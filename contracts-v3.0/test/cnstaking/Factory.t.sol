// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CnStakingBase} from "./CnStakingBase.t.sol";
import {CnStakingV4} from "../../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {ICnStaking} from "../../src/CnStaking/CnStakingV4/interfaces/ICnStaking.sol";
import {CnStakingV4Factory} from "../../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";
import {ICnStakingV4Factory} from "../../src/CnStaking/CnStakingV4Factory/interfaces/ICnStakingV4Factory.sol";
import {PublicDelegation} from "../../src/PublicDelegation/PublicDelegation.sol";
import {IPublicDelegation} from "../../src/PublicDelegation/interfaces/IPublicDelegation.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/* ================================================================
 *  Factory Constructor Tests
 * ================================================================ */

contract Factory_Constructor is CnStakingBase {
    function test_constructor_setsBeacons() public view {
        assertEq(factory.cnStakingBeacon(), address(cnBeacon));
        assertEq(factory.pdBeacon(), address(pdBeacon));
    }

    function test_constructor_revertsOnZeroCnBeacon() public {
        vm.expectRevert(ICnStakingV4Factory.ZeroAddress.selector);
        new CnStakingV4Factory(address(0), address(pdBeacon));
    }

    function test_constructor_revertsOnZeroPdBeacon() public {
        vm.expectRevert(ICnStakingV4Factory.ZeroAddress.selector);
        new CnStakingV4Factory(address(cnBeacon), address(0));
    }
}

/* ================================================================
 *  DeployCnStaking Tests
 * ================================================================ */

contract Factory_DeployCnStaking is CnStakingBase {
    function test_deployCnStaking_createsProxy() public {
        address proxy = factory.deployCnStaking(owner);

        CnStakingV4 cn = CnStakingV4(payable(proxy));
        assertEq(cn.owner(), owner);
        assertEq(cn.publicDelegation(), address(0));
    }

    function test_deployCnStaking_emitsEvent() public {
        vm.expectEmit(false, true, true, false);
        emit ICnStakingV4Factory.DeployCnStakingV4(address(0), owner);

        factory.deployCnStaking(owner);
    }

    function test_deployCnStaking_multipleDeploys() public {
        address proxy1 = factory.deployCnStaking(owner);
        address proxy2 = factory.deployCnStaking(makeAddr("owner2"));

        assertTrue(proxy1 != proxy2);
    }

    function test_deployCnStaking_tracksDeployment() public {
        address proxy = factory.deployCnStaking(owner);

        assertTrue(factory.isDeployedCnStaking(proxy));
        assertFalse(factory.isDeployedPublicDelegation(proxy));
        assertEq(factory.getDeployer(proxy), address(this));
    }

    function test_deployCnStaking_isDeterministic() public {
        // Compute expected address via CREATE2
        bytes32 salt = keccak256(abi.encode(address(this), owner));
        bytes memory creationCode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(address(cnBeacon), ""));
        address expected = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(creationCode)))))
        );

        address proxy = factory.deployCnStaking(owner);
        assertEq(proxy, expected);
    }

    function test_deployCnStaking_revertsOnDuplicateDeploy() public {
        factory.deployCnStaking(owner);

        // Same (deployer, owner) → CREATE2 collision. Raw EVM revert — no selector available.
        vm.expectRevert();
        factory.deployCnStaking(owner);
    }

    function test_deployCnStaking_differentDeployerDifferentAddress() public {
        address proxy1 = factory.deployCnStaking(owner);

        address otherDeployer = makeAddr("otherDeployer");
        vm.prank(otherDeployer);
        address proxy2 = factory.deployCnStaking(owner);

        assertTrue(proxy1 != proxy2);
        assertEq(factory.getDeployer(proxy1), address(this));
        assertEq(factory.getDeployer(proxy2), otherDeployer);
    }

    function test_isDeployedCnStaking_falseForNonFactoryDeploy() public view {
        assertFalse(factory.isDeployedCnStaking(address(0x1234)));
    }

    function test_getDeployer_zeroForNonFactoryDeploy() public view {
        assertEq(factory.getDeployer(address(0x1234)), address(0));
    }
}

/* ================================================================
 *  DeployCnStakingWithPD Tests
 * ================================================================ */

