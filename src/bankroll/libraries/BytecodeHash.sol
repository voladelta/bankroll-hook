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
            mstore(add(code, 927), 0)
            mstore(add(code, 1075), 0)
            mstore(add(code, 1373), 0)
            mstore(add(code, 1456), 0)
            mstore(add(code, 1793), 0)
            mstore(add(code, 2212), 0)
            mstore(add(code, 2700), 0)
            mstore(add(code, 2874), 0)
            mstore(add(code, 2964), 0)
            mstore(add(code, 3474), 0)
            mstore(add(code, 3724), 0)
            mstore(add(code, 4047), 0)
            mstore(add(code, 4106), 0)
            mstore(add(code, 4201), 0)
            mstore(add(code, 5592), 0)
            mstore(add(code, 6514), 0)
            mstore(add(code, 6737), 0)
            mstore(add(code, 8098), 0)
            mstore(add(code, 8598), 0)
            mstore(add(code, 8960), 0)
            mstore(add(code, 9523), 0)
            mstore(add(code, 9669), 0)
            mstore(add(code, 9782), 0)
            mstore(add(code, 9980), 0)
            mstore(add(code, 10097), 0)
            mstore(add(code, 10504), 0)
            mstore(add(code, 10833), 0)
            mstore(add(code, 11331), 0)
            mstore(add(code, 12126), 0)
            mstore(add(code, 12183), 0)
            mstore(add(code, 12358), 0)
            mstore(add(code, 12696), 0)
            mstore(add(code, 13103), 0)
            mstore(add(code, 13380), 0)
            mstore(add(code, 13555), 0)
            mstore(add(code, 13622), 0)
            mstore(add(code, 13811), 0)
            mstore(add(code, 13965), 0)
            mstore(add(code, 14264), 0)
            mstore(add(code, 14397), 0)
            mstore(add(code, 14581), 0)
            mstore(add(code, 15277), 0)
            mstore(add(code, 15510), 0)
            mstore(add(code, 15554), 0)
            mstore(add(code, 15601), 0)
            mstore(add(code, 15648), 0)
            mstore(add(code, 15695), 0)
            mstore(add(code, 15742), 0)
            mstore(add(code, 15803), 0)
            mstore(add(code, 15860), 0)
            mstore(add(code, 15917), 0)
            mstore(add(code, 15966), 0)
            mstore(add(code, 16015), 0)
            mstore(add(code, 16064), 0)
            mstore(add(code, 16113), 0)
            mstore(add(code, 16156), 0)
            mstore(add(code, 16307), 0)
            mstore(add(code, 16521), 0)
            mstore(add(code, 16587), 0)
            mstore(add(code, 18511), 0)
            mstore(add(code, 20712), 0)
            mstore(add(code, 21879), 0)
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
