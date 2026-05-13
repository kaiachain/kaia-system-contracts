// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {AuctionFeeVault} from "../../src/Auction/AuctionFeeVault.sol";
import {AuctionError} from "../../src/Auction/AuctionError.sol";
import {IAuctionFeeVault} from "../../src/Auction/interfaces/IAuctionFeeVault.sol";
import {MockAddressBookV2} from "./mocks/MockAddressBookV2.sol";

/// @title AuctionFeeVault diff tests
/// @notice Targets ONLY the v3.0 change: manager-of-nodeId auth in registerRewardAddress, sourced
///         from AddressBookV2.getNodeInfo(nodeId).manager. Bid/withdrawal flows are unchanged
///         from v2.1 and remain covered there.
contract AuctionFeeVaultTest is Test {
    address internal constant ADDRESS_BOOK = 0x0000000000000000000000000000000000000400;

    AuctionFeeVault internal feeVault;

    address internal owner = makeAddr("owner");
    address internal manager = makeAddr("manager");
    address internal newManager = makeAddr("newManager");
    address internal stranger = makeAddr("stranger");
    address internal nodeId = makeAddr("nodeId");
    address internal rewardAddr = makeAddr("rewardAddr");

    function setUp() public {
        feeVault = new AuctionFeeVault(owner, 5000, 4000);

        // Install a fresh MockAddressBookV2 at the precompile address via etch + initialize storage.
        MockAddressBookV2 mock = new MockAddressBookV2();
        vm.etch(ADDRESS_BOOK, address(mock).code);
        // Etched code shares storage layout with `mock` — write directly via the bound type.
        MockAddressBookV2(ADDRESS_BOOK).setManager(nodeId, manager);
    }

    /* ========== TESTS: manager auth on registerRewardAddress (the diff) ========== */

    function test_manager_can_register() public {
        vm.expectEmit(true, true, true, true);
        emit IAuctionFeeVault.RewardAddressRegistered(nodeId, rewardAddr, manager);

        vm.prank(manager);
        feeVault.registerRewardAddress(nodeId, rewardAddr);

        assertEq(feeVault.getRewardAddr(nodeId), rewardAddr);
    }

    function test_manager_can_update_reward_address() public {
        vm.prank(manager);
        feeVault.registerRewardAddress(nodeId, rewardAddr);

        address newReward = makeAddr("newReward");
        vm.prank(manager);
        feeVault.registerRewardAddress(nodeId, newReward);

        assertEq(feeVault.getRewardAddr(nodeId), newReward, "reward not updated");
    }

    function test_non_manager_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(AuctionError.OnlyNodeManager.selector);
        feeVault.registerRewardAddress(nodeId, rewardAddr);

        assertEq(feeVault.getRewardAddr(nodeId), address(0));
    }

    function test_unknown_nodeId_reverts() public {
        address unknownNode = makeAddr("unknownNode");
        // No manager set for this nodeId → AddressBookV2 returns NodeInfo with manager == 0.
        vm.prank(manager);
        vm.expectRevert(AuctionError.OnlyNodeManager.selector);
        feeVault.registerRewardAddress(unknownNode, rewardAddr);
    }

    function test_manager_rotation_in_addressbook_shifts_auth() public {
        // Old manager registers first.
        vm.prank(manager);
        feeVault.registerRewardAddress(nodeId, rewardAddr);

        // AddressBookV2 rotates the manager (e.g., via updateManager in production).
        MockAddressBookV2(ADDRESS_BOOK).setManager(nodeId, newManager);

        // Old manager is now unauthorized.
        vm.prank(manager);
        vm.expectRevert(AuctionError.OnlyNodeManager.selector);
        feeVault.registerRewardAddress(nodeId, makeAddr("rewardAttempt2"));

        // New manager succeeds.
        address newReward = makeAddr("newReward");
        vm.prank(newManager);
        feeVault.registerRewardAddress(nodeId, newReward);
        assertEq(feeVault.getRewardAddr(nodeId), newReward);
    }

    /* ========== TESTS: owner batch path unaffected ========== */

    function test_owner_batch_does_not_require_manager() public {
        address[] memory ids = new address[](2);
        address[] memory rewards = new address[](2);
        ids[0] = nodeId;
        ids[1] = makeAddr("anotherNode"); // no manager set in AddressBook — still fine for owner
        rewards[0] = rewardAddr;
        rewards[1] = makeAddr("anotherReward");

        vm.prank(owner);
        feeVault.registerRewardAddresses(ids, rewards);

        assertEq(feeVault.getRewardAddr(ids[0]), rewards[0]);
        assertEq(feeVault.getRewardAddr(ids[1]), rewards[1]);
    }

    function test_non_owner_batch_reverts() public {
        address[] memory ids = new address[](1);
        address[] memory rewards = new address[](1);
        ids[0] = nodeId;
        rewards[0] = rewardAddr;

        vm.prank(manager); // even the manager can't bulk-register
        vm.expectRevert(); // OZ Ownable's OwnableUnauthorizedAccount(address)
        feeVault.registerRewardAddresses(ids, rewards);
    }
}
