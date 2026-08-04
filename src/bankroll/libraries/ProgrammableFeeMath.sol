// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

library ProgrammableFeeMath {
    uint256 internal constant RATE_DENOMINATOR = 1_000_000;
    uint256 internal constant PLATFORM_HUNDREDTHS_OF_BIP = 1000;

    function split(uint256 selectedHundredthsOfBip)
        internal
        pure
        returns (uint256 effective, uint256 platform, uint256 project)
    {
        effective = Math.max(selectedHundredthsOfBip, PLATFORM_HUNDREDTHS_OF_BIP);
        platform = PLATFORM_HUNDREDTHS_OF_BIP;
        project = effective - platform;
    }

    function feeForGross(uint256 grossQuote) internal pure returns (uint256) {
        return Math.mulDiv(grossQuote, PLATFORM_HUNDREDTHS_OF_BIP, RATE_DENOMINATOR);
    }

    function grossUpExactOutput(uint256 netQuote) internal pure returns (uint256 grossQuote, uint256 fee) {
        if (netQuote == 0) return (0, 0);
        grossQuote = Math.mulDiv(
            netQuote, RATE_DENOMINATOR, RATE_DENOMINATOR - PLATFORM_HUNDREDTHS_OF_BIP, Math.Rounding.Ceil
        );
        while (grossQuote > netQuote && grossQuote - 1 - feeForGross(grossQuote - 1) >= netQuote) {
            --grossQuote;
        }
        fee = grossQuote - netQuote;
    }
}
