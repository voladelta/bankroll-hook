// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { ProgrammableFeeMath } from "../../../src/bankroll/libraries/ProgrammableFeeMath.sol";

contract ProgrammableFeeMathHarness {
    function split(uint256 selected) external pure returns (uint256 effective, uint256 platform, uint256 project) {
        return ProgrammableFeeMath.split(selected);
    }

    function feeForGross(uint256 gross, uint256 remainder) external pure returns (uint256 fee, uint256 nextRemainder) {
        return ProgrammableFeeMath.feeForGross(gross, remainder);
    }

    function grossUp(uint256 net, uint256 remainder)
        external
        pure
        returns (uint256 gross, uint256 fee, uint256 nextRemainder)
    {
        return ProgrammableFeeMath.grossUpExactOutput(net, remainder);
    }
}

contract ProgrammableFeeMathTest is Test {
    ProgrammableFeeMathHarness internal math;

    function setUp() public {
        math = new ProgrammableFeeMathHarness();
    }

    function testInclusiveFloorExamples() public view {
        (uint256 effective, uint256 platform, uint256 project) = math.split(0);
        assertEq(effective, 1000);
        assertEq(platform, 1000);
        assertEq(project, 0);

        (effective, platform, project) = math.split(30_000);
        assertEq(effective, 30_000);
        assertEq(platform, 1000);
        assertEq(project, 29_000);
    }

    function testGrossFeeCarriesNumeratorRemainder() public view {
        (uint256 fee, uint256 remainder) = math.feeForGross(999, 0);
        assertEq(fee, 0);
        assertEq(remainder, 999_000);
        (fee, remainder) = math.feeForGross(999, remainder);
        assertEq(fee, 1);
        assertEq(remainder, 998_000);
        (fee, remainder) = math.feeForGross(1 ether, 0);
        assertEq(fee, 0.001 ether);
        assertEq(remainder, 0);
    }

    function testExactOutputGrossUp() public view {
        (uint256 gross, uint256 fee, uint256 remainder) = math.grossUp(1 ether, 0);
        assertEq(gross - fee, 1 ether);
        (uint256 expectedFee, uint256 expectedRemainder) = math.feeForGross(gross, 0);
        assertEq(fee, expectedFee);
        assertEq(remainder, expectedRemainder);
    }

    function testFuzzGrossUpConserves(uint128 rawNet) public view {
        uint256 net = bound(uint256(rawNet), 1, type(uint128).max);
        uint256 carried = uint256(keccak256(abi.encode(rawNet))) % 1_000_000;
        (uint256 gross, uint256 fee, uint256 remainder) = math.grossUp(net, carried);
        assertEq(gross - fee, net);
        (uint256 expectedFee, uint256 expectedRemainder) = math.feeForGross(gross, carried);
        assertEq(fee, expectedFee);
        assertEq(remainder, expectedRemainder);
    }

    function testOneThousandSplitGrossSwapsMatchCumulativeIdentity() public view {
        uint256 totalFee;
        uint256 remainder;
        for (uint256 index; index < 1000; ++index) {
            (uint256 fee, uint256 nextRemainder) = math.feeForGross(999, remainder);
            totalFee += fee;
            remainder = nextRemainder;
        }
        assertEq(totalFee, 999);
        assertEq(remainder, 0);
    }

    function testOneThousandSplitFeeOnTopSwapsMatchCumulativeIdentity() public view {
        uint256 totalGross;
        uint256 totalFee;
        uint256 remainder;
        for (uint256 index; index < 1000; ++index) {
            (uint256 gross, uint256 fee, uint256 nextRemainder) = math.grossUp(999, remainder);
            totalGross += gross;
            totalFee += fee;
            remainder = nextRemainder;
        }
        assertEq(totalGross - totalFee, 999_000);
        assertEq(totalFee, totalGross * 1000 / 1_000_000);
        assertEq(remainder, totalGross * 1000 % 1_000_000);
    }
}
