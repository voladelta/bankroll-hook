// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IRandomnessAdapter {
    function quoteRequestFee() external view returns (uint256);

    function requestRandomness(bytes32 context, address refundRecipient) external payable returns (bytes32 requestKey);

    function fulfilled(bytes32 requestKey) external view returns (bool);

    function consumeRandomness(bytes32 requestKey) external returns (bytes32 randomWord);
}
