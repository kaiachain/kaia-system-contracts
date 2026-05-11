// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IAuctionDepositVault} from "../../../src/Auction/interfaces/IAuctionDepositVault.sol";

/// @notice Minimal IAuctionDepositVault implementation for testing only.
/// @dev Only the methods exercised by AuctionEntryPoint (`depositBalances`, `takeBid`, `takeGas`)
///      have meaningful behavior. Other interface members revert so any unintended dependency
///      surfaces immediately rather than silently no-op'ing.
contract MockAuctionDepositVault is IAuctionDepositVault {
    mapping(address => uint256) public override depositBalances;

    /// @dev Toggles to simulate a failing/successful takeBid / takeGas response.
    bool public takeBidShouldSucceed = true;
    bool public takeGasShouldSucceed = true;

    /// @dev Records last call params for assertions.
    address public lastTakeBidSearcher;
    uint256 public lastTakeBidAmount;
    address public lastTakeGasSearcher;
    uint256 public lastTakeGasUsed;
    uint256 public takeBidCallCount;
    uint256 public takeGasCallCount;

    /* ========== TEST-ONLY HOOKS ========== */

    function setBalance(address searcher, uint256 amount) external {
        depositBalances[searcher] = amount;
    }

    function setTakeBidShouldSucceed(bool v) external {
        takeBidShouldSucceed = v;
    }

    function setTakeGasShouldSucceed(bool v) external {
        takeGasShouldSucceed = v;
    }

    /* ========== IAuctionDepositVault (used by EntryPoint) ========== */

    function takeBid(address searcher, uint256 amount) external override returns (bool) {
        takeBidCallCount++;
        lastTakeBidSearcher = searcher;
        lastTakeBidAmount = amount;
        if (!takeBidShouldSucceed) return false;
        depositBalances[searcher] -= amount;
        return true;
    }

    function takeGas(address searcher, uint256 gasUsed) external override returns (bool) {
        takeGasCallCount++;
        lastTakeGasSearcher = searcher;
        lastTakeGasUsed = gasUsed;
        return takeGasShouldSucceed;
    }

    /* ========== IAuctionDepositVault (not exercised — guard with revert) ========== */

    function changeMinDepositAmount(uint256) external pure override {
        revert("not implemented");
    }

    function changeMinWithdrawLocktime(uint256) external pure override {
        revert("not implemented");
    }

    function changeAuctionFeeVault(address) external pure override {
        revert("not implemented");
    }

    function deposit() external payable override {
        revert("not implemented");
    }

    function depositFor(address) external payable override {
        revert("not implemented");
    }

    function reserveWithdraw() external pure override {
        revert("not implemented");
    }

    function withdraw() external pure override {
        revert("not implemented");
    }

    function getDepositAddrsLength() external pure override returns (uint256) {
        revert("not implemented");
    }

    function getDepositAddrs(uint256, uint256) external pure override returns (address[] memory) {
        revert("not implemented");
    }

    function isMinDepositOver(address) external pure override returns (bool) {
        revert("not implemented");
    }

    function getAllAddrsOverMinDeposit(
        uint256,
        uint256
    ) external pure override returns (address[] memory, uint256[] memory, uint256[] memory) {
        revert("not implemented");
    }
}
