// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

import { BankrollHook } from "./BankrollHook.sol";
import { BankrollRouter, IWETH } from "./BankrollRouter.sol";
import { IBankrollHook } from "./interfaces/IBankrollHook.sol";
import { IRandomnessAdapter } from "./interfaces/IRandomnessAdapter.sol";
import { BytecodeHash } from "./libraries/BytecodeHash.sol";
import { BankrollConfig } from "./types/BankrollTypes.sol";

struct CodeProvenance {
    bytes32 creationCodeHash;
    bytes32 runtimeCodeHash;
    bytes32 approvedCreationCodeHash;
    bytes32 approvedRuntimeCodeHash;
}

/// @notice CREATE2 deployment and one-time router binding for Bankroll Hook.
/// @dev The caller supplies init code, but it must match the canonical source and constructor arguments exactly.
contract BankrollHookFactory {
    uint160 public constant ALL_HOOK_MASK = uint160((1 << 14) - 1);
    uint160 public constant REQUIRED_HOOK_FLAGS = uint160(
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
            | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );
    uint256 public constant APPROVED_HOOK_CREATION_CODE_LENGTH = 24_570;
    bytes32 public constant APPROVED_HOOK_CREATION_CODE_HASH =
        0xa21f6c45a4a59d1d458fdf3b56c091650c0bd84beed1cd4fe0a25b7d2a27cc83;
    uint256 public constant APPROVED_HOOK_RUNTIME_CODE_LENGTH = 22_650;
    bytes32 public constant APPROVED_HOOK_RUNTIME_CODE_HASH =
        0x0db8456b774bdc7bdd868369ca50beb7cc7eae2802390f8935e21eaa05158387;

    BankrollRouterFactory public immutable routerFactory;
    bytes32 public immutable approvedHookCreationCodeHash;
    bytes32 public immutable approvedHookRuntimeCodeHash;

    mapping(address hook => CodeProvenance) public hookProvenance;

    error DeploymentAddressMismatch(address actual, address predicted);
    error HookAlreadyDeployed(address hook);
    error InvalidDeployedHook(address hook);
    error InvalidHookAddress(address hook, uint160 actualFlags, uint160 requiredFlags);
    error InvalidHookCreationCodeHash(bytes32 actual, bytes32 expected);
    error InvalidHookConstructorArgs(bytes32 actual, bytes32 expected);
    error ZeroAddress();

    event HookDeployed(
        address indexed hook,
        address indexed router,
        address indexed launchedToken,
        address poolManager,
        address weth,
        bytes32 salt,
        bytes32 initCodeHash,
        bytes32 creationCodeHash,
        bytes32 runtimeCodeHash,
        bytes32 approvedRuntimeCodeHash,
        bytes32 configurationHash
    );

    constructor(BankrollRouterFactory routerFactory_) {
        if (address(routerFactory_) == address(0)) revert ZeroAddress();
        routerFactory = routerFactory_;
        approvedHookCreationCodeHash = APPROVED_HOOK_CREATION_CODE_HASH;
        approvedHookRuntimeCodeHash = APPROVED_HOOK_RUNTIME_CODE_HASH;
    }

    function predict(bytes32 salt, bytes calldata initCode) external view returns (address hook) {
        return Create2.computeAddress(salt, keccak256(initCode));
    }

    function validateHookInitCode(
        bytes calldata initCode,
        IPoolManager poolManager,
        address registrar,
        IERC20 launchedToken,
        IWETH weth,
        IRandomnessAdapter randomnessAdapter,
        BankrollConfig memory config
    ) public view returns (bytes32 initCodeHash) {
        return _validateHookInitCode(initCode, poolManager, registrar, launchedToken, weth, randomnessAdapter, config);
    }

    function deploy(
        bytes32 salt,
        bytes calldata initCode,
        IPoolManager poolManager,
        address registrar,
        IERC20 launchedToken,
        IWETH weth,
        IRandomnessAdapter randomnessAdapter,
        BankrollConfig calldata config
    ) external returns (BankrollHook hook, BankrollRouter router) {
        bytes32 creationCodeHash;
        bytes32 initCodeHash =
            _validateHookInitCode(initCode, poolManager, registrar, launchedToken, weth, randomnessAdapter, config);
        creationCodeHash = keccak256(initCode[:APPROVED_HOOK_CREATION_CODE_LENGTH]);
        if (creationCodeHash != approvedHookCreationCodeHash) {
            revert InvalidHookCreationCodeHash(creationCodeHash, approvedHookCreationCodeHash);
        }

        address predicted = Create2.computeAddress(salt, initCodeHash);
        uint160 actualFlags = uint160(predicted) & ALL_HOOK_MASK;
        if (actualFlags != REQUIRED_HOOK_FLAGS) {
            revert InvalidHookAddress(predicted, actualFlags, REQUIRED_HOOK_FLAGS);
        }
        if (predicted.code.length != 0) revert HookAlreadyDeployed(predicted);
        address deployed = Create2.deploy(0, salt, initCode);
        if (deployed != predicted) revert DeploymentAddressMismatch(deployed, predicted);
        hook = BankrollHook(deployed);
        if (
            hook.factory() != address(this) || address(hook.poolManager()) != address(poolManager)
                || hook.registrar() != registrar || hook.launchedToken() != address(launchedToken)
                || address(hook.weth()) != address(weth)
                || address(hook.randomnessAdapter()) != address(randomnessAdapter)
        ) revert InvalidDeployedHook(deployed);

        bytes32 runtimeCodeHash = BytecodeHash.assertHookRuntimeCode(
            deployed, APPROVED_HOOK_RUNTIME_CODE_LENGTH, approvedHookRuntimeCodeHash
        );

        bytes32 routerSalt = keccak256(abi.encode("BANKROLL_ROUTER_V1", deployed));
        router = routerFactory.deploy(routerSalt, poolManager, IBankrollHook(address(hook)), launchedToken, weth);
        hook.bindRouter(address(router));
        hookProvenance[deployed] = CodeProvenance({
            creationCodeHash: creationCodeHash,
            runtimeCodeHash: runtimeCodeHash,
            approvedCreationCodeHash: approvedHookCreationCodeHash,
            approvedRuntimeCodeHash: approvedHookRuntimeCodeHash
        });
        emit HookDeployed(
            deployed,
            address(router),
            address(launchedToken),
            address(poolManager),
            address(weth),
            salt,
            initCodeHash,
            creationCodeHash,
            runtimeCodeHash,
            approvedHookRuntimeCodeHash,
            hook.configurationHash()
        );
    }

    function _validateHookInitCode(
        bytes calldata initCode,
        IPoolManager poolManager,
        address registrar,
        IERC20 launchedToken,
        IWETH weth,
        IRandomnessAdapter randomnessAdapter,
        BankrollConfig memory config
    ) private view returns (bytes32 initCodeHash) {
        bytes memory constructorArgs = abi.encode(
            poolManager, registrar, launchedToken, weth, randomnessAdapter, config
        );
        if (initCode.length != APPROVED_HOOK_CREATION_CODE_LENGTH + constructorArgs.length) {
            bytes32 shortConstructorArgsHash = bytes32(0);
            if (initCode.length >= APPROVED_HOOK_CREATION_CODE_LENGTH) {
                shortConstructorArgsHash = keccak256(initCode[APPROVED_HOOK_CREATION_CODE_LENGTH:]);
            }
            revert InvalidHookConstructorArgs(shortConstructorArgsHash, keccak256(constructorArgs));
        }
        bytes32 creationCodeHash = keccak256(initCode[:APPROVED_HOOK_CREATION_CODE_LENGTH]);
        if (creationCodeHash != approvedHookCreationCodeHash) {
            revert InvalidHookCreationCodeHash(creationCodeHash, approvedHookCreationCodeHash);
        }
        bytes32 actualConstructorArgsHash = keccak256(initCode[APPROVED_HOOK_CREATION_CODE_LENGTH:]);
        bytes32 expectedConstructorArgsHash = keccak256(constructorArgs);
        if (actualConstructorArgsHash != expectedConstructorArgsHash) {
            revert InvalidHookConstructorArgs(actualConstructorArgsHash, expectedConstructorArgsHash);
        }
        return keccak256(initCode);
    }
}

