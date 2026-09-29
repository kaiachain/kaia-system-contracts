// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CnStakingV4} from "../../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {PublicDelegation} from "../../src/PublicDelegation/PublicDelegation.sol";
import {CnStakingV4Factory} from "../../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";

interface IAddressBookV1 {
    function getState() external view returns (address[] memory adminList, uint256 requirement);
    function getCnInfo(address cnNodeId) external view returns (address, address, address);
    function getAllAddressInfo()
        external
        view
        returns (address[] memory, address[] memory, address[] memory, address, address);
    function submitRegisterCnStakingContract(address cnNodeId, address cnStaking, address rewardAddr) external;
    function submitUnregisterCnStakingContract(address cnNodeId) external;
    function submitAddAdmin(address admin) external;
    function submitDeleteAdmin(address admin) external;
}

/// @title ABv1ForkCommon
/// @notice Shared ABv1-era helpers for mainnet-fork rehearsals: V4 infra deployment,
///         legacy identity carry-over, and the ABv1 multisig registration swap.
///         Used by the full-migration rehearsal (MainnetFullMigrationFork); the per-GC swap
///         rehearsals (ABv1SwapForkBase) keep their own copies of these helpers.
abstract contract ABv1ForkCommon is Script {
    address internal constant ADDRESS_BOOK = 0x0000000000000000000000000000000000000400;
    uint256 internal constant MIN_STAKE = 5_000_000 ether;

    /// @dev `Functions.ApproveStakingWithdrawal` enum index — identical position in
    ///      ICnStakingV2.sol (116-128) and ICnStakingV3MultiSig.sol (46-59).
    uint8 internal constant FN_APPROVE_STAKING_WITHDRAWAL = 6;

    IAddressBookV1 internal abv1 = IAddressBookV1(ADDRESS_BOOK);

    /// @dev Deploys the V4 implementation + PD implementation + both beacons + factory.
    ///      `beaconOwner` controls beacon upgrades — on a real deployment this must be the
    ///      Voting contract, since beacon upgrades affect every deployed proxy at once
    ///      (see DeployBeaconsAndFactory.s.sol).
    function _deployV4Infra(address deployer, address beaconOwner) internal returns (CnStakingV4Factory factory) {
        vm.startPrank(deployer);
        CnStakingV4 cnImpl = new CnStakingV4();
        PublicDelegation pdImpl = new PublicDelegation();
        UpgradeableBeacon cnBeacon = new UpgradeableBeacon(address(cnImpl), beaconOwner);
        UpgradeableBeacon pdBeacon = new UpgradeableBeacon(address(pdImpl), beaconOwner);
        factory = new CnStakingV4Factory(address(cnBeacon), address(pdBeacon));
        vm.stopPrank();
    }

    /// @dev Carries the legacy ABv1 identity into a V4 — required by ABv1's registration
    ///      validation (nodeId/rewardAddress/isInitialized checks in registerCnStakingContract).
    function _setLegacyInfo(address gcOwner, CnStakingV4 v4, address nodeId, address reward) internal {
        vm.prank(gcOwner);
        v4.setLegacyAbv1Info(nodeId, reward);
    }

    /// @dev Unregisters a node's current CnStaking in ABv1 via the AB admin multisig
    ///      (`requirement` confirmations; requirement=1 on mainnet today).
    function _unregisterAbv1Node(address nodeId) internal {
        (address[] memory admins, uint256 quorum) = abv1.getState();
        for (uint256 i = 0; i < quorum; ++i) {
            vm.prank(admins[i]);
            abv1.submitUnregisterCnStakingContract(nodeId);
        }
    }

    /// @dev Registers a staking contract for a node in ABv1 via the AB admin multisig.
    function _registerAbv1Node(address nodeId, address staking, address reward) internal {
        (address[] memory admins, uint256 quorum) = abv1.getState();
        for (uint256 i = 0; i < quorum; ++i) {
            vm.prank(admins[i]);
            abv1.submitRegisterCnStakingContract(nodeId, staking, reward);
        }
    }

    /// @dev Full swap for one node: unregister the old CnStaking, register the new one
    ///      under the same nodeId, and verify the mapping took effect.
    function _swapAbv1Node(address nodeId, address newStaking, address reward) internal {
        _unregisterAbv1Node(nodeId);
        _registerAbv1Node(nodeId, newStaking, reward);
        (, address registered,) = abv1.getCnInfo(nodeId);
        require(registered == newStaking, "ABv1 swap failed");
    }
}
