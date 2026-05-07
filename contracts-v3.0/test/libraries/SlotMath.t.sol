// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SlotMath} from "../../src/libraries/SlotMath.sol";

contract SlotMathTest is Test {
    struct TestCase {
        uint256 n;
        uint256 expected;
    }

    function test_maxSlotAvailable() public pure {
        // n < 4: maxSlot = 0 (f=0, no transitions out of ValActive)
        // n >= 4: maxSlot = (n/3 + 1) / 2
        TestCase[17] memory tc = [
            TestCase(0,   0),
            TestCase(1,   0),
            TestCase(2,   0),
            TestCase(3,   0),
            TestCase(4,   1), // (4/3+1)/2 = (1+1)/2 = 1
            TestCase(5,   1), // (5/3+1)/2 = (1+1)/2 = 1
            TestCase(6,   1), // (6/3+1)/2 = (2+1)/2 = 1
            TestCase(7,   1), // (7/3+1)/2 = (2+1)/2 = 1
            TestCase(8,   1), // (8/3+1)/2 = (2+1)/2 = 1
            TestCase(9,   2), // (9/3+1)/2 = (3+1)/2 = 2
            TestCase(10,  2), // (10/3+1)/2 = (3+1)/2 = 2
            TestCase(12,  2), // (12/3+1)/2 = (4+1)/2 = 2
            TestCase(13,  2), // (13/3+1)/2 = (4+1)/2 = 2
            TestCase(15,  3), // (15/3+1)/2 = (5+1)/2 = 3
            TestCase(16,  3), // (16/3+1)/2 = (5+1)/2 = 3
            TestCase(50,  8), // (50/3+1)/2 = (16+1)/2 = 8
            TestCase(100, 17) // (100/3+1)/2 = (33+1)/2 = 17
        ];
        for (uint256 i = 0; i < tc.length; i++) {
            assertEq(SlotMath.maxSlotAvailable(tc[i].n), tc[i].expected, "maxSlotAvailable mismatch");
        }
    }

    function test_minActiveCount() public pure {
        // n < 4: minActive = n (all must stay active, f=0)
        // n >= 4: minActive = ceil(2n/3) = (2n + 2) / 3
        TestCase[17] memory tc = [
            TestCase(0,   0),
            TestCase(1,   1),
            TestCase(2,   2),
            TestCase(3,   3),
            TestCase(4,   3),  // (8+2)/3 = 3
            TestCase(5,   4),  // (10+2)/3 = 4
            TestCase(6,   4),  // (12+2)/3 = 4
            TestCase(7,   5),  // (14+2)/3 = 5
            TestCase(8,   6),  // (16+2)/3 = 6
            TestCase(9,   6),  // (18+2)/3 = 6
            TestCase(10,  7),  // (20+2)/3 = 7
            TestCase(12,  8),  // (24+2)/3 = 8
            TestCase(13,  9),  // (26+2)/3 = 9
            TestCase(15,  10), // (30+2)/3 = 10
            TestCase(16,  11), // (32+2)/3 = 11
            TestCase(50,  34), // (100+2)/3 = 34
            TestCase(100, 67)  // (200+2)/3 = 67
        ];
        for (uint256 i = 0; i < tc.length; i++) {
            assertEq(SlotMath.minActiveCount(tc[i].n), tc[i].expected, "minActiveCount mismatch");
        }
    }
}
