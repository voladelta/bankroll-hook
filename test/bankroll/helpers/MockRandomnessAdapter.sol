// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IRandomnessAdapter } from "../../../src/bankroll/interfaces/IRandomnessAdapter.sol";

contract MockRandomnessAdapter is IRandomnessAdapter {
    uint256 public immutable fee;
    uint256 public nonce;
    mapping(bytes32 requestKey => address consumer) public consumerOf;
    mapping(bytes32 requestKey => bytes32 word) public wordOf;
    mapping(bytes32 requestKey => bool ready) public ready;
    address public reentrancyTarget;
    bool public reenterOnRequest;
    bool public reenterOnConsume;
    bool public lastReentrySucceeded;

    constructor(uint256 fee_) {
        fee = fee_;
    }

    function quoteRequestFee() external view returns (uint256) {
        return fee;
    }

    function requestRandomness(bytes32 context, address) external payable returns (bytes32 requestKey) {
        require(msg.value == fee);
        requestKey = keccak256(abi.encode(context, msg.sender, ++nonce));
        consumerOf[requestKey] = msg.sender;
        if (reenterOnRequest) _attemptExpiryReentrancy();
    }

    function fulfilled(bytes32 requestKey) external view returns (bool) {
        return ready[requestKey];
    }

    function consumeRandomness(bytes32 requestKey) external returns (bytes32 randomWord) {
        require(msg.sender == consumerOf[requestKey]);
        require(ready[requestKey]);
        ready[requestKey] = false;
        if (reenterOnConsume) _attemptExpiryReentrancy();
        return wordOf[requestKey];
    }

    function configureExpiryReentrancy(address target, bool onRequest, bool onConsume) external {
        reentrancyTarget = target;
        reenterOnRequest = onRequest;
        reenterOnConsume = onConsume;
        lastReentrySucceeded = false;
    }

    function fulfill(bytes32 requestKey, bytes32 word) external {
        require(consumerOf[requestKey] != address(0));
        wordOf[requestKey] = word;
        ready[requestKey] = true;
    }

    function _attemptExpiryReentrancy() private {
        (lastReentrySucceeded,) = reentrancyTarget.call(abi.encodeWithSignature("expireRandomness()"));
    }
}