contract Factory_DeployCnStakingWithPD is CnStakingBase {
    function test_deployCnStakingWithPD_createsBothProxies() public {
        IPublicDelegation.PDConstructorArgs memory args = IPublicDelegation.PDConstructorArgs({
            owner: owner,
            commissionTo: commissionTo,
            commissionRate: 500,
            gcName: "TestGC"
        });

        (address cnProxy, address pdProxy) = factory.deployCnStakingWithPD{value: INITIAL_LOCKUP}(owner, args);

        CnStakingV4 cn = CnStakingV4(payable(cnProxy));
        PublicDelegation pd = PublicDelegation(payable(pdProxy));

        // CnStaking is correctly initialized
        assertEq(cn.owner(), owner);
        assertEq(cn.publicDelegation(), pdProxy);

        // PD is correctly initialized
        assertEq(pd.baseCnStaking(), cnProxy);
        assertEq(pd.owner(), owner);
        assertEq(pd.commissionTo(), commissionTo);
        assertEq(pd.commissionRate(), 500);
        assertEq(pd.name(), "TestGC Public Delegated KAIA");
        assertEq(pd.symbol(), "TestGC-pdKAIA");
    }

    function test_deployCnStakingWithPD_emitsEvent() public {
        IPublicDelegation.PDConstructorArgs memory args = IPublicDelegation.PDConstructorArgs({
            owner: owner,
            commissionTo: commissionTo,
            commissionRate: 0,
            gcName: "TestGC"
        });

        vm.expectEmit(false, true, true, false);
        emit ICnStakingV4Factory.DeployCnStakingV4WithPD(address(0), owner, address(0));

        factory.deployCnStakingWithPD{value: INITIAL_LOCKUP}(owner, args);
    }

    function test_deployCnStakingWithPD_pdCanStake() public {
        IPublicDelegation.PDConstructorArgs memory args = IPublicDelegation.PDConstructorArgs({
            owner: owner,
            commissionTo: commissionTo,
            commissionRate: 0,
            gcName: "TestGC"
        });

        (address cnProxy, address pdProxy) = factory.deployCnStakingWithPD{value: INITIAL_LOCKUP}(owner, args);
        CnStakingV4 cn = CnStakingV4(payable(cnProxy));
        PublicDelegation pd = PublicDelegation(payable(pdProxy));

        // Stake via PD
        vm.deal(user1, 50 ether);
        vm.prank(user1);
        pd.stake{value: 50 ether}();

        assertEq(cn.staking(), INITIAL_LOCKUP + 50 ether);
        assertEq(pd.balanceOf(user1), 50 ether);
    }

    function test_deployCnStakingWithPD_revertsOnInsufficientStake() public {
        IPublicDelegation.PDConstructorArgs memory args = IPublicDelegation.PDConstructorArgs({
            owner: owner,
            commissionTo: commissionTo,
            commissionRate: 0,
            gcName: "TestGC"
        });

        vm.expectRevert(ICnStakingV4Factory.InsufficientInitialStake.selector);
        factory.deployCnStakingWithPD{value: 0}(owner, args);
    }

    function test_deployCnStakingWithPD_tracksDeployment() public {
        IPublicDelegation.PDConstructorArgs memory args = IPublicDelegation.PDConstructorArgs({
            owner: owner,
            commissionTo: commissionTo,
            commissionRate: 0,
            gcName: "TestGC"
        });

        (address cnProxy, address pdProxy) = factory.deployCnStakingWithPD{value: INITIAL_LOCKUP}(owner, args);

        // CN is tracked as deployed CnStaking
        assertTrue(factory.isDeployedCnStaking(cnProxy));
        assertFalse(factory.isDeployedPublicDelegation(cnProxy));

        // PD is tracked as deployed PublicDelegation
        assertTrue(factory.isDeployedPublicDelegation(pdProxy));
        assertFalse(factory.isDeployedCnStaking(pdProxy));

        // Both have deployer set
        assertEq(factory.getDeployer(cnProxy), address(this));
        assertEq(factory.getDeployer(pdProxy), address(this));
    }

    function test_deployCnStakingWithPD_revertsOnDuplicateDeploy() public {
        IPublicDelegation.PDConstructorArgs memory args = IPublicDelegation.PDConstructorArgs({
            owner: owner,
            commissionTo: commissionTo,
            commissionRate: 0,
            gcName: "TestGC"
        });

        factory.deployCnStakingWithPD{value: INITIAL_LOCKUP}(owner, args);

        // Same (deployer, owner) → CREATE2 collision. Raw EVM revert — no selector available.
        vm.expectRevert();
        factory.deployCnStakingWithPD{value: INITIAL_LOCKUP}(owner, args);
    }

    function test_deployCnStakingWithPD_mintsDeadShares() public {
        IPublicDelegation.PDConstructorArgs memory args = IPublicDelegation.PDConstructorArgs({
            owner: owner,
            commissionTo: commissionTo,
            commissionRate: 0,
            gcName: "TestGC"
        });

        (address cnProxy, address pdProxy) = factory.deployCnStakingWithPD{value: INITIAL_LOCKUP}(owner, args);
        CnStakingV4 cn = CnStakingV4(payable(cnProxy));
        PublicDelegation pd = PublicDelegation(payable(pdProxy));

        // Dead shares minted to DEAD_ADDRESS
        assertEq(pd.balanceOf(factory.DEAD_ADDRESS()), INITIAL_LOCKUP);
        assertEq(pd.totalSupply(), INITIAL_LOCKUP);
        assertEq(cn.staking(), INITIAL_LOCKUP);
    }
}
