// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {console} from "forge-std/Script.sol";
import {Abv1SwapForkBase} from "./Abv1SwapForkBase.sol";
import {CnStakingV4} from "../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {CnStakingV4Factory} from "../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";

/// @dev Minimal stub for CnStakingV2 multisig functions on mainnet.
///      ABI-compatible with the V3MultiSig variant — Functions enum is uint8-encoded.
interface IMainnetV2 {
    function staking() external view returns (uint256);
    function unstaking() external view returns (uint256);
    function withdrawalRequestCount() external view returns (uint256);
    function requestCount() external view returns (uint256);
    function requirement() external view returns (uint256);
    function getState()
        external
        view
        returns (
            address contractValidator,
            address nodeIdAddr,
            address rewardAddr,
            address[] memory adminList,
            uint256 requirement,
            uint256[] memory pendingRequestList,
            uint256 jailUntil,
            bool isInitialized,
            bool isAbookActivated
        );

    function submitApproveStakingWithdrawal(address to, uint256 value) external;
    function confirmRequest(uint256 id, uint8 functionId, bytes32 a1, bytes32 a2, bytes32 a3) external;
    function withdrawApprovedStaking(uint256 id) external;
}

/// @title Abv1V2SwapFork
/// @notice PD-off scenario for CnStakingV2 GCs: V2 admin multisig unstakes the entire
///         balance, transfers to a freshly deployed V4, then performs the ABv1 swap.
///         Same migration pattern as Abv1SwapFork (V3 PD-off); only the V3 ↔ V2 contract
///         interface differs.
///
/// Targets: V2 GCs with EOA reward addresses (12 out of 27 V2 entries on mainnet).
///          V2 GCs with self-vault reward (Kommuendo-like, 15/27) are a separate track.
///
/// Usage:
///   forge script script/Abv1V2SwapFork.s.sol \
///     --fork-url https://public-en.node.kaia.io -vv
contract Abv1V2SwapFork is Abv1SwapForkBase {
    // V2 PD-off target (effective 9.6M, EOA reward)
    address internal constant TARGET_NODE_ID_ = 0x6A7aCac3634348222843066cDAa7D860BBf62EeF;
    address internal constant TARGET_V2_      = 0x163CE1C953aEA99Dc70496066D268b45bB8278A4;
    address internal constant TARGET_REWARD   = 0x842aB31AB877b67A7636927580d83c5ee561C981;

    /// @dev `Functions.ApproveStakingWithdrawal` index in CnStakingV2's Functions enum
    ///      (ICnStakingV2.sol:116-128 — same position 6 as the V3MultiSig variant).
    uint8 internal constant FN_APPROVE_STAKING_WITHDRAWAL = 6;

    constructor() Abv1SwapForkBase(TARGET_NODE_ID_, TARGET_V2_) {}

    function _logInitialState() internal view override {
        IMainnetV2 v2 = IMainnetV2(TARGET_OLD_CN);
        console.log("=== Initial mainnet state ===");
        console.log("V2 staking (KAIA):", v2.staking() / 1e18);
        console.log("V2 balance (KAIA):", TARGET_OLD_CN.balance / 1e18);
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

    /// @dev Drives V2 multisig. Identical flow to V3MultiSig variant:
    ///   1) admin[0] submits — creates request + auto-confirms.
    ///   2) admins[1..quorum-1] confirm; (quorum-1)-th confirmation triggers inline execute
    ///      → V2.approveStakingWithdrawal under address(this).
    ///   3) Warp past STAKE_LOCKUP.
    ///   4) Any single admin calls withdrawApprovedStaking — onlyAdmin guard (CnStakingV2.sol:859).
    function _extractFromV3() internal override returns (address recipient, uint256 amount) {
        IMainnetV2 v2 = IMainnetV2(TARGET_OLD_CN);
        (address[] memory admins, uint256 quorum) = _fetchV2Admins(v2);

        // V2.approveStakingWithdrawal precondition: unstaking + value <= staking
        // (CnStakingV2.sol:500-501). staking is free-stake only; initial lockup pool is separate.
        amount = v2.staking() - v2.unstaking();
        recipient = makeAddr("gcEoa");

        uint256 withdrawalId = v2.withdrawalRequestCount();
        uint256 multisigId = v2.requestCount();
        console.log("=== Unstaking from V2 ===");
        console.log("Amount (KAIA):", amount / 1e18);

        vm.prank(admins[0]);
        v2.submitApproveStakingWithdrawal(recipient, amount);

        bytes32 toArg = bytes32(uint256(uint160(recipient)));
        bytes32 valueArg = bytes32(amount);
        for (uint256 i = 1; i < quorum; ++i) {
            vm.prank(admins[i]);
            v2.confirmRequest(multisigId, FN_APPROVE_STAKING_WITHDRAWAL, toArg, valueArg, 0);
        }

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(admins[0]);
        v2.withdrawApprovedStaking(withdrawalId);

        console.log("Recipient balance after withdraw (KAIA):", recipient.balance / 1e18);
        console.log("V2 balance after withdraw (KAIA):", TARGET_OLD_CN.balance / 1e18);
    }

    /// @dev PD-off V4's `receive()` is open. Direct send works.
    function _injectToV4(address from, CnStakingV4 v4, address /*reward*/, uint256 amount) internal override {
        vm.prank(from);
        (bool ok,) = address(v4).call{value: amount}("");
        require(ok, "V4 receive failed");
        console.log("V4 balance after inject (KAIA):", address(v4).balance / 1e18);
    }

    /// @dev V2 must be left holding only the untouched initial-lockup pool (~10 KAIA bound).
    function _verifyScenario() internal view override {
        require(TARGET_OLD_CN.balance <= 10 ether, "V2 leftover too large");
    }

    /// @dev V2 admins come from getState() — no AccessControl in V2 multisig variant.
    function _fetchV2Admins(IMainnetV2 v2) internal view returns (address[] memory admins, uint256 quorum) {
        (, , , address[] memory all, uint256 req, , , , ) = v2.getState();
        quorum = req;
        admins = new address[](quorum);
        for (uint256 i; i < quorum; ++i) {
            admins[i] = all[i];
        }
    }
}
