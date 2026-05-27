// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CnStakingV4} from "../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {PublicDelegation} from "../src/PublicDelegation/PublicDelegation.sol";
import {CnStakingV4Factory} from "../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";

/// @dev Minimal stub for AddressBookV1 (Solidity 0.4.24) functions we call.
interface IAddressBookV1 {
    function getState() external view returns (address[] memory adminList, uint256 requirement);
    function getCnInfo(address cnNodeId) external view returns (address nodeId, address stakingContract, address rewardAddr);
    function getAllAddressInfo() external view returns (
        address[] memory cnNodeIdList,
        address[] memory cnStakingContractList,
        address[] memory cnRewardAddressList,
        address pocContractAddress,
        address kirContractAddress
    );
    function submitRegisterCnStakingContract(address cnNodeId, address cnStaking, address rewardAddr) external;
    function submitUnregisterCnStakingContract(address cnNodeId) external;
}

/// @dev Minimal stub for the existing CnStakingV3 MultiSig variant on mainnet.
///      `confirmRequest`'s `uint8 functionId` matches the canonical ABI signature of the
///      original `Functions` enum parameter (Solidity encodes enum types as their backing
///      integer type — uint8 for small enums).
interface IMainnetV3 {
    function staking() external view returns (uint256);
    function unstaking() external view returns (uint256);
    function withdrawalRequestCount() external view returns (uint256);
    function requestCount() external view returns (uint256);                                // multisig req counter
    function requirement() external view returns (uint256);
    function ADMIN_ROLE() external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);

    function submitApproveStakingWithdrawal(address to, uint256 value) external;
    function confirmRequest(uint256 id, uint8 functionId, bytes32 a1, bytes32 a2, bytes32 a3) external;
    function withdrawApprovedStaking(uint256 id) external;
}

