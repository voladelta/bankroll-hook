// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

library BankrollMath {
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant PAYOUT_BPS = 19_600;
    uint256 internal constant MAX_STAKE_TO_QUOTE_BPS = 2000;
    uint256 internal constant MAX_UTILIZATION_BPS = 8000;

    error InvalidStake();

    function quoteTicket(uint256 stake) internal pure returns (uint256 grossPayout, uint256 exposure) {
        if (stake == 0) revert InvalidStake();
        grossPayout = Math.mulDiv(stake, PAYOUT_BPS, BPS_DENOMINATOR);
        if (grossPayout <= stake) revert InvalidStake();
        exposure = grossPayout - stake;
    }

    function maxStakeForGrossQuote(uint256 grossQuote) internal pure returns (uint256) {
        return Math.mulDiv(grossQuote, MAX_STAKE_TO_QUOTE_BPS, BPS_DENOMINATOR);
    }

    function utilizationLimit(uint256 bankrollAssets) internal pure returns (uint256) {
        return Math.mulDiv(bankrollAssets, MAX_UTILIZATION_BPS, BPS_DENOMINATOR);
    }

    function redemptionAssets(uint256 assets, uint256 shares, uint256 totalShares) internal pure returns (uint256) {
        if (shares == totalShares) return assets;
        return Math.mulDiv(assets, shares, totalShares);
    }
}
