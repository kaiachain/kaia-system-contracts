// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {ABv1PdOffMultiSigForkBase} from "./ABv1PdOffMultiSigForkBase.sol";

/// @dev Narrow view of CnStakingV3MultiSig — only the AccessControl-based admin getter
///      that the V2 surface does not share. Multisig submit/confirm/withdraw come from
///      the parent's `IMainnetMultiSig` interface.
interface IMainnetV3AdminGetter {
    function requirement() external view returns (uint256);
    function ADMIN_ROLE() external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
}

/// @title ABv1V3SwapFork
/// @notice PD-off CnStakingV3 GC mainnet-fork swap rehearsal. Reuses the entire migration
///         flow from `ABv1PdOffMultiSigForkBase`; only the AccessControl admin lookup is
///         scenario-specific.
///
/// Usage:
///   forge script script/ABv1V3SwapFork.s.sol \
///     --fork-url https://public-en.node.kaia.io -vv
contract ABv1V3SwapFork is ABv1PdOffMultiSigForkBase {
    // GC #5 in cnNodeIdList — V3 PD off, ~14.7M staking, multisig requirement = 3
    address internal constant TARGET_NODE_ID_ = 0x6Cd6261c8bE831ee79dA184BeAac962F6c8ee634;
    address internal constant TARGET_V3_      = 0x7dc397C45Ea4468c180fC010E69091B6D38846dF;
    address internal constant TARGET_REWARD_  = 0xF786C3720A10cb48c8F12d0AC2086dCF227c7CDe;

    constructor() ABv1PdOffMultiSigForkBase(TARGET_NODE_ID_, TARGET_V3_, TARGET_REWARD_, "V3") {}

    /// @dev V3 admins are held under AccessControl `ADMIN_ROLE`; `requirement()` is the
    ///      multisig quorum. Granted-member count is >= requirement, so iterating
    ///      `[0, quorum)` yields enough admins to drive the multisig.
    function _fetchAdmins() internal view override returns (address[] memory admins, uint256 quorum) {
        IMainnetV3AdminGetter v3 = IMainnetV3AdminGetter(TARGET_OLD_CN);
        quorum = v3.requirement();
        bytes32 adminRole = v3.ADMIN_ROLE();
        admins = new address[](quorum);
        for (uint256 i = 0; i < quorum; ++i) {
            admins[i] = v3.getRoleMember(adminRole, i);
        }
    }
}
