// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {console} from "forge-std/Script.sol";
import {ABv1SwapForkBase} from "./ABv1SwapForkBase.sol";
import {CnStakingV4} from "../../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {CnStakingV4Factory} from "../../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";

/// @dev Subset of the CnStakingV2/V3MultiSig surface that the PD-off migration drives.
///      Both contracts expose the same Functions enum (ApproveStakingWithdrawal = 6) and
///      identical submit/confirm/withdraw signatures (ICnStakingV2.sol vs
///      ICnStakingV3MultiSig.sol). Only the admin getter differs.
interface IMainnetMultiSig {
    function staking() external view returns (uint256);
    function unstaking() external view returns (uint256);
    function withdrawalRequestCount() external view returns (uint256);
    function requestCount() external view returns (uint256);

    function submitApproveStakingWithdrawal(address to, uint256 value) external;
    function confirmRequest(uint256 id, uint8 functionId, bytes32 a1, bytes32 a2, bytes32 a3) external;
    function withdrawApprovedStaking(uint256 id) external;
}

/// @title ABv1PdOffMultiSigForkBase
/// @notice Shared PD-off multisig migration flow for CnStakingV2 and CnStakingV3 GCs.
///         Implements every step that is identical between V2 and V3 — children only
///         supply scenario constants and the admin getter (`_fetchAdmins`).
abstract contract ABv1PdOffMultiSigForkBase is ABv1SwapForkBase {
    /// @dev `Functions.ApproveStakingWithdrawal` enum index — position 6 in both
    ///      ICnStakingV3MultiSig.sol:46-59 and ICnStakingV2.sol:116-128.
    uint8 internal constant FN_APPROVE_STAKING_WITHDRAWAL = 6;

    /// @dev Legacy ABv1 reward EOA — preserved across the swap.
    address internal immutable TARGET_REWARD;

    /// @dev Legacy cnStaking viewed through the common multisig ABI.
    IMainnetMultiSig internal immutable LEGACY;

    /// @dev Label used in opening/extraction logs ("V2", "V3", ...).
    string internal LEGACY_LABEL;

    constructor(address _nodeId, address _oldCn, address _reward, string memory _label)
        ABv1SwapForkBase(_nodeId, _oldCn)
    {
        TARGET_REWARD = _reward;
        LEGACY = IMainnetMultiSig(_oldCn);
        LEGACY_LABEL = _label;
    }

    function _logInitialState() internal view override {
        console.log("=== Initial mainnet state ===");
        console.log(string.concat(LEGACY_LABEL, " staking (KAIA):"), LEGACY.staking() / 1e18);
        console.log(string.concat(LEGACY_LABEL, " balance (KAIA):"), TARGET_OLD_CN.balance / 1e18);
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

    /// @dev Common V2/V3 PD-off multisig flow:
    ///   1) admin[0] submits — creates request and auto-confirms.
    ///   2) admins[1..quorum-1] confirm; (quorum-1)-th confirmation runs `_executeRequest`
    ///      inline → cn.approveStakingWithdrawal under address(this).
    ///   3) Warp past the 7-day STAKE_LOCKUP.
    ///   4) Any admin calls withdrawApprovedStaking (onlyAdmin in V2; per-admin
    ///      UNSTAKING_CLAIMER_ROLE in V3 PD-off).
    ///
    /// `amount = staking() - unstaking()` is the max value the legacy contract accepts
    /// (V2/V3 approveStakingWithdrawal precondition). The initial-lockup pool is a
    /// separate flow (submitWithdrawLockupStaking) and is left behind.
    function _extractFromV3() internal override returns (address recipient, uint256 amount) {
        (address[] memory admins, uint256 quorum) = _fetchAdmins();

        amount = LEGACY.staking() - LEGACY.unstaking();
        recipient = makeAddr("gcEoa");

        uint256 withdrawalId = LEGACY.withdrawalRequestCount();
        uint256 multisigId = LEGACY.requestCount();
        console.log(string.concat("=== Unstaking from ", LEGACY_LABEL, " ==="));
        console.log("Amount (KAIA):", amount / 1e18);

        vm.prank(admins[0]);
        LEGACY.submitApproveStakingWithdrawal(recipient, amount);

        bytes32 toArg = bytes32(uint256(uint160(recipient)));
        bytes32 valueArg = bytes32(amount);
        for (uint256 i = 1; i < quorum; ++i) {
            vm.prank(admins[i]);
            LEGACY.confirmRequest(multisigId, FN_APPROVE_STAKING_WITHDRAWAL, toArg, valueArg, 0);
        }

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(admins[0]);
        LEGACY.withdrawApprovedStaking(withdrawalId);

        console.log("Recipient balance after withdraw (KAIA):", recipient.balance / 1e18);
        console.log(string.concat(LEGACY_LABEL, " balance after withdraw (KAIA):"), TARGET_OLD_CN.balance / 1e18);
    }

    /// @dev PD-off V4's `receive()` is open (CnStakingV4.sol:84-89 `_onlyStaker` returns
    ///      silently when publicDelegation is unset). Direct send works.
    function _injectToV4(address from, CnStakingV4 v4, address /*reward*/, uint256 amount) internal override {
        vm.prank(from);
        (bool ok,) = address(v4).call{value: amount}("");
        require(ok, "V4 receive failed");
        console.log("V4 balance after inject (KAIA):", address(v4).balance / 1e18);
    }

    /// @dev Legacy cnStaking should be left holding only the untouched initial-lockup pool.
    function _verifyScenario() internal view override {
        require(TARGET_OLD_CN.balance <= 10 ether, "legacy leftover too large");
    }

    /// @dev Scenario-specific admin getter (V2: getState 9-tuple; V3: AccessControl).
    function _fetchAdmins() internal view virtual returns (address[] memory admins, uint256 quorum);
}
