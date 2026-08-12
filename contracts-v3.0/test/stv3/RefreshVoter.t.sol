// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {STv3Base} from "./Base.t.sol";
import {IStakingTrackerV3} from "../../src/StakingTrackerV3/interfaces/IStakingTrackerV3.sol";
import {IAddressBookV2} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";

contract RefreshVoterTest is STv3Base {
    function test_refreshVoter_setsMapping() public {
        stv3.refreshVoter(gc[0].nodeId);

        assertEq(stv3.gcIdToVoter(gc[0].gcId), gc[0].voterAddr);
        assertEq(stv3.voterToGCId(gc[0].voterAddr), gc[0].gcId);
    }

    function test_refreshVoter_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IStakingTrackerV3.RefreshVoter(gc[0].gcId, gc[0].voterAddr);
        stv3.refreshVoter(gc[0].nodeId);
    }

    function test_refreshVoter_updatesVoter() public {
        // Set initial voter
        stv3.refreshVoter(gc[0].nodeId);
        assertEq(stv3.gcIdToVoter(gc[0].gcId), gc[0].voterAddr);

        // Update voter in ABv2 — also triggers refreshVoter via _refreshVoter
        address newVoter = makeAddr("newVoter");
        vm.prank(gc[0].manager);
        abv2.updateVoterAddress(gc[0].nodeId, newVoter);

        assertEq(stv3.gcIdToVoter(gc[0].gcId), newVoter);
        assertEq(stv3.voterToGCId(newVoter), gc[0].gcId);

        // Old voter should be unlinked
        assertEq(stv3.voterToGCId(gc[0].voterAddr), 0);
    }

    function test_refreshVoter_clearVoter() public {
        // Set initial voter
        stv3.refreshVoter(gc[0].nodeId);

        // Set voter to address(0) in ABv2
        vm.prank(gc[0].manager);
        abv2.updateVoterAddress(gc[0].nodeId, address(0));

        assertEq(stv3.gcIdToVoter(gc[0].gcId), address(0));
        assertEq(stv3.voterToGCId(gc[0].voterAddr), 0);
    }

    function test_refreshVoter_duplicateVoterReverts() public {
        // Set voter for GC 0
        stv3.refreshVoter(gc[0].nodeId);

        // Try to set same voter for GC 1 via ABv2 — reverts in STv3
        vm.prank(gc[1].manager);
        vm.expectRevert(IStakingTrackerV3.VoterAlreadyRegistered.selector);
        abv2.updateVoterAddress(gc[1].nodeId, gc[0].voterAddr);
    }

    function test_refreshVoter_anyoneCanCall() public {
        // Any address can call refreshVoter
        vm.prank(makeAddr("randomCaller"));
        stv3.refreshVoter(gc[0].nodeId);

        assertEq(stv3.gcIdToVoter(gc[0].gcId), gc[0].voterAddr);
    }

    function test_refreshVoter_gcIdZero_silentNoOp() public {
        // Create a Registered node (gcId > 0 from _createNode) then mock gcId = 0
        // Simulate by calling refreshVoter on a node whose gcId ABv2 would return as 0
        // We can do this by mocking the getNodeInfo response
        address fakeNode = makeAddr("fakeNode");
        // Mock getNodeInfo to return a NodeInfo with gcId = 0
        vm.mockCall(
            ABV2_ADDRESS,
            abi.encodeWithSignature("getNodeInfo(address)", fakeNode),
            abi.encode(
                _makeNodeInfoWithGcId(0, makeAddr("someVoter"))
            )
        );

        // Should not revert, should be a no-op
        stv3.refreshVoter(fakeNode);

        assertEq(stv3.gcIdToVoter(0), address(0));
        assertEq(stv3.voterToGCId(makeAddr("someVoter")), 0);
    }

    function test_refreshVoter_unknownNodeReverts() public {
        // getNodeInfo reverts with NodeNotFound for unknown nodes
        vm.expectRevert(IAddressBookV2.NodeNotFound.selector);
        stv3.refreshVoter(makeAddr("unknownNode"));
    }

    function test_refreshVoter_allGCs() public {
        for (uint256 i; i < 4; i++) {
            stv3.refreshVoter(gc[i].nodeId);
        }

        for (uint256 i; i < 4; i++) {
            assertEq(stv3.gcIdToVoter(gc[i].gcId), gc[i].voterAddr);
            assertEq(stv3.voterToGCId(gc[i].voterAddr), gc[i].gcId);
        }
    }

    /* ========== revokeVoter ========== */

    function test_revokeGcId_clearsVoterMapping() public {
        stv3.refreshVoter(gc[0].nodeId);
        assertEq(stv3.voterToGCId(gc[0].voterAddr), gc[0].gcId);
        assertEq(stv3.gcIdToVoter(gc[0].gcId), gc[0].voterAddr);

        vm.prank(makeAddr("configurator"));
        abv2.revokeGcId(gc[0].nodeId);

        // Both directions of the tracker voter mapping are cleared.
        assertEq(stv3.voterToGCId(gc[0].voterAddr), 0);
        assertEq(stv3.gcIdToVoter(gc[0].gcId), address(0));
    }

    function test_revokeGcId_voterReusableAfterReassign() public {
        stv3.refreshVoter(gc[0].nodeId);

        vm.prank(makeAddr("configurator"));
        abv2.revokeGcId(gc[0].nodeId);

        // revokeGcId leaves the node's voterAddress intact, so re-assigning a gcId and
        // refreshing re-registers the same voter under the new gcId.
        vm.prank(makeAddr("configurator"));
        abv2.assignGcId(gc[0].nodeId);
        uint256 newGcId = abv2.getNodeInfo(gc[0].nodeId).gcId;
        assertGt(newGcId, 0);

        stv3.refreshVoter(gc[0].nodeId);
        assertEq(stv3.voterToGCId(gc[0].voterAddr), newGcId);
        assertEq(stv3.gcIdToVoter(newGcId), gc[0].voterAddr);
    }

    function test_assignGcId_registersVoterMapping() public {
        // Revoke first so the node has no gcId, making assignGcId the only thing that could
        // register its voter. No manual refreshVoter here - that is the point of the test.
        vm.prank(makeAddr("configurator"));
        abv2.revokeGcId(gc[0].nodeId);
        assertEq(stv3.voterToGCId(gc[0].voterAddr), 0);

        vm.prank(makeAddr("configurator"));
        abv2.assignGcId(gc[0].nodeId);

        uint256 newGcId = abv2.getNodeInfo(gc[0].nodeId).gcId;
        assertEq(stv3.voterToGCId(gc[0].voterAddr), newGcId, "assignGcId must register the voter");
        assertEq(stv3.gcIdToVoter(newGcId), gc[0].voterAddr);
    }

    function test_revokeVoter_revert_notAddressBook() public {
        stv3.refreshVoter(gc[0].nodeId);
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(IStakingTrackerV3.NotAddressBook.selector);
        stv3.revokeVoter(gc[0].gcId);
    }

    function test_revokeGcId_seversVoterFromExistingTracker() public {
        uint256 trackerId = _createTracker(100);
        stv3.refreshVoter(gc[0].nodeId);
        (, uint256 votesBefore) = stv3.getTrackedGC(trackerId, gc[0].gcId);
        assertGt(votesBefore, 0);

        vm.prank(makeAddr("configurator"));
        abv2.revokeGcId(gc[0].nodeId);

        // The pre-existing tracker still records the GC's frozen votes ...
        (, uint256 votesAfter) = stv3.getTrackedGC(trackerId, gc[0].gcId);
        assertEq(votesAfter, votesBefore);
        // ... but the voter no longer resolves to any GC, so Voting.getVotes() yields gcId 0.
        assertEq(stv3.voterToGCId(gc[0].voterAddr), 0);
    }
}
