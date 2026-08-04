// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

import { BankrollHook } from "./BankrollHook.sol";
import { BankrollRouter, IWETH } from "./BankrollRouter.sol";
import { IBankrollHook } from "./interfaces/IBankrollHook.sol";

/// @notice CREATE2 deployment and one-time router binding for Bankroll Hook.
/// @dev The caller supplies init code so this factory does not embed the hook bytecode and exceed EIP-170.
contract BankrollHookFactory {
    uint160 public constant ALL_HOOK_MASK = uint160((1 << 14) - 1);
    uint160 public constant REQUIRED_HOOK_FLAGS = uint160(
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
            | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    BankrollRouterFactory public immutable routerFactory;

    error DeploymentAddressMismatch(address actual, address predicted);
    error HookAlreadyDeployed(address hook);
    error InvalidDeployedHook(address hook);
    error InvalidHookAddress(address hook, uint160 actualFlags, uint160 requiredFlags);
    error ZeroAddress();

    event HookDeployed(
        address indexed hook,
        address indexed router,
        address indexed launchedToken,
        address poolManager,
        address weth,
        bytes32 salt,
        bytes32 initCodeHash,
        bytes32 configurationHash
    );

    constructor(BankrollRouterFactory routerFactory_) {
        if (address(routerFactory_) == address(0)) revert ZeroAddress();
        routerFactory = routerFactory_;
    }

    function predict(bytes32 salt, bytes calldata initCode) external view returns (address hook) {
        return Create2.computeAddress(salt, keccak256(initCode));
    }

    function deploy(bytes32 salt, bytes calldata initCode, IPoolManager poolManager, IERC20 launchedToken, IWETH weth)
        external
        returns (BankrollHook hook, BankrollRouter router)
    {
        bytes32 initCodeHash = keccak256(initCode);
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
                || hook.launchedToken() != address(launchedToken) || address(hook.weth()) != address(weth)
        ) revert InvalidDeployedHook(deployed);
        bytes32 routerSalt = keccak256(abi.encode("BANKROLL_ROUTER_V1", deployed));
        router = routerFactory.deploy(routerSalt, poolManager, IBankrollHook(address(hook)), launchedToken, weth);
        hook.bindRouter(address(router));
        emit HookDeployed(
            deployed,
            address(router),
            address(launchedToken),
            address(poolManager),
            address(weth),
            salt,
            initCodeHash,
            hook.configurationHash()
        );
    }
}

/// @notice Isolated router deployer keeps the CREATE2 hook factory below EIP-170.
contract BankrollRouterFactory {
    error DeploymentAddressMismatch(address actual, address predicted);
    error RouterAlreadyDeployed(address router);

    function deploy(bytes32 salt, IPoolManager poolManager, IBankrollHook hook, IERC20 launchedToken, IWETH weth)
        external
        returns (BankrollRouter router)
    {
        bytes memory code = initCode(poolManager, hook, launchedToken, weth);
        address predicted = Create2.computeAddress(salt, keccak256(code));
        if (predicted.code.length != 0) revert RouterAlreadyDeployed(predicted);
        address deployed = Create2.deploy(0, salt, code);
        if (deployed != predicted) revert DeploymentAddressMismatch(deployed, predicted);
        router = BankrollRouter(payable(deployed));
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