/// @notice Isolated router deployer keeps the CREATE2 hook factory below EIP-170.
contract BankrollRouterFactory {
    uint256 public constant APPROVED_ROUTER_CREATION_CODE_LENGTH = 5949;
    bytes32 public constant APPROVED_ROUTER_CREATION_CODE_HASH =
        0xe1ce945bbb95bd1dcf9ffc7da4c1585009416599fdb21340768d4020c8e9556d;
    uint256 public constant APPROVED_ROUTER_RUNTIME_CODE_LENGTH = 5316;
    bytes32 public constant APPROVED_ROUTER_RUNTIME_CODE_HASH =
        0xef3209b3d091029d17ff449fd871ce3fa8f1dd3aae43f22b3cae1148879e89bf;
    bytes32 public immutable approvedRouterCreationCodeHash;
    bytes32 public immutable approvedRouterRuntimeCodeHash;

    mapping(address router => CodeProvenance) public routerProvenance;

    error DeploymentAddressMismatch(address actual, address predicted);
    error InvalidRouterCreationCodeHash(bytes32 actual, bytes32 expected);
    error RouterAlreadyDeployed(address router);

    constructor() {
        approvedRouterCreationCodeHash = APPROVED_ROUTER_CREATION_CODE_HASH;
        approvedRouterRuntimeCodeHash = APPROVED_ROUTER_RUNTIME_CODE_HASH;
    }

    function deploy(bytes32 salt, IPoolManager poolManager, IBankrollHook hook, IERC20 launchedToken, IWETH weth)
        external
        returns (BankrollRouter router)
    {
        bytes memory code = initCode(poolManager, hook, launchedToken, weth);
        bytes32 creationCodeHash = BytecodeHash.assertCreationCode(code, type(BankrollRouter).creationCode);
        if (creationCodeHash != approvedRouterCreationCodeHash) {
            revert InvalidRouterCreationCodeHash(creationCodeHash, approvedRouterCreationCodeHash);
        }

        bytes32 initCodeHash = keccak256(code);
        address predicted = Create2.computeAddress(salt, initCodeHash);
        if (predicted.code.length != 0) revert RouterAlreadyDeployed(predicted);
        address deployed = Create2.deploy(0, salt, code);
        if (deployed != predicted) revert DeploymentAddressMismatch(deployed, predicted);
        router = BankrollRouter(payable(deployed));

        bytes32 runtimeCodeHash = BytecodeHash.assertRouterRuntimeCode(
            deployed, APPROVED_ROUTER_RUNTIME_CODE_LENGTH, approvedRouterRuntimeCodeHash
        );
        routerProvenance[deployed] = CodeProvenance({
            creationCodeHash: creationCodeHash,
            runtimeCodeHash: runtimeCodeHash,
            approvedCreationCodeHash: approvedRouterCreationCodeHash,
            approvedRuntimeCodeHash: approvedRouterRuntimeCodeHash
        });
    }

    function predict(bytes32 salt, IPoolManager poolManager, IBankrollHook hook, IERC20 launchedToken, IWETH weth)
        external
        view
        returns (address)
    {
        return Create2.computeAddress(salt, keccak256(initCode(poolManager, hook, launchedToken, weth)));
    }

    function initCode(IPoolManager poolManager, IBankrollHook hook, IERC20 launchedToken, IWETH weth)
        public
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(type(BankrollRouter).creationCode, abi.encode(poolManager, hook, launchedToken, weth));
    }
}
