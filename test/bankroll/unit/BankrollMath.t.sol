// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { BankrollMath } from "../../../src/bankroll/libraries/BankrollMath.sol";

contract BankrollMathHarness {
    function quoteTicket(uint256 stake) external pure returns (uint256 payout, uint256 exposure) {
        return BankrollMath.quoteTicket(stake);
    }

    function maxStake(uint256 quote) external pure returns (uint256) {
        return BankrollMath.maxStakeForGrossQuote(quote);
    }

    function utilization(uint256 assets) external pure returns (uint256) {
        return BankrollMath.utilizationLimit(assets);
    }

    function redeem(uint256 assets, uint256 shares, uint256 totalShares) external pure returns (uint256) {
        return BankrollMath.redemptionAssets(assets, shares, totalShares);
    }
}

contract BankrollMathTest is Test {
    BankrollMathHarness internal math;

    function setUp() public {
        math = new BankrollMathHarness();
    }

    function testWorkedTicketExample() public view {
        (uint256 payout, uint256 exposure) = math.quoteTicket(0.1 ether);
        assertEq(payout, 0.196 ether);
        assertEq(exposure, 0.096 ether);
    }

    function testPublishedRiskCaps() public view {
        assertEq(math.maxStake(1 ether), 0.2 ether);
        assertEq(math.utilization(10 ether), 8 ether);
    }

    function testLastRedeemerReceivesDust() public view {
        assertEq(math.redeem(10, 3, 6), 5);
        assertEq(math.redeem(5, 3, 3), 5);
    }

    function testFuzzPayoutAndExposureConserve(uint128 rawStake) public view {
        uint256 stake = bound(uint256(rawStake), 2, type(uint128).max / 2);
        (uint256 payout, uint256 exposure) = math.quoteTicket(stake);
        assertEq(payout, stake + exposure);
        assertGe(payout, stake);
    }
}
