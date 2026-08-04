// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { BankrollHookData } from "../../../src/bankroll/libraries/BankrollHookData.sol";

contract HookDataHarness {
    function encode(bytes32 pendingId) external pure returns (bytes memory) {
        return BankrollHookData.encode(pendingId);
    }

    function decode(bytes calldata data) external pure returns (bytes32) {
        return BankrollHookData.decode(data);
    }
}

contract HookDataTest is Test {
    HookDataHarness internal hookData;

    function setUp() public {
        hookData = new HookDataHarness();
    }

    function testRoundTrip() public view {
        bytes32 pendingId = keccak256("pending");
        bytes memory encoded = hookData.encode(pendingId);
        assertEq(encoded.length, 64);
        assertEq(hookData.decode(encoded), pendingId);
    }

    function testRejectsMalformedLength() public {
        vm.expectRevert(abi.encodeWithSelector(BankrollHookData.InvalidHookDataLength.selector, 1));
        hookData.decode(hex"01");
    }

    function testRejectsUnknownVersion() public {
        vm.expectRevert(abi.encodeWithSelector(BankrollHookData.UnsupportedHookDataVersion.selector, 2));
        hookData.decode(abi.encode(uint8(2), bytes32(uint256(1))));
    }
}
