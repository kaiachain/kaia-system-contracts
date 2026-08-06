// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {AuctionCallExecutor} from "src/Auction/AuctionCallExecutor.sol";

contract GasProbe {
    uint256 public seen;

    fallback() external {
        seen = gasleft();
    }
}

contract AuctionCallExecutorTest is Test {
    AuctionCallExecutor executor;
    GasProbe probe;

    function setUp() public {
        executor = new AuctionCallExecutor(address(this));
        probe = new GasProbe();
    }

    /// Runs execute() at the smallest outer gas its check accepts, and reports what the target got.
    function _deliveredAtCheckBoundary(uint256 payload, uint256 gasLimit) internal returns (uint256) {
        bytes memory encoded = abi.encodeCall(
            AuctionCallExecutor.execute,
            (address(probe), gasLimit, new bytes(payload))
        );

        // The check needs gasleft*63/64 >= gasLimit + CALL_ENTRY_GAS, so success is monotonic in
        // the outer gas. Above the boundary the call is never gas-starved and the bug is invisible.
        uint256 lo = ((gasLimit + 3_000) * 64) / 63;
        uint256 hi = lo + 1_000_000;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            (bool ok, ) = address(executor).call{gas: mid}(encoded);
            if (ok) {
                hi = mid;
            } else {
                lo = mid + 1;
            }
        }
        (bool passed, ) = address(executor).call{gas: lo}(encoded);
        require(passed, "check never passed");
        return probe.seen();
    }

    /// The gas the target receives must not depend on how big the payload is. Comparing two sizes
    /// cancels out the gas the probe spends before it can read gasleft().
    function test_deliveredGasIsIndependentOfPayloadSize() public {
        uint256 gasLimit = 1_000_000;
        uint256 small = _deliveredAtCheckBoundary(1_024, gasLimit);
        uint256 large = _deliveredAtCheckBoundary(64 * 1024, gasLimit); // BidTxMaxDataSize
        assertEq(large, small, "a bigger payload starved the target");
    }
}
