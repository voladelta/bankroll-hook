// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library BankrollHookData {
    uint8 internal constant VERSION = 1;
    uint256 internal constant ENCODED_LENGTH = 64;

    error InvalidHookDataLength(uint256 actual);
    error UnsupportedHookDataVersion(uint8 actual);

    function encode(bytes32 pendingId) internal pure returns (bytes memory) {
        return abi.encode(VERSION, pendingId);
    }

    function decode(bytes calldata data) internal pure returns (bytes32 pendingId) {
        if (data.length != ENCODED_LENGTH) revert InvalidHookDataLength(data.length);
        (uint8 version, bytes32 decodedId) = abi.decode(data, (uint8, bytes32));
        if (version != VERSION) revert UnsupportedHookDataVersion(version);
        return decodedId;
    }
}
