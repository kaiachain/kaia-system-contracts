// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {console} from "forge-std/Script.sol";
import {ABv1SwapForkBase} from "./ABv1SwapForkBase.sol";
import {CnStakingV4} from "../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {CnStakingV4Factory} from "../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";
import {IPublicDelegation} from "../src/PublicDelegation/interfaces/IPublicDelegation.sol";

interface IV3PDV1 {
    function stake() external payable;
    function redeem(address recipient, uint256 shares) external;
    function claim(uint256 requestId) external;
    function balanceOf(address) external view returns (uint256);
    function getUserRequestIds(address) external view returns (uint256[] memory);
}

interface IV3 {
    function staking() external view returns (uint256);
    function unstaking() external view returns (uint256);
}

/// @title ABv1V3PdOnSwapFork
/// @notice PD-on "yes" scenario: a GC that already holds >=5M share in V3 PD redeems
///         those shares, re-stakes into a freshly deployed V4 + PD V2, then performs
///         the ABv1 swap. Patched V4's legacy ABv1 getters bridge the call from ABv1.
///
/// Differences vs PD-off (ABv1V3SwapFork):
///   - V4 deployed via deployCnStakingWithPD (atomic V4 + PD V2)
///   - V3 funds freed via V3 PD.redeem (single tx, no multisig — PD already holds the role)
///   - Only the GC's own share (5M) leaves V3 PD; other holders' shares stay in V3 PD,
///     which becomes ABv1-unregistered after the swap
///   - V4 funds injected via V4 PD.stake (PD-on V4's `receive` is gated to PD only)
///
/// Usage:
///   forge script script/ABv1V3PdOnSwapFork.s.sol \
///     --fork-url https://public-en.node.kaia.io -vv
contract ABv1V3PdOnSwapFork is ABv1SwapForkBase {
    // PD-on target (effective 29.8M, picked from AuditPdOwnerStake output)
    address internal constant TARGET_NODE_ID_ = 0x7AA64D5f97402c1b84A5027A254151BC6129CC4e;
    address internal constant TARGET_V3_      = 0xEA217C25FB244FAf32F9B274517dB735CeCb989C;
    address internal constant TARGET_V3_PD    = 0x26295D173d146c3E7cdbdC770D955c44Abac8C04;

    uint256 internal constant GC_SELF_SHARE = 5_000_000 ether;

    constructor() ABv1SwapForkBase(TARGET_NODE_ID_, TARGET_V3_) {}

    function _logInitialState() internal view override {
        IV3 v3 = IV3(TARGET_OLD_CN);
        console.log("=== Initial mainnet state ===");
        console.log("V3 effective (KAIA):", (v3.staking() - v3.unstaking()) / 1e18);
        console.log("V3 PD:", TARGET_V3_PD);
    }

    /// @dev Atomic V4 + PD V2 deploy via factory. Only pays INITIAL_LOCKUP (1 nano-KAIA)
    ///      for the inflation-attack dead share. No GC seed capital here — the 5M
    ///      arrives later via _injectToV4 (= V4 PD.stake).
    ///      Note: factory.INITIAL_LOCKUP() must be read OUTSIDE the prank, otherwise
    ///      vm.prank gets consumed by the staticcall and the actual deploy hits the
    ///      script contract as msg.sender (which has zero balance → OutOfFunds).
    function _deployV4(CnStakingV4Factory factory, address gcOwner)
        internal
        override
        returns (CnStakingV4 v4, address reward)
    {
        uint256 lockup = factory.INITIAL_LOCKUP();

        IPublicDelegation.PDConstructorArgs memory args = IPublicDelegation.PDConstructorArgs({
            owner: gcOwner,
            commissionTo: gcOwner,
            commissionRate: 0,
            gcName: "TestGC"
        });

        vm.deal(gcOwner, 1 ether);
        vm.prank(gcOwner);
        (address cnProxy, address pdProxy) = factory.deployCnStakingWithPD{value: lockup}(gcOwner, args);
        v4 = CnStakingV4(payable(cnProxy));
        reward = pdProxy;

        console.log("V4 proxy:", cnProxy);
        console.log("V4 PD proxy:", pdProxy);
    }

    /// @dev Simulated GC-side flow:
    ///   1) Seed gcEoa with 5M V3 PD share (mints by staking — reproduces the on-chain
    ///      state of "GC already has 5M locked in V3 PD"; mainnet's actual GC-owned share
    ///      lives off-chain and is unknowable).
    ///   2) gcEoa calls V3 PD.redeem(self, shares) — internally V3 PD invokes
    ///      V3.approveStakingWithdrawal(gcEoa, assets), kicking off the 7-day lockup.
    ///   3) Warp past STAKE_LOCKUP.
    ///   4) gcEoa calls V3 PD.claim(requestId) — V3 PD invokes V3.withdrawApprovedStaking,
    ///      KAIA lands in gcEoa.
    function _extractFromV3() internal override returns (address recipient, uint256 amount) {
        recipient = makeAddr("gcEoa");
        IV3 v3 = IV3(TARGET_OLD_CN);
        IV3PDV1 v3pd = IV3PDV1(TARGET_V3_PD);

        vm.deal(recipient, GC_SELF_SHARE);
        vm.prank(recipient);
        v3pd.stake{value: GC_SELF_SHARE}();
        uint256 shares = v3pd.balanceOf(recipient);
        require(shares > 0, "seed: zero shares minted");
        console.log("Seeded gcEoa V3 PD shares:", shares);

        uint256 unstakingBefore = v3.unstaking();
        vm.prank(recipient);
        v3pd.redeem(recipient, shares);
        amount = v3.unstaking() - unstakingBefore;
        console.log("V3 unstaking delta (KAIA):", amount / 1e18);
        require(amount > 0, "redeem produced zero unstaking");

        vm.warp(block.timestamp + 7 days + 1);

        uint256[] memory ids = v3pd.getUserRequestIds(recipient);
        require(ids.length == 1, "expected exactly one withdrawal request");

        uint256 balBefore = recipient.balance;
        vm.prank(recipient);
        v3pd.claim(ids[0]);
        console.log("gcEoa balance after V3 PD claim (KAIA):", (recipient.balance - balBefore) / 1e18);
    }

    /// @dev V4 PD-on: cn's `receive` is PD-gated. Funds must go through V4 PD.stake.
    function _injectToV4(address from, CnStakingV4 /*v4*/, address reward, uint256 amount) internal override {
        require(from.balance >= amount, "insufficient balance for V4 PD stake");
        vm.prank(from);
        IV3PDV1(reward).stake{value: amount}();
        console.log("V4 PD totalAssets after stake (KAIA):", IPublicDelegation(payable(reward)).totalAssets() / 1e18);
    }

    /// @dev V3 still holds other holders' funds after the swap — sanity log, no assertion.
    function _verifyScenario() internal view override {
        console.log("V3 leftover balance (KAIA):", TARGET_OLD_CN.balance / 1e18);
    }
}
