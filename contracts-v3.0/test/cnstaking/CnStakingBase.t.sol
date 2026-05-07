// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CnStakingV4} from "../../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {ICnStaking} from "../../src/CnStaking/CnStakingV4/interfaces/ICnStaking.sol";
import {CnStakingV4Factory} from "../../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";
import {PublicDelegation} from "../../src/PublicDelegation/PublicDelegation.sol";
import {IPublicDelegation} from "../../src/PublicDelegation/interfaces/IPublicDelegation.sol";

/// @title CnStakingBase
/// @notice Test base for CnStakingV4 and PublicDelegation tests.
///         Sets up beacons, factory, and mocks for system contracts.
contract CnStakingBase is Test {
    /* ========== SYSTEM ADDRESSES ========== */

    address internal constant REGISTRY = address(0x401);

    /* ========== CONSTANTS ========== */

    uint256 internal constant STAKE_LOCKUP = 1 weeks;
    uint256 internal constant INITIAL_LOCKUP = 1e9;

    /* ========== BEACONS & FACTORY ========== */

    UpgradeableBeacon internal cnBeacon;
    UpgradeableBeacon internal pdBeacon;
    CnStakingV4Factory internal factory;

    /* ========== TEST ACCOUNTS ========== */

    address internal owner;
    address internal beaconOwner;
    address internal commissionTo;
    address internal stakingTracker;
    address internal user1;
    address internal user2;

    /* ========== SETUP ========== */

    function setUp() public virtual {
        owner = makeAddr("owner");
        beaconOwner = makeAddr("beaconOwner");
        commissionTo = makeAddr("commissionTo");
        stakingTracker = makeAddr("stakingTracker");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy implementations
        CnStakingV4 cnImpl = new CnStakingV4();
        PublicDelegation pdImpl = new PublicDelegation();

        // Deploy beacons
        cnBeacon = new UpgradeableBeacon(address(cnImpl), beaconOwner);
        pdBeacon = new UpgradeableBeacon(address(pdImpl), beaconOwner);

        // Deploy factory
        factory = new CnStakingV4Factory(address(cnBeacon), address(pdBeacon));

        // Mock system contracts
        _mockRegistry();
        _mockStakingTracker();
    }

    /* ========== MOCK HELPERS ========== */

    /// @dev Mock Registry at 0x401: getActiveAddr("StakingTracker") → stakingTracker,
    ///      getActiveAddr("CnStakingFactory") → factory address.
    function _mockRegistry() internal {
        vm.mockCall(
            REGISTRY,
            abi.encodeWithSignature("getActiveAddr(string)", "StakingTracker"),
            abi.encode(stakingTracker)
        );
        vm.mockCall(
            REGISTRY,
            abi.encodeWithSignature("getActiveAddr(string)", "CnStakingFactory"),
            abi.encode(address(factory))
        );
    }

    /// @dev Mock StakingTracker: refreshStake(address) is no-op
    function _mockStakingTracker() internal {
        vm.mockCall(stakingTracker, abi.encodeWithSignature("refreshStake(address)"), "");
    }

    /* ========== DEPLOYMENT HELPERS ========== */

    /// @notice Deploy CnStakingV4 proxy without PD via factory
    function _deployCnStaking(address _owner) internal returns (CnStakingV4) {
        address proxy = factory.deployCnStaking(_owner);
        return CnStakingV4(payable(proxy));
    }

    /// @notice Deploy CnStakingV4 + PublicDelegation proxies via factory
    function _deployCnStakingWithPD(
        address _owner,
        IPublicDelegation.PDConstructorArgs memory _pdArgs
    ) internal returns (CnStakingV4 cnStaking, PublicDelegation pd) {
        (address cnProxy, address pdProxy) = factory.deployCnStakingWithPD{value: INITIAL_LOCKUP}(_owner, _pdArgs);
        cnStaking = CnStakingV4(payable(cnProxy));
        pd = PublicDelegation(payable(pdProxy));
    }

    /// @notice Convenience: deploy CnStaking+PD with default args
    function _deployCnStakingWithPDDefaults() internal returns (CnStakingV4 cnStaking, PublicDelegation pd) {
        return
            _deployCnStakingWithPD(
                owner,
                IPublicDelegation.PDConstructorArgs({
                    owner: owner,
                    commissionTo: commissionTo,
                    commissionRate: 1000, // 10%
                    gcName: "TestGC"
                })
            );
    }

    /// @notice Deal KAIA and stake via PD
    function _stakeViaPD(PublicDelegation _pd, address _user, uint256 _amount) internal {
        vm.deal(_user, _amount);
        vm.prank(_user);
        _pd.stake{value: _amount}();
    }

    /// @notice Simulate block reward by sending KAIA to PD
    function _simulateReward(PublicDelegation _pd, uint256 _amount) internal {
        vm.deal(address(_pd), address(_pd).balance + _amount);
    }
}
