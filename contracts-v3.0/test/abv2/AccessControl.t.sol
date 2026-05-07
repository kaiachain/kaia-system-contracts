// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Base} from "../base/Base.t.sol";
import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {
    IAddressBookV2,
    ADDR_CFG_SUSPENDER,
    ADDR_CFG_CONFIGURATOR
} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";
import {State, NodeInfo, BlsPublicKeyInfo} from "../../src/types/Node.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title AccessControlTest
/// @notice Access control tests including UUPS upgrade authorization.
contract AccessControlTest is Base {
    /* ========== UUPS upgrade: _authorizeUpgrade ========== */

    function test_upgrade_succeeds_asOwner() public {
        AddressBookV2 newImpl = new AddressBookV2(EPOCH_BLOCK_INTERVAL);

        vm.prank(owner);
        abv2.upgradeToAndCall(address(newImpl), "");

        // State preserved after upgrade
        _assertNodeState(genesis[0].nodeId, State.Registered);
        assertEq(abv2.getNodeInfo(genesis[0].nodeId).manager, genesis[0].manager);
    }

    function test_upgrade_reverts_asNonOwner() public {
        AddressBookV2 newImpl = new AddressBookV2(EPOCH_BLOCK_INTERVAL);
        address nonOwner = makeAddr("nonOwner");

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        abv2.upgradeToAndCall(address(newImpl), "");
    }

    /* ========== updateSuspender ========== */

    function test_updateSuspender_success() public {
        address newSuspender = makeAddr("newSuspender");

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.AddressConfigUpdated(ADDR_CFG_SUSPENDER, owner, newSuspender);

        vm.prank(owner);
        abv2.updateSuspender(newSuspender);

        assertEq(abv2.getSuspender(), newSuspender);
    }

    function test_updateSuspender_revert_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        abv2.updateSuspender(makeAddr("newSuspender"));
    }

    /* ========== updateConfigurator ========== */

    function test_updateConfigurator_success() public {
        address newConfigurator = makeAddr("newConfigurator");

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.AddressConfigUpdated(ADDR_CFG_CONFIGURATOR, owner, newConfigurator);

        vm.prank(owner);
        abv2.updateConfigurator(newConfigurator);

        assertEq(abv2.getConfigurator(), newConfigurator);
    }

    function test_updateConfigurator_revert_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        abv2.updateConfigurator(makeAddr("newConfigurator"));
    }

    /* ========== Re-initialization guard ========== */

    function test_initialize_revert_alreadyInitialized() public {
        vm.expectRevert();
        abv2.initialize();
    }
}
