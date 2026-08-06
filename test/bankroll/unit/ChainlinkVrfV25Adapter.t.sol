// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { VRFV2PlusWrapperConsumerBase } from "@chainlink/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";

import { ChainlinkVrfV25Adapter } from "../../../src/bankroll/randomness/ChainlinkVrfV25Adapter.sol";
import { MockVrfWrapper } from "../helpers/MockVrfWrapper.sol";

contract ChainlinkVrfV25AdapterTest is Test {
    uint256 internal constant FEE = 0.01 ether;

    MockVrfWrapper internal wrapper;
    ChainlinkVrfV25Adapter internal adapter;

    function setUp() public {
        wrapper = new MockVrfWrapper(FEE);
        adapter = new ChainlinkVrfV25Adapter(address(wrapper), 200_000, 3);
        vm.deal(address(this), 10 ether);
    }

    function testExactPaymentAndQuote() public {
        assertEq(adapter.quoteRequestFee(), FEE);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkVrfV25Adapter.ExactPaymentRequired.selector, FEE, FEE - 1));
        adapter.requestRandomness{ value: FEE - 1 }(keccak256("underpaid"), address(this));
        vm.expectRevert(abi.encodeWithSelector(ChainlinkVrfV25Adapter.ExactPaymentRequired.selector, FEE, FEE + 1));
        adapter.requestRandomness{ value: FEE + 1 }(keccak256("overpaid"), address(this));

        bytes32 requestKey = adapter.requestRandomness{ value: FEE }(keccak256("exact"), address(this));
        assertEq(adapter.requestKeyById(1), requestKey);
        assertFalse(adapter.fulfilled(requestKey));
    }

    function testRepeatedRequestIdRevertsAtomically() public {
        adapter.requestRandomness{ value: FEE }(keccak256("first"), address(this));
        wrapper.setRepeatRequestId(true);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkVrfV25Adapter.DuplicateRequestId.selector, 1));
        adapter.requestRandomness{ value: FEE }(keccak256("second"), address(this));
        assertEq(wrapper.lastRequestId(), 1);
    }

    function testOnlyWrapperCanFulfillAndUnknownOrDuplicateFulfillmentReverts() public {
        bytes32 requestKey = adapter.requestRandomness{ value: FEE }(keccak256("known"), address(this));
        uint256[] memory words = new uint256[](1);
        words[0] = 42;

        vm.expectRevert(
            abi.encodeWithSelector(
                VRFV2PlusWrapperConsumerBase.OnlyVRFWrapperCanFulfill.selector, address(this), address(wrapper)
            )
        );
        adapter.rawFulfillRandomWords(1, words);

        vm.expectRevert(abi.encodeWithSelector(ChainlinkVrfV25Adapter.InvalidFulfilment.selector, 999));
        wrapper.fulfill(address(adapter), 999, words);
        wrapper.fulfill(address(adapter), 1, words);
        assertTrue(adapter.fulfilled(requestKey));
        vm.expectRevert(abi.encodeWithSelector(ChainlinkVrfV25Adapter.InvalidFulfilment.selector, 1));
        wrapper.fulfill(address(adapter), 1, words);

        uint256[] memory wrongLength = new uint256[](2);
        bytes32 second = adapter.requestRandomness{ value: FEE }(keccak256("wrong length"), address(this));
        vm.expectRevert(abi.encodeWithSelector(ChainlinkVrfV25Adapter.InvalidFulfilment.selector, 2));
        wrapper.fulfill(address(adapter), 2, wrongLength);
        assertFalse(adapter.fulfilled(second));
    }

    function testOnlyConsumerCanConsumeAndConsumptionIsOneShot() public {
        bytes32 requestKey = adapter.requestRandomness{ value: FEE }(keccak256("consume"), address(this));
        uint256[] memory words = new uint256[](1);
        words[0] = 42;
        wrapper.fulfill(address(adapter), 1, words);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(ChainlinkVrfV25Adapter.UnauthorizedConsumer.selector, stranger, address(this))
        );
        adapter.consumeRandomness(requestKey);
        assertEq(adapter.consumeRandomness(requestKey), bytes32(uint256(42)));
        assertFalse(adapter.fulfilled(requestKey));
        vm.expectRevert(abi.encodeWithSelector(ChainlinkVrfV25Adapter.RandomnessNotReady.selector, requestKey));
        adapter.consumeRandomness(requestKey);

        bytes32 unknown = keccak256("unknown");
        vm.expectRevert(
            abi.encodeWithSelector(ChainlinkVrfV25Adapter.UnauthorizedConsumer.selector, address(this), address(0))
        );
        adapter.consumeRandomness(unknown);
    }
}
