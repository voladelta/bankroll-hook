// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { ProgrammableFeeMath } from "../../../src/bankroll/libraries/ProgrammableFeeMath.sol";

contract ProgrammableFeeMathHarness {
    function split(uint256 selected) external pure returns (uint256 effective, uint256 platform, uint256 project) {
        return ProgrammableFeeMath.split(selected);
    }

    function feeForGross(uint256 gross) external pure returns (uint256) {
        return ProgrammableFeeMath.feeForGross(gross);
    }

    function grossUp(uint256 net) external pure returns (uint256 gross, uint256 fee) {
        return ProgrammableFeeMath.grossUpExactOutput(net);
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

    function testGrossFeeRoundsDown() public view {
        assertEq(math.feeForGross(999), 0);
        assertEq(math.feeForGross(1000), 1);
        assertEq(math.feeForGross(1 ether), 0.001 ether);
    }

    function testExactOutputGrossUp() public view {
        (uint256 gross, uint256 fee) = math.grossUp(1 ether);
        assertEq(gross - fee, 1 ether);
        assertEq(fee, math.feeForGross(gross));
    }

    function testFuzzGrossUpConserves(uint128 rawNet) public view {
        uint256 net = bound(uint256(rawNet), 1, type(uint128).max);
        (uint256 gross, uint256 fee) = math.grossUp(net);
        assertEq(gross - fee, net);
        assertEq(fee, math.feeForGross(gross));
    }
}
