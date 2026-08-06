// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IVRFV2PlusWrapper } from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFV2PlusWrapper.sol";

interface IRawVrfConsumer {
    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external;
}

contract MockVrfWrapper is IVRFV2PlusWrapper {
    uint256 public fee;
    uint256 public override lastRequestId;
    bool public repeatRequestId;
    mapping(uint256 requestId => address consumer) public consumerOf;

    constructor(uint256 fee_) {
        fee = fee_;
    }

    function setFee(uint256 fee_) external {
        fee = fee_;
    }

    function setRepeatRequestId(bool repeat) external {
        repeatRequestId = repeat;
    }

    function calculateRequestPrice(uint32, uint32) external view returns (uint256) {
        return fee;
    }

    function calculateRequestPriceNative(uint32, uint32) external view returns (uint256) {
        return fee;
    }

    function estimateRequestPrice(uint32, uint32, uint256) external view returns (uint256) {
        return fee;
    }

    function estimateRequestPriceNative(uint32, uint32, uint256) external view returns (uint256) {
        return fee;
    }

    function requestRandomWordsInNative(uint32, uint16, uint32, bytes calldata)
        external
        payable
        returns (uint256 requestId)
    {
        require(msg.value == fee);
        if (!repeatRequestId || lastRequestId == 0) ++lastRequestId;
        requestId = lastRequestId;
        consumerOf[requestId] = msg.sender;
    }

    function fulfill(address consumer, uint256 requestId, uint256[] memory randomWords) external {
        IRawVrfConsumer(consumer).rawFulfillRandomWords(requestId, randomWords);
    }

    function link() external pure returns (address) {
        return address(0);
    }

    function linkNativeFeed() external pure returns (address) {
        return address(0);
    }
}
