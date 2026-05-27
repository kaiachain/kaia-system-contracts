// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CnStakingBase} from "./CnStakingBase.t.sol";
import {CnStakingV4} from "../../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {ICnStaking} from "../../src/CnStaking/CnStakingV4/interfaces/ICnStaking.sol";
import {PublicDelegation} from "../../src/PublicDelegation/PublicDelegation.sol";
import {IPublicDelegation} from "../../src/PublicDelegation/interfaces/IPublicDelegation.sol";

/// @title LegacyAbv1Test
/// @notice Coverage for the ABv1 legacy compatibility layer on CnStakingV4:
///         setLegacyAbv1Info, clearLegacyAbv1Info, and the three legacy getters
///         (nodeId, rewardAddress, isInitialized).
contract LegacyAbv1Test is CnStakingBase {
    CnStakingV4 internal cn;

    address internal nodeIdAddr;
    address internal rewardAddr;

    event LegacyAbv1InfoSet(address indexed nodeId, address indexed rewardAddress);
    event LegacyAbv1InfoCleared();

    function setUp() public override {
        super.setUp();
        cn = _deployCnStaking(owner);
        nodeIdAddr = makeAddr("gcNodeId");
        rewardAddr = makeAddr("gcReward");
    }

    /* ========== FRESH STATE ========== */

    function test_FreshState_GettersReturnZero() public view {
        assertEq(cn.nodeId(), address(0), "fresh nodeId must be zero");
        assertEq(cn.rewardAddress(), address(0), "fresh rewardAddress must be zero");
        assertFalse(cn.isInitialized(), "fresh isInitialized must be false");
    }

    /* ========== setLegacyAbv1Info ========== */

    function test_Set_HappyPath_StoresValuesAndEmits() public {
        vm.expectEmit(true, true, false, false, address(cn));
        emit LegacyAbv1InfoSet(nodeIdAddr, rewardAddr);

        vm.prank(owner);
        cn.setLegacyAbv1Info(nodeIdAddr, rewardAddr);

        assertEq(cn.nodeId(), nodeIdAddr);
        assertEq(cn.rewardAddress(), rewardAddr);
        assertTrue(cn.isInitialized());
    }

    function test_Set_RevertsWhenNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        cn.setLegacyAbv1Info(nodeIdAddr, rewardAddr);
    }

    function test_Set_RevertsOnZeroNodeId() public {
        vm.prank(owner);
        vm.expectRevert(ICnStaking.ZeroAddress.selector);
        cn.setLegacyAbv1Info(address(0), rewardAddr);
    }

    function test_Set_RevertsOnZeroRewardAddress() public {
        vm.prank(owner);
        vm.expectRevert(ICnStaking.ZeroAddress.selector);
        cn.setLegacyAbv1Info(nodeIdAddr, address(0));
    }

    function test_Set_RevertsOnSecondCall() public {
        vm.prank(owner);
        cn.setLegacyAbv1Info(nodeIdAddr, rewardAddr);

        address newNodeId = makeAddr("otherNodeId");
        address newReward = makeAddr("otherReward");

        vm.prank(owner);
        vm.expectRevert(ICnStaking.LegacyAlreadySet.selector);
        cn.setLegacyAbv1Info(newNodeId, newReward);

        // Original values preserved
        assertEq(cn.nodeId(), nodeIdAddr);
        assertEq(cn.rewardAddress(), rewardAddr);
    }

    /* ========== clearLegacyAbv1Info ========== */

    function test_Clear_RevertsWhenNotOwner() public {
        vm.prank(owner);
        cn.setLegacyAbv1Info(nodeIdAddr, rewardAddr);

        vm.prank(user1);
        vm.expectRevert();
        cn.clearLegacyAbv1Info();
    }

    function test_Clear_ZeroesFieldsAndEmits() public {
        vm.prank(owner);
        cn.setLegacyAbv1Info(nodeIdAddr, rewardAddr);

        vm.expectEmit(false, false, false, false, address(cn));
        emit LegacyAbv1InfoCleared();

        vm.prank(owner);
        cn.clearLegacyAbv1Info();
    }

    function test_Clear_AllowedBeforeSet() public {
        // No prior set — clear should still work and toggle the cleared flag.
        vm.prank(owner);
        cn.clearLegacyAbv1Info();

        vm.expectRevert(ICnStaking.LegacyCleared.selector);
        cn.nodeId();
    }

    /* ========== POST-CLEAR REVERT SEMANTICS ========== */

    function test_PostClear_NodeIdReverts() public {
        _setThenClear();
        vm.expectRevert(ICnStaking.LegacyCleared.selector);
        cn.nodeId();
    }

    function test_PostClear_RewardAddressReverts() public {
        _setThenClear();
        vm.expectRevert(ICnStaking.LegacyCleared.selector);
        cn.rewardAddress();
    }

    function test_PostClear_IsInitializedReverts() public {
        _setThenClear();
        vm.expectRevert(ICnStaking.LegacyCleared.selector);
        cn.isInitialized();
    }

    function test_PostClear_SetReverts() public {
        _setThenClear();
        vm.prank(owner);
        vm.expectRevert(ICnStaking.LegacyCleared.selector);
        cn.setLegacyAbv1Info(nodeIdAddr, rewardAddr);
    }

    function test_PostClear_DoubleClearReverts() public {
        _setThenClear();
        vm.prank(owner);
        vm.expectRevert(ICnStaking.LegacyCleared.selector);
        cn.clearLegacyAbv1Info();
    }

    /* ========== STORAGE ISOLATION ========== */

    /// @notice Sanity check that the legacy storage namespace does not collide with the main
    ///         StakingStorage namespace — setting legacy info must not change staking() / unstaking().
    function test_StorageIsolation_DoesNotAffectMainState() public {
        uint256 stakingBefore = cn.staking();
        uint256 unstakingBefore = cn.unstaking();
        uint256 wrCountBefore = cn.withdrawalRequestCount();
        address pdBefore = cn.publicDelegation();

        vm.prank(owner);
        cn.setLegacyAbv1Info(nodeIdAddr, rewardAddr);

        assertEq(cn.staking(), stakingBefore);
        assertEq(cn.unstaking(), unstakingBefore);
        assertEq(cn.withdrawalRequestCount(), wrCountBefore);
        assertEq(cn.publicDelegation(), pdBefore);

        vm.prank(owner);
        cn.clearLegacyAbv1Info();

        assertEq(cn.staking(), stakingBefore);
        assertEq(cn.unstaking(), unstakingBefore);
        assertEq(cn.withdrawalRequestCount(), wrCountBefore);
        assertEq(cn.publicDelegation(), pdBefore);
    }

    /* ========== PD ON SANITY ========== */

    /// @notice Legacy interface must behave identically on PD-enabled deployments — the
    ///         LegacyAbv1 storage namespace is orthogonal to PD-related state.
    /// @dev Uses a distinct owner from setUp's PD-off deploy to avoid CREATE2 address collision
    ///      in the factory's deterministic proxy deployment.
    function test_PDOn_LegacyInterfaceWorksIndependently() public {
        address pdOwner = makeAddr("pdOwner");
        (CnStakingV4 pdCn, PublicDelegation pd) = _deployCnStakingWithPD(
            pdOwner,
            IPublicDelegation.PDConstructorArgs({
                owner: pdOwner,
                commissionTo: commissionTo,
                commissionRate: 1000,
                gcName: "PDOnTestGC"
            })
        );

        // PD wiring intact before legacy ops
        assertEq(pdCn.publicDelegation(), address(pd));

        vm.prank(pdOwner);
        pdCn.setLegacyAbv1Info(nodeIdAddr, rewardAddr);

        // Legacy getters work
        assertEq(pdCn.nodeId(), nodeIdAddr);
        assertEq(pdCn.rewardAddress(), rewardAddr);
        assertTrue(pdCn.isInitialized());

        // PD wiring untouched
        assertEq(pdCn.publicDelegation(), address(pd));

        // Clear semantics also unchanged under PD-on
        vm.prank(pdOwner);
        pdCn.clearLegacyAbv1Info();

        vm.expectRevert(ICnStaking.LegacyCleared.selector);
        pdCn.nodeId();

        // PD wiring still untouched after clear
        assertEq(pdCn.publicDelegation(), address(pd));
    }

    /* ========== HELPERS ========== */

    function _setThenClear() private {
        vm.startPrank(owner);
        cn.setLegacyAbv1Info(nodeIdAddr, rewardAddr);
        cn.clearLegacyAbv1Info();
        vm.stopPrank();
    }
}
