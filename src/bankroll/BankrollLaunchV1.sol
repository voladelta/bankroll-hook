// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { CurrencySettler } from "@openzeppelin/uniswap-hooks/src/utils/CurrencySettler.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import { Pool } from "@uniswap/v4-core/src/libraries/Pool.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { ActionConstants } from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { LiquidityAmounts } from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

import { BankrollHook } from "./BankrollHook.sol";
import { BankrollHookFactory, BankrollRouterFactory } from "./BankrollHookFactory.sol";
import { BankrollRouter, IWETH } from "./BankrollRouter.sol";
import { PermanentPositionLocker } from "./PermanentPositionLocker.sol";
import { IRandomnessAdapter } from "./interfaces/IRandomnessAdapter.sol";
import { BankrollConfig } from "./types/BankrollTypes.sol";

struct UERC20Metadata {
    string description;
    string website;
    string image;
    bytes extraData;
}

interface IUERC20Factory {
    function getUERC20Address(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address creator,
        bytes32 graffiti
    ) external view returns (address);

    function createToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 initialSupply,
        address creator,
        bytes calldata tokenData,
        bytes32 graffiti
    ) external returns (address);
}

/// @notice Creates one fixed-supply token, its bound hook and router, and one permanently locked v4 position.
/// @dev Dependency addresses are immutable constructor inputs; deployment tooling must bind them to reviewed runtime
/// evidence.
contract BankrollLaunchV1 is IUnlockCallback, ReentrancyGuardTransient {
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using SafeCast for *;

    uint8 public constant TOKEN_DECIMALS = 18;
    uint256 public constant TOKEN_SUPPLY = 1_000_000_000 ether;
    uint256 public constant MIN_NONZERO_INITIAL_BUY = 0.0006 ether;
    uint256 public constant MAX_TOKEN_NAME_BYTES = 48;
    uint256 public constant MAX_TOKEN_SYMBOL_BYTES = 12;
    uint256 public constant MAX_TOKEN_DESCRIPTION_BYTES = 280;
    uint256 public constant MAX_METADATA_URL_BYTES = 2048;
    uint256 public constant MAX_SOCIAL_EXTRA_DATA_BYTES = 1200;
    int24 public constant INITIAL_TICK = 204_200;
    int24 public constant TICK_SPACING = 200;
    uint24 public constant LP_FEE_PIPS = 0;
    bytes32 public constant REVIEWED_HOOK_CREATION_CODE_HASH =
        0xa21f6c45a4a59d1d458fdf3b56c091650c0bd84beed1cd4fe0a25b7d2a27cc83;
    bytes32 public constant REVIEWED_HOOK_RUNTIME_CODE_HASH =
        0x0db8456b774bdc7bdd868369ca50beb7cc7eae2802390f8935e21eaa05158387;
    bytes32 public constant REVIEWED_ROUTER_CREATION_CODE_HASH =
        0xe1ce945bbb95bd1dcf9ffc7da4c1585009416599fdb21340768d4020c8e9556d;
    bytes32 public constant REVIEWED_ROUTER_RUNTIME_CODE_HASH =
        0xef3209b3d091029d17ff449fd871ce3fa8f1dd3aae43f22b3cae1148879e89bf;
    Currency private constant NATIVE = Currency.wrap(address(0));

    IPoolManager public immutable poolManager;
    IPositionManager public immutable positionManager;
    IUERC20Factory public immutable tokenFactory;
    BankrollHookFactory public immutable hookFactory;
    IWETH public immutable weth;
    IRandomnessAdapter public immutable randomnessAdapter;
    bytes32 public immutable approvedHookCreationCodeHash;
    bytes32 public immutable approvedHookRuntimeCodeHash;
    bytes32 public immutable approvedRouterCreationCodeHash;
    bytes32 public immutable approvedRouterRuntimeCodeHash;

    mapping(address token => bytes32 launchHash) public launchHashOf;

    struct LaunchParameters {
        string name;
        string symbol;
        bytes32 creatorSalt;
        bytes32 hookSalt;
        bytes hookInitCode;
        uint256 minimumInitialBuyTokenAmount;
        UERC20Metadata metadata;
        BankrollConfig game;
    }

    struct LaunchResult {
        address token;
        BankrollHook hook;
        BankrollRouter router;
        PermanentPositionLocker positionLocker;
        uint256 positionTokenId;
        uint256 tokenLiquidityAmount;
        uint256 lockedTokenDust;
        uint256 initialBuyNativeAmount;
        uint256 initialBuyTokenAmount;
        bytes32 poolId;
        bytes32 hookCreationCodeHash;
        bytes32 hookRuntimeCodeHash;
        bytes32 routerCreationCodeHash;
        bytes32 routerRuntimeCodeHash;
        bytes32 launchHash;
    }

    struct InitialBuyCallbackData {
        PoolKey key;
        address recipient;
        uint256 nativeAmount;
    }

    error EmptyName();
    error EmptySymbol();
    error InitialBuyBelowMinimum(uint256 actual, uint256 minimum);
    error InvalidDependency(address dependency);
    error InvalidHookConfiguration(bytes32 actual, bytes32 expected);
    error InvalidLaunchBytecodeHash(bytes32 actual, bytes32 expected);
    error InvalidInitialBuyDelta(int128 nativeDelta, int128 tokenDelta);
    error InvalidInitialBuyMinimum(uint256 minimumTokenAmount);
    error InitialBuyMinimumOutputNotMet(uint256 actual, uint256 minimum);
    error InvalidInitialBuyResult(uint256 tokenAmount, uint256 nativeBalance);
    error InvalidInitialBuySettlement(uint256 actual, uint256 expected);
    error InvalidInitialTick(int24 actual, int24 expected);
    error InvalidPosition(uint256 liquidity, uint256 tokenAmount);
    error InvalidPositionManager(address expectedPoolManager, address actualPoolManager);
    error MetadataExtraDataTooLong(uint256 actual, uint256 maximum);
    error MetadataImageTooLong(uint256 actual, uint256 maximum);
    error MetadataWebsiteTooLong(uint256 actual, uint256 maximum);
    error TokenAddressMismatch(address actual, address predicted);
    error TokenAlreadyExists(address token);
    error TokenCustodyMismatch(uint256 launcherBalance, uint256 positionManagerBalance);
    error TokenDescriptionTooLong(uint256 actual, uint256 maximum);
    error TokenNameTooLong(uint256 actual, uint256 maximum);
    error TokenSymbolTooLong(uint256 actual, uint256 maximum);
    error UnauthorizedUnlockCallback(address caller);

    event BankrollTokenLaunched(
        address indexed creator,
        address indexed token,
        bytes32 indexed poolId,
        address hook,
        address router,
        address positionLocker,
        uint256 positionTokenId,
        bytes32 launchHash
    );
    event BankrollLiquidityConfigured(
        address indexed token,
        uint256 totalSupply,
        uint256 tokenLiquidityAmount,
        uint256 lockedTokenDust,
        int24 initialTick,
        int24 tickLower,
        int24 tickUpper,
        bytes32 launchHash
    );
    event BankrollInitialBuy(
        address indexed creator,
        address indexed token,
        bytes32 indexed poolId,
        uint256 nativeAmount,
        uint256 tokenAmount,
        bytes32 launchHash
    );
    event BankrollLaunchProvenance(
        address indexed token,
        address indexed hook,
        address indexed router,
        bytes32 hookCreationCodeHash,
        bytes32 hookRuntimeCodeHash,
        bytes32 routerCreationCodeHash,
        bytes32 routerRuntimeCodeHash,
        bytes32 approvedHookCreationCodeHash,
        bytes32 approvedHookRuntimeCodeHash,
        bytes32 approvedRouterCreationCodeHash,
        bytes32 approvedRouterRuntimeCodeHash,
        bytes32 launchHash
    );

    constructor(
        IPoolManager poolManager_,
        IPositionManager positionManager_,
        IUERC20Factory tokenFactory_,
        BankrollHookFactory hookFactory_,
        IWETH weth_,
        IRandomnessAdapter randomnessAdapter_
    ) {
        _requireContract(address(poolManager_));
        _requireContract(address(positionManager_));
        _requireContract(address(tokenFactory_));
        _requireContract(address(hookFactory_));
        _requireContract(address(weth_));
        _requireContract(address(randomnessAdapter_));
        address actualManager = address(positionManager_.poolManager());
        if (actualManager != address(poolManager_)) {
            revert InvalidPositionManager(address(poolManager_), actualManager);
        }
        poolManager = poolManager_;
        positionManager = positionManager_;
        tokenFactory = tokenFactory_;
        hookFactory = hookFactory_;
        weth = weth_;
        randomnessAdapter = randomnessAdapter_;
        approvedHookCreationCodeHash = hookFactory_.approvedHookCreationCodeHash();
        _requireApprovedHash(approvedHookCreationCodeHash, REVIEWED_HOOK_CREATION_CODE_HASH);
        approvedHookRuntimeCodeHash = hookFactory_.approvedHookRuntimeCodeHash();
        _requireApprovedHash(approvedHookRuntimeCodeHash, REVIEWED_HOOK_RUNTIME_CODE_HASH);
        BankrollRouterFactory routerFactory_ = hookFactory_.routerFactory();
        approvedRouterCreationCodeHash = routerFactory_.approvedRouterCreationCodeHash();
        _requireApprovedHash(approvedRouterCreationCodeHash, REVIEWED_ROUTER_CREATION_CODE_HASH);
        approvedRouterRuntimeCodeHash = routerFactory_.approvedRouterRuntimeCodeHash();
        _requireApprovedHash(approvedRouterRuntimeCodeHash, REVIEWED_ROUTER_RUNTIME_CODE_HASH);
    }

    function predictTokenAddress(string calldata name, string calldata symbol, address creator, bytes32 creatorSalt)
        external
        view
        returns (address token, bytes32 effectiveGraffiti)
    {
        effectiveGraffiti = _effectiveGraffiti(creator, creatorSalt);
        token = tokenFactory.getUERC20Address(name, symbol, TOKEN_DECIMALS, address(this), effectiveGraffiti);
    }

    function launch(LaunchParameters calldata parameters)
        external
        payable
        nonReentrant
        returns (LaunchResult memory result)
    {
        _validateLaunch(parameters);
        result.initialBuyNativeAmount = msg.value;
        bytes32 effectiveGraffiti = _effectiveGraffiti(msg.sender, parameters.creatorSalt);
        result.token = tokenFactory.getUERC20Address(
            parameters.name, parameters.symbol, TOKEN_DECIMALS, address(this), effectiveGraffiti
        );
        if (result.token.code.length != 0) revert TokenAlreadyExists(result.token);

        (result.hook, result.router) = hookFactory.deploy(
            parameters.hookSalt,
            parameters.hookInitCode,
            poolManager,
            address(this),
            IERC20(result.token),
            weth,
            randomnessAdapter,
            parameters.game
        );
        (
            bytes32 hookCreationCodeHash,
            bytes32 hookRuntimeCodeHash,
            bytes32 hookApprovedCreationCodeHash,
            bytes32 hookApprovedRuntimeCodeHash
        ) = hookFactory.hookProvenance(address(result.hook));
        (
            bytes32 routerCreationCodeHash,
            bytes32 routerRuntimeCodeHash,
            bytes32 routerApprovedCreationCodeHash,
            bytes32 routerApprovedRuntimeCodeHash
        ) = BankrollRouterFactory(address(hookFactory.routerFactory())).routerProvenance(address(result.router));
        result.hookCreationCodeHash = hookCreationCodeHash;
        result.hookRuntimeCodeHash = hookRuntimeCodeHash;
        result.routerCreationCodeHash = routerCreationCodeHash;
        result.routerRuntimeCodeHash = routerRuntimeCodeHash;
        if (
            hookApprovedCreationCodeHash != approvedHookCreationCodeHash
                || hookApprovedRuntimeCodeHash != approvedHookRuntimeCodeHash
                || routerApprovedCreationCodeHash != approvedRouterCreationCodeHash
                || routerApprovedRuntimeCodeHash != approvedRouterRuntimeCodeHash
                || result.hookCreationCodeHash != approvedHookCreationCodeHash
                || result.routerCreationCodeHash != approvedRouterCreationCodeHash
        ) {
            revert InvalidLaunchBytecodeHash(result.hookRuntimeCodeHash, approvedHookRuntimeCodeHash);
        }
        bytes32 expectedConfiguration = _expectedHookConfiguration(result, parameters.game);
        bytes32 actualConfiguration = result.hook.configurationHash();
        if (actualConfiguration != expectedConfiguration) {
            revert InvalidHookConfiguration(actualConfiguration, expectedConfiguration);
        }

        result.positionLocker =
            new PermanentPositionLocker{ salt: _positionSalt(result.token, msg.sender) }(positionManager, msg.sender);
        _createToken(parameters, effectiveGraffiti, result.token);

        PoolKey memory key = _poolKey(result.token, result.hook);
        result.poolId = PoolId.unwrap(key.toId());
        int24 initializedTick = poolManager.initialize(key, TickMath.getSqrtPriceAtTick(INITIAL_TICK));
        if (initializedTick != INITIAL_TICK) revert InvalidInitialTick(initializedTick, INITIAL_TICK);

        result.positionTokenId = positionManager.nextTokenId();
        (result.tokenLiquidityAmount, result.lockedTokenDust) =
            _placeOneSidedLiquidity(key, address(result.positionLocker));
        if (msg.value != 0) {
            result.initialBuyTokenAmount =
                _executeInitialBuy(key, msg.sender, msg.value, parameters.minimumInitialBuyTokenAmount);
        }
        result.launchHash = _recordLaunch(parameters, result, msg.sender);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert UnauthorizedUnlockCallback(msg.sender);
        InitialBuyCallbackData memory callback = abi.decode(data, (InitialBuyCallbackData));
        BalanceDelta delta = poolManager.swap(
            callback.key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -callback.nativeAmount.toInt256(),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            ""
        );
        int128 nativeDelta = delta.amount0();
        int128 tokenDelta = delta.amount1();
        if (nativeDelta >= 0 || tokenDelta <= 0) revert InvalidInitialBuyDelta(nativeDelta, tokenDelta);
        uint256 nativeSettlement = (-int256(nativeDelta)).toUint256();
        if (nativeSettlement != callback.nativeAmount) {
            revert InvalidInitialBuySettlement(nativeSettlement, callback.nativeAmount);
        }
        uint256 tokenAmount = int256(tokenDelta).toUint256();
        NATIVE.settle(poolManager, address(this), nativeSettlement, false);
        callback.key.currency1.take(poolManager, callback.recipient, tokenAmount, false);
        return abi.encode(tokenAmount);
    }

    function poolKey(address token, BankrollHook hook) external pure returns (PoolKey memory) {
        return _poolKey(token, hook);
    }

    function _placeOneSidedLiquidity(PoolKey memory key, address locker)
        private
        returns (uint256 tokenAmount, uint256 dust)
    {
        int24 lower = TickMath.minUsableTick(TICK_SPACING);
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(lower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(INITIAL_TICK);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtUpper, TOKEN_SUPPLY);
        uint128 maximum = Pool.tickSpacingToMaxLiquidityPerTick(TICK_SPACING);
        if (liquidity > maximum) liquidity = maximum;
        tokenAmount = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, true);
        if (tokenAmount > TOKEN_SUPPLY) {
            --liquidity;
            tokenAmount = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, true);
        }
        if (tokenAmount > TOKEN_SUPPLY) revert InvalidPosition(liquidity, tokenAmount);
        if (liquidity == 0 || tokenAmount == 0) revert InvalidPosition(liquidity, tokenAmount);
        dust = TOKEN_SUPPLY - tokenAmount;

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE), uint8(Actions.SETTLE), uint8(Actions.TAKE_PAIR)
        );
        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(key, lower, INITIAL_TICK, liquidity, 0, tokenAmount, locker, bytes(""));
        params[1] = abi.encode(key.currency0, ActionConstants.CONTRACT_BALANCE, false);
        params[2] = abi.encode(key.currency1, ActionConstants.CONTRACT_BALANCE, false);
        params[3] = abi.encode(key.currency0, key.currency1, locker);

        key.currency1.transfer(address(positionManager), TOKEN_SUPPLY);
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);
        uint256 launcherBalance = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(this));
        uint256 positionManagerBalance = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(positionManager));
        if (launcherBalance != 0 || positionManagerBalance != 0) {
            revert TokenCustodyMismatch(launcherBalance, positionManagerBalance);
        }
    }

    function _executeInitialBuy(PoolKey memory key, address recipient, uint256 nativeAmount, uint256 minimumTokenAmount)
        private
        returns (uint256 tokenAmount)
    {
        bytes memory result = poolManager.unlock(
            abi.encode(InitialBuyCallbackData({ key: key, recipient: recipient, nativeAmount: nativeAmount }))
        );
        tokenAmount = abi.decode(result, (uint256));
        if (tokenAmount < minimumTokenAmount) {
            revert InitialBuyMinimumOutputNotMet(tokenAmount, minimumTokenAmount);
        }
        if (tokenAmount == 0 || address(this).balance != 0) {
            revert InvalidInitialBuyResult(tokenAmount, address(this).balance);
        }
    }

    function _createToken(LaunchParameters calldata parameters, bytes32 graffiti, address predicted) private {
        address token = tokenFactory.createToken(
            parameters.name,
            parameters.symbol,
            TOKEN_DECIMALS,
            TOKEN_SUPPLY,
            address(this),
            abi.encode(parameters.metadata),
            graffiti
        );
        if (token != predicted) revert TokenAddressMismatch(token, predicted);
    }

    function _expectedHookConfiguration(LaunchResult memory result, BankrollConfig calldata game)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                address(poolManager),
                address(hookFactory),
                address(this),
                result.token,
                address(weth),
                address(randomnessAdapter),
                address(result.router),
                game.minimumWager,
                game.maximumWager,
                game.minimumBankrollAssets,
                game.fundingBlocks,
                game.activeBlocks,
                game.requestGraceBlocks,
                game.fulfillmentTimeoutBlocks,
                game.maximumSettlementBatch
            )
        );
    }

    function _requireApprovedHash(bytes32 actual, bytes32 expected) private pure {
        if (actual != expected) revert InvalidLaunchBytecodeHash(actual, expected);
    }

    function _recordLaunch(LaunchParameters calldata parameters, LaunchResult memory result, address creator)
        private
        returns (bytes32 launchHash)
    {
        bytes32 infrastructureHash = keccak256(
            abi.encode(
                creator,
                result.token,
                address(result.hook),
                address(result.router),
                address(result.positionLocker),
                result.positionTokenId,
                result.poolId,
                result.hook.configurationHash(),
                result.hookCreationCodeHash,
                result.hookRuntimeCodeHash,
                result.routerCreationCodeHash,
                result.routerRuntimeCodeHash,
                approvedHookCreationCodeHash,
                approvedHookRuntimeCodeHash,
                approvedRouterCreationCodeHash,
                approvedRouterRuntimeCodeHash
            )
        );
        bytes32 economicsHash = keccak256(
            abi.encode(
                TOKEN_SUPPLY,
                result.tokenLiquidityAmount,
                result.lockedTokenDust,
                result.initialBuyNativeAmount,
                result.initialBuyTokenAmount,
                parameters.minimumInitialBuyTokenAmount,
                INITIAL_TICK,
                TICK_SPACING,
                LP_FEE_PIPS,
                parameters.game
            )
        );
        launchHash = keccak256(abi.encode(block.chainid, address(this), infrastructureHash, economicsHash));
        launchHashOf[result.token] = launchHash;
        emit BankrollLaunchProvenance(
            result.token,
            address(result.hook),
            address(result.router),
            result.hookCreationCodeHash,
            result.hookRuntimeCodeHash,
            result.routerCreationCodeHash,
            result.routerRuntimeCodeHash,
            approvedHookCreationCodeHash,
            approvedHookRuntimeCodeHash,
            approvedRouterCreationCodeHash,
            approvedRouterRuntimeCodeHash,
            launchHash
        );
        emit BankrollTokenLaunched(
            creator,
            result.token,
            result.poolId,
            address(result.hook),
            address(result.router),
            address(result.positionLocker),
            result.positionTokenId,
            launchHash
        );
        emit BankrollLiquidityConfigured(
            result.token,
            TOKEN_SUPPLY,
            result.tokenLiquidityAmount,
            result.lockedTokenDust,
            INITIAL_TICK,
            TickMath.minUsableTick(TICK_SPACING),
            INITIAL_TICK,
            launchHash
        );
        if (result.initialBuyNativeAmount != 0) {
            emit BankrollInitialBuy(
                creator,
                result.token,
                result.poolId,
                result.initialBuyNativeAmount,
                result.initialBuyTokenAmount,
                launchHash
            );
        }
    }

    function _poolKey(address token, BankrollHook hook) private pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(token),
            fee: LP_FEE_PIPS,
            tickSpacing: TICK_SPACING,
            hooks: hook
        });
    }

    function _validateLaunch(LaunchParameters calldata parameters) private view {
        uint256 nameBytes = bytes(parameters.name).length;
        uint256 symbolBytes = bytes(parameters.symbol).length;
        if (nameBytes == 0) revert EmptyName();
        if (symbolBytes == 0) revert EmptySymbol();
        if (nameBytes > MAX_TOKEN_NAME_BYTES) revert TokenNameTooLong(nameBytes, MAX_TOKEN_NAME_BYTES);
        if (symbolBytes > MAX_TOKEN_SYMBOL_BYTES) revert TokenSymbolTooLong(symbolBytes, MAX_TOKEN_SYMBOL_BYTES);
        uint256 descriptionBytes = bytes(parameters.metadata.description).length;
        uint256 websiteBytes = bytes(parameters.metadata.website).length;
        uint256 imageBytes = bytes(parameters.metadata.image).length;
        uint256 extraBytes = parameters.metadata.extraData.length;
        if (descriptionBytes > MAX_TOKEN_DESCRIPTION_BYTES) {
            revert TokenDescriptionTooLong(descriptionBytes, MAX_TOKEN_DESCRIPTION_BYTES);
        }
        if (websiteBytes > MAX_METADATA_URL_BYTES) revert MetadataWebsiteTooLong(websiteBytes, MAX_METADATA_URL_BYTES);
        if (imageBytes > MAX_METADATA_URL_BYTES) revert MetadataImageTooLong(imageBytes, MAX_METADATA_URL_BYTES);
        if (extraBytes > MAX_SOCIAL_EXTRA_DATA_BYTES) {
            revert MetadataExtraDataTooLong(extraBytes, MAX_SOCIAL_EXTRA_DATA_BYTES);
        }
        if (msg.value != 0 && msg.value < MIN_NONZERO_INITIAL_BUY) {
            revert InitialBuyBelowMinimum(msg.value, MIN_NONZERO_INITIAL_BUY);
        }
        if (msg.value == 0 && parameters.minimumInitialBuyTokenAmount != 0) {
            revert InvalidInitialBuyMinimum(parameters.minimumInitialBuyTokenAmount);
        }
    }

    function _effectiveGraffiti(address creator, bytes32 creatorSalt) private pure returns (bytes32) {
        return keccak256(abi.encode(creator, creatorSalt));
    }

    function _positionSalt(address token, address creator) private pure returns (bytes32) {
        return keccak256(abi.encode("BANKROLL_POSITION_V1", token, creator));
    }

    function _requireContract(address dependency) private view {
        if (dependency == address(0) || dependency.code.length == 0) revert InvalidDependency(dependency);
    }
}