/// @title Abv1SwapFork
/// @notice End-to-end V3 → V4 swap rehearsal against Kaia mainnet fork.
///         Picks one existing V3 PD-off GC, deploys the patched V4 under the same nodeId,
///         unstakes 5M from V3 via its internal multisig, transfers the funds to V4, then
///         unregisters V3 and registers V4 in AddressBookV1.
///
/// Usage:
///   forge script script/Abv1SwapFork.s.sol \
///     --fork-url https://public-en.node.kaia.io -vv
contract Abv1SwapFork is Script {
    /* ========== MAINNET ADDRESSES ========== */

    address internal constant ADDRESS_BOOK = 0x0000000000000000000000000000000000000400;

    // GC #5 in cnNodeIdList — V3 PD off, ~14.7M staking
    address internal constant TARGET_NODE_ID = 0x6Cd6261c8bE831ee79dA184BeAac962F6c8ee634;
    address internal constant TARGET_V3      = 0x7dc397C45Ea4468c180fC010E69091B6D38846dF;
    address internal constant TARGET_REWARD  = 0xF786C3720A10cb48c8F12d0AC2086dCF227c7CDe;

    /* ========== PROTOCOL CONSTANTS ========== */

    /// @dev `Functions.ApproveStakingWithdrawal` index in the V3MultiSig enum
    ///      (see ICnStakingV3MultiSig.sol:46-59 — 0:Unknown, 1:AddAdmin, ..., 6:ApproveStakingWithdrawal).
    uint8 internal constant FN_APPROVE_STAKING_WITHDRAWAL = 6;

    /// @dev Chain-level minimum stake for council eligibility (params/config.go:83 MinimumStake = 5M KAIA).
    uint256 internal constant MIN_STAKE = 5_000_000 ether;

    IAddressBookV1 internal abv1 = IAddressBookV1(ADDRESS_BOOK);
    IMainnetV3 internal v3 = IMainnetV3(TARGET_V3);

    function run() external {
        _logInitialState();

        (address[] memory abv1Admins, uint256 abv1Req) = abv1.getState();
        (address[] memory v3Admins, uint256 v3Quorum) = _fetchV3Multisig();

        // Unstake the entire withdrawable delegated balance from V3 in one shot — leaving
        // funds in V3 after unregister would orphan them since the chain no longer reads V3.
        //
        // The max amount V3.approveStakingWithdrawal will accept is `staking - unstaking`
        // (CnStakingV3.sol:416 `require(unstaking + _value <= staking)`); subtracting
        // `unstaking` guards against any pending withdrawal that may exist on mainnet at
        // fork time. Initial lockup (~1 KAIA) is a separate pool and is left behind here —
        // it needs a separate submitWithdrawLockupStaking multisig flow.
        uint256 unstakeAmount = v3.staking() - v3.unstaking();

        address gcOwner = makeAddr("gcOwner");
        address gcEoa = makeAddr("gcEoa");
        CnStakingV4 v4 = _deployV4Infra(gcOwner);

        _unstakeFromV3(v3Admins, v3Quorum, gcEoa, unstakeAmount);
        _transferToV4(gcEoa, v4, unstakeAmount);
        _swapAbv1(abv1Admins, abv1Req, address(v4));
        _verifyFinalState(address(v4), unstakeAmount);

        console.log("=== SUCCESS ===");
    }

    /* ========== STEP HELPERS ========== */

    function _logInitialState() internal view {
        console.log("=== Initial mainnet state ===");
        console.log("V3 staking (KAIA):", v3.staking() / 1e18);
        console.log("V3 balance (KAIA):", TARGET_V3.balance / 1e18);
    }

    /// @dev Reads V3's ADMIN_ROLE list and quorum directly from the contract.
    function _fetchV3Multisig() internal view returns (address[] memory admins, uint256 quorum) {
        quorum = v3.requirement();
        bytes32 adminRole = v3.ADMIN_ROLE();
        admins = new address[](quorum);
        for (uint256 i = 0; i < quorum; ++i) {
            admins[i] = v3.getRoleMember(adminRole, i);
        }
        console.log("V3 quorum:", quorum);
    }

    /// @dev Deploys the patched V4 implementation + beacons + factory, deploys a
    ///      proxy under `gcOwner`, and seeds the legacy ABv1 identity fields.
    ///      No StakingTracker mocking — mainnet's V1 tracker (0xF45c...7c9c) returns
    ///      early in updateTracker when called with an unregistered staking contract
    ///      (see contracts-klaytn-v1.10/contracts/StakingTracker.sol:175-178).
    function _deployV4Infra(address gcOwner) internal returns (CnStakingV4 v4) {
        address deployer = makeAddr("deployer");

        vm.startPrank(deployer);
        CnStakingV4 cnImpl = new CnStakingV4();
        PublicDelegation pdImpl = new PublicDelegation();
        UpgradeableBeacon cnBeacon = new UpgradeableBeacon(address(cnImpl), deployer);
        UpgradeableBeacon pdBeacon = new UpgradeableBeacon(address(pdImpl), deployer);
        CnStakingV4Factory factory = new CnStakingV4Factory(address(cnBeacon), address(pdBeacon));
        vm.stopPrank();

        vm.prank(gcOwner);
        address proxy = factory.deployCnStaking(gcOwner);
        v4 = CnStakingV4(payable(proxy));

        vm.prank(gcOwner);
        v4.setLegacyAbv1Info(TARGET_NODE_ID, TARGET_REWARD);

        console.log("=== V4 deployed ===");
        console.log("V4 proxy:", proxy);
        console.log("V4.nodeId():", v4.nodeId());
        console.log("V4.rewardAddress():", v4.rewardAddress());
        console.log("V4.isInitialized():", v4.isInitialized());
    }

    /// @dev Drives the V3 multisig: 1 admin submits the approve request (also auto-confirms),
    ///      the remaining (quorum-1) admins call `confirmRequest` to push the request over
    ///      quorum — the last confirmer's call triggers `_executeRequest` inline which then
    ///      invokes V3.approveStakingWithdrawal via `address(this).call`. After STAKE_LOCKUP
    ///      a single admin claims the withdrawal directly (UNSTAKING_CLAIMER_ROLE is granted
    ///      per-admin in V3MultiSig PD-off, not via multisig — CnStakingV3MultiSig.sol:149).
    function _unstakeFromV3(
        address[] memory admins,
        uint256 quorum,
        address gcEoa,
        uint256 amount
    ) internal {
        uint256 withdrawalId = v3.withdrawalRequestCount();
        uint256 multisigId = v3.requestCount();
        console.log("=== Unstaking from V3 ===");
        console.log("Amount (KAIA):", amount / 1e18);
        console.log("Next withdrawal id:", withdrawalId);
        console.log("Next multisig req id:", multisigId);

        // 1) First admin submits — creates multisig request #multisigId and auto-confirms.
        vm.prank(admins[0]);
        v3.submitApproveStakingWithdrawal(gcEoa, amount);

        // 2) Remaining admins confirm. The (quorum-1)-th confirmation triggers inline execute,
        //    which calls V3.approveStakingWithdrawal(gcEoa, amount) under address(this)
        //    — the holder of UNSTAKING_APPROVER_ROLE in V3MultiSig (PD off).
        bytes32 toArg = bytes32(uint256(uint160(gcEoa)));
        bytes32 valueArg = bytes32(amount);
        for (uint256 i = 1; i < quorum; ++i) {
            vm.prank(admins[i]);
            v3.confirmRequest(multisigId, FN_APPROVE_STAKING_WITHDRAWAL, toArg, valueArg, 0);
        }

        // 3) Warp past the 1-week stake lockup (well within the [+7d, +14d] claim window).
        vm.warp(block.timestamp + 7 days + 1);
        console.log("Warped block.timestamp:", block.timestamp);

        // 4) Any single admin can claim — UNSTAKING_CLAIMER_ROLE is per-admin.
        vm.prank(admins[0]);
        v3.withdrawApprovedStaking(withdrawalId);

        console.log("gcEoa balance after withdraw (KAIA):", gcEoa.balance / 1e18);
        console.log("V3 balance after withdraw (KAIA):", TARGET_V3.balance / 1e18);
    }

    /// @dev gcEoa moves the just-claimed amount into the patched V4. V4 is deployed PD-off so
    ///      its `receive()` is open (CnStakingV4.sol:84-89 `_onlyStaker` returns silently
    ///      when publicDelegation is unset).
    function _transferToV4(address gcEoa, CnStakingV4 v4, uint256 amount) internal {
        vm.prank(gcEoa);
        (bool ok,) = address(v4).call{value: amount}("");
        require(ok, "V4 receive failed");

        console.log("V4 balance after transfer (KAIA):", address(v4).balance / 1e18);
        console.log("V4 staking() after transfer (KAIA):", v4.staking() / 1e18);
    }

    /// @dev ABv1 swap: unregister V3 then register V4 under the same nodeId. With requirement=1
    ///      a single admin's submit hits quorum inline. The register validation reads V4's three
    ///      legacy getters (nodeId / rewardAddress / isInitialized) — this is what the patch is
    ///      meant to satisfy.
    function _swapAbv1(address[] memory admins, uint256 quorum, address v4Proxy) internal {
        for (uint256 i = 0; i < quorum; ++i) {
            vm.prank(admins[i]);
            abv1.submitUnregisterCnStakingContract(TARGET_NODE_ID);
        }
        console.log("ABv1 V3 unregister done");

        for (uint256 i = 0; i < quorum; ++i) {
            vm.prank(admins[i]);
            abv1.submitRegisterCnStakingContract(TARGET_NODE_ID, v4Proxy, TARGET_REWARD);
        }
        console.log("ABv1 V4 register done");
    }

    /// @dev Comprehensive post-swap state verification.
    ///   (1) ABv1 mapping: getCnInfo returns the V4 triple under TARGET_NODE_ID
    ///   (2) ABv1 list consistency: V3 absent from cnStakingContractList, V4 present
    ///   (3) V4 fund state: raw balance and internal `staking()` both equal expectedStake
    ///   (4) Chain-level eligibility: V4.balance >= MIN_STAKE (what MultiCall reads in ABv1 era —
    ///       see contracts-v3.0/src/Multicall/MultiCallContract.sol:180-184 `cnStaking.balance`)
    ///   (5) V3 emptied (only the untouched initial-lockup pool ≤ initialLockupStaking remains)
    function _verifyFinalState(address v4Proxy, uint256 expectedStake) internal view {
        // (1) getCnInfo
        (address gotNodeId, address gotStaking, address gotReward) = abv1.getCnInfo(TARGET_NODE_ID);
        console.log("=== Final ABv1 state for nodeId ===");
        console.log("nodeId:", gotNodeId);
        console.log("stakingContract:", gotStaking);
        console.log("rewardAddress:", gotReward);
        require(gotNodeId == TARGET_NODE_ID, "nodeId mismatch");
        require(gotStaking == v4Proxy, "V4 not registered as staking contract");
        require(gotReward == TARGET_REWARD, "reward address mismatch");

        // (2) List consistency — V3 gone, V4 present
        (, address[] memory stakingList, , , ) = abv1.getAllAddressInfo();
        bool v3Found = false;
        bool v4Found = false;
        for (uint256 i = 0; i < stakingList.length; ++i) {
            if (stakingList[i] == TARGET_V3) v3Found = true;
            if (stakingList[i] == v4Proxy)   v4Found = true;
        }
        require(!v3Found, "V3 still present in cnStakingContractList");
        require(v4Found,  "V4 missing from cnStakingContractList");

        // (3) V4 fund state
        uint256 v4Balance = v4Proxy.balance;
        uint256 v4Staking = CnStakingV4(payable(v4Proxy)).staking();
        console.log("V4 balance / staking() (KAIA):", v4Balance / 1e18, v4Staking / 1e18);
        require(v4Balance == expectedStake, "V4 balance != expected");
        require(v4Staking == expectedStake, "V4 staking() != expected");

        // (4) Chain-level minimum stake (ABv1 era reader = balance)
        require(v4Balance >= MIN_STAKE, "V4 below MinStake");

        // (5) V3 emptied — only the untouched initial-lockup pool remains.
        //     V3.approveStakingWithdrawal cannot touch remainingLockupStaking, so the leftover
        //     is bounded by it. We accept any value ≤ that bound.
        // (Querying remainingLockupStaking() costs another stub method; we cap loosely at 10 KAIA
        //  since the inspected target's initial lockup is 1 KAIA. Adjust if reused for other GCs.)
        require(TARGET_V3.balance <= 10 ether, "V3 leftover too large");
    }
}
