// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CnStakingV4} from "../../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {PublicDelegation} from "../../src/PublicDelegation/PublicDelegation.sol";
import {CnStakingV4Factory} from "../../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";

interface IAddressBookV1 {
    function getState() external view returns (address[] memory adminList, uint256 requirement);
    function getCnInfo(address cnNodeId) external view returns (address, address, address);
    function getAllAddressInfo() external view returns (address[] memory, address[] memory, address[] memory, address, address);
    function submitRegisterCnStakingContract(address cnNodeId, address cnStaking, address rewardAddr) external;
    function submitUnregisterCnStakingContract(address cnNodeId) external;
}

/// @title ABv1SwapForkBase
/// @notice Shared scaffolding for V3 → V4 mainnet-fork swap rehearsals.
///         Implements the parts that don't change across scenarios:
///         V4 infra deploy, setLegacyAbv1Info, ABv1 multisig swap, common verification.
///
/// Subclasses fill in five scenario hooks:
///   _logInitialState : scenario-specific opening dump
///   _deployV4        : how to instantiate V4 (with/without PD V2) and pick the reward
///   _extractFromV3   : how to free funds from V3 (admin multisig vs PD.redeem etc.)
///   _injectToV4      : how to put those funds into V4 (cn.delegate vs PD.stake etc.)
///   _verifyScenario  : extra post-swap invariants specific to the scenario
abstract contract ABv1SwapForkBase is Script {
    address internal constant ADDRESS_BOOK = 0x0000000000000000000000000000000000000400;
    uint256 internal constant MIN_STAKE = 5_000_000 ether;

    address internal immutable TARGET_NODE_ID;
    /// @dev The legacy cnStaking address registered in ABv1 (V2 or V3) that gets unregistered
    ///      during the swap. Kept generic so the same base supports both V2 and V3 scenarios.
    address internal immutable TARGET_OLD_CN;

    IAddressBookV1 internal abv1 = IAddressBookV1(ADDRESS_BOOK);

    constructor(address _nodeId, address _oldCn) {
        TARGET_NODE_ID = _nodeId;
        TARGET_OLD_CN = _oldCn;
    }

    /* ========== TEMPLATE ========== */

    function run() external {
        _logInitialState();

        CnStakingV4Factory factory = _deployFactory();
        address gcOwner = makeAddr("gcOwner");
        (CnStakingV4 v4, address reward) = _deployV4(factory, gcOwner);

        (address from, uint256 amount) = _extractFromV3();
        _injectToV4(from, v4, reward, amount);

        _setLegacy(gcOwner, v4, reward);
        _swapAbv1(address(v4), reward);

        _verifyCommon(address(v4), reward, amount);
        _verifyScenario();

        console.log("=== SUCCESS ===");
    }

    /* ========== SHARED STEPS ========== */

    /// @dev Deploys the patched V4 implementation + PD V2 implementation + beacons + factory.
    ///      No StakingTracker mocking — mainnet's V1 tracker returns early in updateTracker
    ///      when called with an unregistered staking contract (StakingTracker.sol:175-178).
    function _deployFactory() internal returns (CnStakingV4Factory factory) {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        CnStakingV4 cnImpl = new CnStakingV4();
        PublicDelegation pdImpl = new PublicDelegation();
        UpgradeableBeacon cnBeacon = new UpgradeableBeacon(address(cnImpl), deployer);
        UpgradeableBeacon pdBeacon = new UpgradeableBeacon(address(pdImpl), deployer);
        factory = new CnStakingV4Factory(address(cnBeacon), address(pdBeacon));
        vm.stopPrank();
        console.log("Factory:", address(factory));
    }

    function _setLegacy(address gcOwner, CnStakingV4 v4, address reward) internal {
        vm.prank(gcOwner);
        v4.setLegacyAbv1Info(TARGET_NODE_ID, reward);
        console.log("V4.nodeId:", v4.nodeId());
        console.log("V4.rewardAddress:", v4.rewardAddress());
        console.log("V4.isInitialized:", v4.isInitialized());
    }

    /// @dev ABv1 swap: unregister V3 then register V4 under the same nodeId.
    ///      Mainnet ABv1 currently has 2 admins, requirement=1 → each submit hits quorum inline.
    function _swapAbv1(address v4, address reward) internal {
        (address[] memory admins, uint256 quorum) = abv1.getState();

        for (uint256 i = 0; i < quorum; ++i) {
            vm.prank(admins[i]);
            abv1.submitUnregisterCnStakingContract(TARGET_NODE_ID);
        }
        console.log("ABv1 V3 unregister done");

        for (uint256 i = 0; i < quorum; ++i) {
            vm.prank(admins[i]);
            abv1.submitRegisterCnStakingContract(TARGET_NODE_ID, v4, reward);
        }
        console.log("ABv1 V4 register done");
    }

    /// @dev Post-swap invariants common to every scenario:
    ///   - getCnInfo(nodeId) maps to (nodeId, V4, reward)
    ///   - cnStakingContractList drops V3 and contains V4
    ///   - V4.balance >= MIN_STAKE (ABv1 era reader, MultiCallContract.sol:180-184)
    ///   - V4.staking() >= expectedStake (tracks the funds we just injected)
    function _verifyCommon(address v4, address reward, uint256 expectedStake) internal view {
        (address gotNodeId, address gotStaking, address gotReward) = abv1.getCnInfo(TARGET_NODE_ID);
        require(gotNodeId == TARGET_NODE_ID, "nodeId mismatch");
        require(gotStaking == v4, "V4 not registered");
        require(gotReward == reward, "reward mismatch");

        (, address[] memory list, , , ) = abv1.getAllAddressInfo();
        bool v3Found;
        bool v4Found;
        for (uint256 i = 0; i < list.length; ++i) {
            if (list[i] == TARGET_OLD_CN) v3Found = true;
            if (list[i] == v4) v4Found = true;
        }
        require(!v3Found, "V3 still in list");
        require(v4Found, "V4 missing from list");

        uint256 v4Balance = v4.balance;
        uint256 v4Staking = CnStakingV4(payable(v4)).staking();
        require(v4Balance >= MIN_STAKE, "V4 below MinStake");
        require(v4Staking >= expectedStake, "V4 staking() < expected");
        console.log("V4 balance / staking (KAIA):", v4Balance / 1e18, v4Staking / 1e18);
    }

    /* ========== HOOKS ========== */

    function _logInitialState() internal view virtual;

    function _deployV4(CnStakingV4Factory factory, address gcOwner)
        internal
        virtual
        returns (CnStakingV4 v4, address reward);

    function _extractFromV3() internal virtual returns (address recipient, uint256 amount);

    function _injectToV4(address from, CnStakingV4 v4, address reward, uint256 amount) internal virtual;

    function _verifyScenario() internal view virtual;
}
