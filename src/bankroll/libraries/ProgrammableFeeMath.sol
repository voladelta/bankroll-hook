// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";

library ProgrammableFeeMath {
    uint256 internal constant RATE_DENOMINATOR = 1_000_000;
    uint256 internal constant PLATFORM_HUNDREDTHS_OF_BIP = 1000;
    uint256 private constant EXACT_OUTPUT_SEARCH_RADIUS = 8;

    error ExactOutputRoundingUnsupported(uint256 netQuote, uint256 carriedRemainder);

    function split(uint256 selectedHundredthsOfBip)
        internal
        pure
        returns (uint256 effective, uint256 platform, uint256 project)
    {
        effective = Math.max(selectedHundredthsOfBip, PLATFORM_HUNDREDTHS_OF_BIP);
        platform = PLATFORM_HUNDREDTHS_OF_BIP;
        project = effective - platform;
    }

    function feeForGross(uint256 grossQuote, uint256 carriedRemainder)
        internal
        pure
        returns (uint256 fee, uint256 nextRemainder)
    {
        fee = FullMath.mulDiv(grossQuote, PLATFORM_HUNDREDTHS_OF_BIP, RATE_DENOMINATOR);
        uint256 fractional = mulmod(grossQuote, PLATFORM_HUNDREDTHS_OF_BIP, RATE_DENOMINATOR);
        uint256 combinedRemainder = fractional + carriedRemainder;
        fee += combinedRemainder / RATE_DENOMINATOR;
        nextRemainder = combinedRemainder % RATE_DENOMINATOR;
    }

    function grossUpExactOutput(uint256 netQuote, uint256 carriedRemainder)
        internal
        pure
        returns (uint256 grossQuote, uint256 fee, uint256 nextRemainder)
    {
        if (netQuote == 0) return (0, 0, carriedRemainder);
        uint256 estimate =
            FullMath.mulDivRoundingUp(netQuote, RATE_DENOMINATOR, RATE_DENOMINATOR - PLATFORM_HUNDREDTHS_OF_BIP);
        // Carry can shift the fee by at most one unit. Search around the no-carry ceiling so the inverse remains exact.
        uint256 candidate = estimate > EXACT_OUTPUT_SEARCH_RADIUS ? estimate - EXACT_OUTPUT_SEARCH_RADIUS : netQuote;
        if (candidate < netQuote) candidate = netQuote;
        for (uint256 index; index < EXACT_OUTPUT_SEARCH_RADIUS * 2 + 1; ++index) {
            (uint256 candidateFee, uint256 candidateRemainder) = feeForGross(candidate, carriedRemainder);
            if (candidateFee <= candidate && candidate - candidateFee == netQuote) {
                return (candidate, candidateFee, candidateRemainder);
            }
            ++candidate;
        }
        revert ExactOutputRoundingUnsupported(netQuote, carriedRemainder);
    }
}
