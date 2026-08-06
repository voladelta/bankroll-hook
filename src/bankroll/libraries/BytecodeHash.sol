// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Exact creation-code and immutable-normalised runtime-code checks.
/// @dev Runtime hashes clear only the compiler-recorded immutable slots. Creation-code equality prevents alternate
/// templates.
library BytecodeHash {
    error CreationCodeTooShort(uint256 actual, uint256 expected);
    error CreationCodeMismatch(uint256 offset, bytes1 expected, bytes1 actual);
    error RuntimeCodeLengthMismatch(uint256 actual, uint256 expected);
    error RuntimeCodeHashMismatch(bytes32 actual, bytes32 expected);

    function assertCreationCode(bytes memory initCode, bytes memory expectedCreationCode)
        internal
        pure
        returns (bytes32 creationCodeHash)
    {
        if (initCode.length < expectedCreationCode.length) {
            revert CreationCodeTooShort(initCode.length, expectedCreationCode.length);
        }
        for (uint256 i; i < expectedCreationCode.length; ++i) {
            if (initCode[i] != expectedCreationCode[i]) {
                revert CreationCodeMismatch(i, expectedCreationCode[i], initCode[i]);
            }
        }
        return keccak256(expectedCreationCode);
    }

    function assertHookRuntimeCode(address deployed, uint256 expectedLength, bytes32 expectedHash)
        internal
        view
        returns (bytes32 rawRuntimeCodeHash)
    {
        bytes memory runtimeCode = deployed.code;
        _assertLength(runtimeCode, expectedLength);
        bytes32 rawHash = keccak256(runtimeCode);
        bytes memory normalisedCode = deployed.code;
        _zeroHookImmutables(normalisedCode);
        _assertNormalisedHash(normalisedCode, expectedHash);
        return rawHash;
    }

    function assertRouterRuntimeCode(address deployed, uint256 expectedLength, bytes32 expectedHash)
        internal
        view
        returns (bytes32 rawRuntimeCodeHash)
    {
        bytes memory runtimeCode = deployed.code;
        _assertLength(runtimeCode, expectedLength);
        bytes32 rawHash = keccak256(runtimeCode);
        bytes memory normalisedCode = deployed.code;
        _zeroRouterImmutables(normalisedCode);
        _assertNormalisedHash(normalisedCode, expectedHash);
        return rawHash;
    }

    function normalisedHookRuntimeCode(address deployed) internal view returns (bytes memory runtimeCode) {
        runtimeCode = deployed.code;
        _zeroHookImmutables(runtimeCode);
    }

    function _assertLength(bytes memory runtimeCode, uint256 expectedLength) private pure {
        if (runtimeCode.length != expectedLength) {
            revert RuntimeCodeLengthMismatch(runtimeCode.length, expectedLength);
        }
    }

    function _assertNormalisedHash(bytes memory runtimeCode, bytes32 expectedHash) private pure {
        bytes memory hashInput = bytes.concat(runtimeCode);
        bytes32 normalisedRuntimeCodeHash = keccak256(hashInput);
        if (normalisedRuntimeCodeHash != expectedHash) {
            revert RuntimeCodeHashMismatch(normalisedRuntimeCodeHash, expectedHash);
        }
    }

    function _zeroHookImmutables(bytes memory runtimeCode) private pure {
        assembly {
            let code := add(runtimeCode, 0x20)
            mstore(add(code, 905), 0)
            mstore(add(code, 1053), 0)
            mstore(add(code, 1351), 0)
            mstore(add(code, 1434), 0)
            mstore(add(code, 1771), 0)
            mstore(add(code, 2190), 0)
            mstore(add(code, 2671), 0)
            mstore(add(code, 2845), 0)
            mstore(add(code, 2935), 0)
            mstore(add(code, 3445), 0)
            mstore(add(code, 3695), 0)
            mstore(add(code, 3940), 0)
            mstore(add(code, 3999), 0)
            mstore(add(code, 4094), 0)
            mstore(add(code, 5485), 0)
            mstore(add(code, 6407), 0)
            mstore(add(code, 6630), 0)
            mstore(add(code, 7999), 0)
            mstore(add(code, 8499), 0)
            mstore(add(code, 8861), 0)
            mstore(add(code, 9419), 0)
            mstore(add(code, 9565), 0)
            mstore(add(code, 9678), 0)
            mstore(add(code, 9876), 0)
            mstore(add(code, 9993), 0)
            mstore(add(code, 10400), 0)
            mstore(add(code, 10729), 0)
            mstore(add(code, 11227), 0)
            mstore(add(code, 12022), 0)
            mstore(add(code, 12079), 0)
            mstore(add(code, 12254), 0)
            mstore(add(code, 12592), 0)
            mstore(add(code, 12999), 0)
            mstore(add(code, 13276), 0)
            mstore(add(code, 13343), 0)
            mstore(add(code, 13410), 0)
            mstore(add(code, 13599), 0)
            mstore(add(code, 13753), 0)
            mstore(add(code, 14052), 0)
            mstore(add(code, 14185), 0)
            mstore(add(code, 14369), 0)
            mstore(add(code, 15065), 0)
            mstore(add(code, 15298), 0)
            mstore(add(code, 15342), 0)
            mstore(add(code, 15389), 0)
            mstore(add(code, 15436), 0)
            mstore(add(code, 15483), 0)
            mstore(add(code, 15530), 0)
            mstore(add(code, 15591), 0)
            mstore(add(code, 15648), 0)
            mstore(add(code, 15705), 0)
            mstore(add(code, 15754), 0)
            mstore(add(code, 15803), 0)
            mstore(add(code, 15852), 0)
            mstore(add(code, 15901), 0)
            mstore(add(code, 15944), 0)
            mstore(add(code, 16095), 0)
            mstore(add(code, 16309), 0)
            mstore(add(code, 16375), 0)
            mstore(add(code, 18277), 0)
            mstore(add(code, 20499), 0)
            mstore(add(code, 21828), 0)
        }
    }

    function _zeroRouterImmutables(bytes memory runtimeCode) private pure {
        assembly {
            let code := add(runtimeCode, 0x20)
            mstore(add(code, 144), 0)
            mstore(add(code, 432), 0)
            mstore(add(code, 628), 0)
            mstore(add(code, 862), 0)
            mstore(add(code, 1360), 0)
            mstore(add(code, 2526), 0)
            mstore(add(code, 2821), 0)
            mstore(add(code, 2976), 0)
            mstore(add(code, 4014), 0)
            mstore(add(code, 4079), 0)
        }
    }
}
