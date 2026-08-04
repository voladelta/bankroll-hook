// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { VRFV2PlusWrapperConsumerBase } from "@chainlink/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import { IVRFV2PlusWrapper } from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFV2PlusWrapper.sol";
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import { IRandomnessAdapter } from "../interfaces/IRandomnessAdapter.sol";

/// @notice Chainlink VRF v2.5 direct-funding adapter that stores one word for later consumption.
/// @dev Prototype only. The immutable wrapper must be checked against the target chain before deployment.
contract ChainlinkVrfV25Adapter is IRandomnessAdapter, VRFV2PlusWrapperConsumerBase {
    struct Request {
        address consumer;
        bytes32 context;
        bytes32 word;
        bool fulfilled;
        bool consumed;
    }

    uint32 public immutable callbackGasLimit;
    uint16 public immutable requestConfirmations;

    mapping(bytes32 requestKey => Request request) private _requests;
    mapping(uint256 requestId => bytes32 requestKey) public requestKeyById;

    error ExactPaymentRequired(uint256 expected, uint256 actual);
    error InvalidConfiguration();
    error InvalidFulfilment(uint256 requestId);
    error RandomnessNotReady(bytes32 requestKey);
    error UnauthorizedConsumer(address caller, address expected);

    event RandomnessRequested(
        bytes32 indexed requestKey, uint256 indexed requestId, address indexed consumer, bytes32 context, uint256 fee
    );
    event RandomnessAvailable(bytes32 indexed requestKey, uint256 indexed requestId);
    event RandomnessConsumed(bytes32 indexed requestKey, address indexed consumer);

    constructor(address wrapper, uint32 callbackGasLimit_, uint16 requestConfirmations_)
        VRFV2PlusWrapperConsumerBase(wrapper)
    {
        if (wrapper == address(0) || callbackGasLimit_ < 40_000 || requestConfirmations_ < 3) {
            revert InvalidConfiguration();
        }
        callbackGasLimit = callbackGasLimit_;
        requestConfirmations = requestConfirmations_;
    }

    function quoteRequestFee() public view returns (uint256) {
        return IVRFV2PlusWrapper(address(i_vrfV2PlusWrapper)).calculateRequestPriceNative(callbackGasLimit, 1);
    }

    function requestRandomness(bytes32 context, address) external payable returns (bytes32 requestKey) {
        uint256 fee = quoteRequestFee();
        if (msg.value != fee) revert ExactPaymentRequired(fee, msg.value);

        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({ nativePayment: true }));
        (uint256 requestId, uint256 charged) =
            requestRandomnessPayInNative(callbackGasLimit, requestConfirmations, 1, extraArgs);
        if (charged != fee) revert ExactPaymentRequired(fee, charged);

        requestKey = keccak256(
            abi.encode("BANKROLL_VRF_REQUEST_V1", block.chainid, address(this), msg.sender, context, requestId)
        );
        _requests[requestKey] =
            Request({ consumer: msg.sender, context: context, word: bytes32(0), fulfilled: false, consumed: false });
        requestKeyById[requestId] = requestKey;
        emit RandomnessRequested(requestKey, requestId, msg.sender, context, fee);
    }

    function fulfilled(bytes32 requestKey) external view returns (bool) {
        Request storage request = _requests[requestKey];
        return request.fulfilled && !request.consumed;
    }

    function consumeRandomness(bytes32 requestKey) external returns (bytes32 randomWord) {
        Request storage request = _requests[requestKey];
        if (msg.sender != request.consumer) revert UnauthorizedConsumer(msg.sender, request.consumer);
        if (!request.fulfilled || request.consumed) revert RandomnessNotReady(requestKey);
        request.consumed = true;
        randomWord = request.word;
        emit RandomnessConsumed(requestKey, msg.sender);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        bytes32 requestKey = requestKeyById[requestId];
        Request storage request = _requests[requestKey];
        if (request.consumer == address(0) || request.fulfilled || randomWords.length != 1) {
            revert InvalidFulfilment(requestId);
        }
        request.word = bytes32(randomWords[0]);
        request.fulfilled = true;
        emit RandomnessAvailable(requestKey, requestId);
    }
}
