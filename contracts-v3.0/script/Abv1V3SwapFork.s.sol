// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {console} from "forge-std/Script.sol";
import {Abv1SwapForkBase} from "./Abv1SwapForkBase.sol";
import {CnStakingV4} from "../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {CnStakingV4Factory} from "../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";

/// @dev Minimal stub for the existing CnStakingV3 MultiSig variant on mainnet.
///      `confirmRequest`'s `uint8 functionId` matches the canonical ABI encoding of the
///      Functions enum parameter (Solidity encodes small enums as uint8).
interface IMainnetV3 {
    function staking() external view returns (uint256);
    function unstaking() external view returns (uint256);
    function withdrawalRequestCount() external view returns (uint256);
    function requestCount() external view returns (uint256);
    function requirement() external view returns (uint256);
    function ADMIN_ROLE() external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);

    function submitApproveStakingWithdrawal(address to, uint256 value) external;
    function confirmRequest(uint256 id, uint8 functionId, bytes32 a1, bytes32 a2, bytes32 a3) external;
    function withdrawApprovedStaking(uint256 id) external;
}

/// @title Abv1V3SwapFork
/// @notice PD-off scenario: V3 admin multisig unstakes the entire balance, transfers it
///         to a freshly deployed PD-off V4, then performs the ABv1 swap. Same-capital
///         migration with no dual staking.
///
/// Usage:
///   forge script script/Abv1V3SwapFork.s.sol \
///     --fork-url https://public-en.node.kaia.io -vv
contract Abv1V3SwapFork is Abv1SwapForkBase {
    // GC #5 in cnNodeIdList — V3 PD off, ~14.7M staking, multisig requirement = 3
    address internal constant TARGET_NODE_ID_ = 0x6Cd6261c8bE831ee79dA184BeAac962F6c8ee634;
    address internal constant TARGET_V3_      = 0x7dc397C45Ea4468c180fC010E69091B6D38846dF;
    address internal constant TARGET_REWARD   = 0xF786C3720A10cb48c8F12d0AC2086dCF227c7CDe;

    /// @dev `Functions.ApproveStakingWithdrawal` index in the V3MultiSig enum
    ///      (ICnStakingV3MultiSig.sol:46-59 — 6th entry).
    uint8 internal constant FN_APPROVE_STAKING_WITHDRAWAL = 6;

    constructor() Abv1SwapForkBase(TARGET_NODE_ID_, TARGET_V3_) {}

    function _logInitialState() internal view override {
        IMainnetV3 v3 = IMainnetV3(TARGET_OLD_CN);
        console.log("=== Initial mainnet state ===");
        console.log("V3 staking (KAIA):", v3.staking() / 1e18);
        console.log("V3 balance (KAIA):", TARGET_OLD_CN.balance / 1e18);
    }

    /// @dev PD-off V4 deploy. Reward stays the legacy ABv1 reward EOA.
    function _deployV4(CnStakingV4Factory factory, address gcOwner)
        internal
        override
        returns (CnStakingV4 v4, address reward)
    {
        vm.prank(gcOwner);
        address proxy = factory.deployCnStaking(gcOwner);
        v4 = CnStakingV4(payable(proxy));
        reward = TARGET_REWARD;
        console.log("V4 proxy:", proxy);
    }

    /// @dev Drives V3 multisig:
    ///   1) admin[0] submits — creates multisig request and auto-confirms.
    ///   2) admins[1..quorum-1] confirm; the (quorum-1)-th confirmation runs `_executeRequest`
    ///      inline which calls V3.approveStakingWithdrawal under address(this) — the holder
    ///      of UNSTAKING_APPROVER_ROLE in V3MultiSig (PD off, CnStakingV3MultiSig.sol:149).
    ///   3) Warp past 7-day STAKE_LOCKUP (claim window [+7d, +14d]).
    ///   4) Any single admin claims — UNSTAKING_CLAIMER_ROLE is per-admin in PD-off.
    function _extractFromV3() internal override returns (address recipient, uint256 amount) {
        IMainnetV3 v3 = IMainnetV3(TARGET_OLD_CN);
        (address[] memory admins, uint256 quorum) = _fetchV3Admins(v3);

        // Max value V3 accepts = staking - unstaking (V3.approveStakingWithdrawal precond).
        // Subtracting unstaking guards against any pending withdrawal at fork time.
        // Initial-lockup pool is a separate flow (submitWithdrawLockupStaking) and is left behind.
        amount = v3.staking() - v3.unstaking();
        recipient = makeAddr("gcEoa");

        uint256 withdrawalId = v3.withdrawalRequestCount();
        uint256 multisigId = v3.requestCount();
        console.log("=== Unstaking from V3 ===");
        console.log("Amount (KAIA):", amount / 1e18);

        vm.prank(admins[0]);
        v3.submitApproveStakingWithdrawal(recipient, amount);

        bytes32 toArg = bytes32(uint256(uint160(recipient)));
        bytes32 valueArg = bytes32(amount);
        for (uint256 i = 1; i < quorum; ++i) {
            vm.prank(admins[i]);
            v3.confirmRequest(multisigId, FN_APPROVE_STAKING_WITHDRAWAL, toArg, valueArg, 0);
        }

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(admins[0]);
        v3.withdrawApprovedStaking(withdrawalId);

        console.log("Recipient balance after withdraw (KAIA):", recipient.balance / 1e18);
        console.log("V3 balance after withdraw (KAIA):", TARGET_OLD_CN.balance / 1e18);
    }

    /// @dev PD-off V4's `receive()` is open (CnStakingV4.sol:84-89 `_onlyStaker` returns
    ///      silently when publicDelegation is unset). Direct send works.
    function _injectToV4(address from, CnStakingV4 v4, address /*reward*/, uint256 amount) internal override {
        vm.prank(from);
        (bool ok,) = address(v4).call{value: amount}("");
        require(ok, "V4 receive failed");
        console.log("V4 balance after inject (KAIA):", address(v4).balance / 1e18);
    }

    /// @dev V3 must be left holding only the untouched initial-lockup pool
    ///      (~1 KAIA on this target — bounded loosely at 10).
    function _verifyScenario() internal view override {
        require(TARGET_OLD_CN.balance <= 10 ether, "V3 leftover too large");
    }

    function _fetchV3Admins(IMainnetV3 v3) internal view returns (address[] memory admins, uint256 quorum) {
        quorum = v3.requirement();
        bytes32 adminRole = v3.ADMIN_ROLE();
        admins = new address[](quorum);
        for (uint256 i = 0; i < quorum; ++i) {
            admins[i] = v3.getRoleMember(adminRole, i);
        }
    }
}
