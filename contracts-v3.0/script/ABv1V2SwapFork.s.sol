// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {ABv1PdOffMultiSigForkBase} from "./ABv1PdOffMultiSigForkBase.sol";

/// @dev Narrow view of CnStakingV2 — only the `getState()` admin getter that the V3
///      surface does not share. Multisig submit/confirm/withdraw come from the parent's
///      `IMainnetMultiSig` interface.
interface IMainnetV2AdminGetter {
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
}

/// @title ABv1V2SwapFork
/// @notice PD-off CnStakingV2 GC mainnet-fork swap rehearsal. Reuses the entire migration
///         flow from `ABv1PdOffMultiSigForkBase`; only the `getState()`-based admin lookup
///         is scenario-specific.
///
/// Targets: V2 GCs with EOA reward addresses (12 out of 27 V2 entries on mainnet).
///          V2 GCs with self-vault reward (Kommuendo-like, 15/27) are out of scope.
///
/// Usage:
///   forge script script/ABv1V2SwapFork.s.sol \
///     --fork-url https://public-en.node.kaia.io -vv
contract ABv1V2SwapFork is ABv1PdOffMultiSigForkBase {
    // V2 PD-off target (effective 9.6M, EOA reward)
    address internal constant TARGET_NODE_ID_ = 0x6A7aCac3634348222843066cDAa7D860BBf62EeF;
    address internal constant TARGET_V2_      = 0x163CE1C953aEA99Dc70496066D268b45bB8278A4;
    address internal constant TARGET_REWARD_  = 0x842aB31AB877b67A7636927580d83c5ee561C981;

    constructor() ABv1PdOffMultiSigForkBase(TARGET_NODE_ID_, TARGET_V2_, TARGET_REWARD_, "V2") {}

    /// @dev V2 admins come from the `getState()` 9-tuple (no AccessControl); `requirement`
    ///      field is the multisig quorum.
    function _fetchAdmins() internal view override returns (address[] memory admins, uint256 quorum) {
        (, , , address[] memory all, uint256 req, , , , ) = IMainnetV2AdminGetter(TARGET_OLD_CN).getState();
        quorum = req;
        admins = new address[](quorum);
        for (uint256 i = 0; i < quorum; ++i) {
            admins[i] = all[i];
        }
    }
}
