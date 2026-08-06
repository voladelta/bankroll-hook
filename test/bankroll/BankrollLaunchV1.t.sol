// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PosmTestSetup } from "@uniswap/v4-periphery/test/shared/PosmTestSetup.sol";
import { PositionManager } from "@uniswap/v4-periphery/src/PositionManager.sol";
import { PositionDescriptor } from "@uniswap/v4-periphery/src/PositionDescriptor.sol";

import { BankrollLaunchV1, IUERC20Factory, UERC20Metadata } from "../../src/bankroll/BankrollLaunchV1.sol";
import { BankrollHook } from "../../src/bankroll/BankrollHook.sol";
import { BankrollHookFactory, BankrollRouterFactory } from "../../src/bankroll/BankrollHookFactory.sol";
import { IWETH } from "../../src/bankroll/BankrollRouter.sol";
import { PermanentPositionLocker } from "../../src/bankroll/PermanentPositionLocker.sol";
import { IRandomnessAdapter } from "../../src/bankroll/interfaces/IRandomnessAdapter.sol";
import { BankrollConfig, GameState } from "../../src/bankroll/types/BankrollTypes.sol";
import { MockFixedToken, MockUERC20Factory } from "./helpers/MockAssets.sol";
import { MockRandomnessAdapter } from "./helpers/MockRandomnessAdapter.sol";

contract MismatchedHookFactory {
    function approvedHookCreationCodeHash() external pure returns (bytes32) {
        return bytes32(0);
    }
}

contract HostileUERC20Factory is IUERC20Factory {
    enum Mode {
        WrongReturn,
        NoToken,
        RevertCreation
    }

    address public predicted;
    address public returned;
    Mode public mode;
    uint256 public createCalls;

    function configure(address predicted_, address returned_, Mode mode_) external {
        predicted = predicted_;
        returned = returned_;
        mode = mode_;
    }

    function getUERC20Address(string calldata, string calldata, uint8, address, bytes32)
        external
        view
        returns (address)
    {
        return predicted;
    }

    function createToken(string calldata, string calldata, uint8, uint256, address, bytes calldata, bytes32)
        external
        returns (address)
    {
        ++createCalls;
        if (mode == Mode.RevertCreation) revert("HOSTILE_FACTORY");
        return mode == Mode.WrongReturn ? returned : predicted;
    }
}

contract BankrollLaunchV1Test is PosmTestSetup {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    BankrollLaunchV1 internal launcher;
    BankrollHookFactory internal hookFactory;
    BankrollRouterFactory internal routerFactory;
    MockUERC20Factory internal tokenFactory;
    MockRandomnessAdapter internal randomness;
    BankrollConfig internal config;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployPosm(manager);
        tokenFactory = new MockUERC20Factory();
        randomness = new MockRandomnessAdapter(0.01 ether);
        routerFactory = new BankrollRouterFactory();
        hookFactory = new BankrollHookFactory(routerFactory);
        launcher = new BankrollLaunchV1(
            manager,
            lpm,
            IUERC20Factory(address(tokenFactory)),
            hookFactory,
            IWETH(address(_WETH9)),
            IRandomnessAdapter(address(randomness))
        );
        config = BankrollConfig({
            minimumWager: 0.01 ether,
            maximumWager: 10 ether,
            minimumBankrollAssets: 10 ether,
            fundingBlocks: 10,
            activeBlocks: 20,
            requestGraceBlocks: 10,
            fulfillmentTimeoutBlocks: 20,
            maximumSettlementBatch: 16
        });
        vm.deal(address(this), 100 ether);
    }

    function testLaunchBindsFixedTokenHookRouterPoolAndPermanentPosition() public {
        string memory name = "Bankroll Launch Token";
        string memory symbol = "BANK";
        bytes32 creatorSalt = keccak256("creator salt");
        (address predictedToken,) = launcher.predictTokenAddress(name, symbol, address(this), creatorSalt);
        bytes memory constructorArgs = abi.encode(
            manager,
            address(launcher),
            predictedToken,
            IERC20(address(_WETH9)),
            IRandomnessAdapter(address(randomness)),
            config
        );
        bytes memory initCode = abi.encodePacked(type(BankrollHook).creationCode, constructorArgs);
        (, bytes32 hookSalt) = HookMiner.find(
            address(hookFactory), hookFactory.REQUIRED_HOOK_FLAGS(), type(BankrollHook).creationCode, constructorArgs
        );
        BankrollLaunchV1.LaunchParameters memory parameters = BankrollLaunchV1.LaunchParameters({
            name: name,
            symbol: symbol,
            creatorSalt: creatorSalt,
            hookSalt: hookSalt,
            hookInitCode: initCode,
            minimumInitialBuyTokenAmount: 0,
            metadata: UERC20Metadata({ description: "A fixed test token", website: "", image: "", extraData: "" }),
            game: config
        });

        BankrollLaunchV1.LaunchResult memory result = launcher.launch{ value: 1 ether }(parameters);

        assertEq(result.token, predictedToken);
        assertEq(MockFixedToken(result.token).totalSupply(), launcher.TOKEN_SUPPLY());
        assertEq(IERC20(result.token).balanceOf(address(launcher)), 0);
        assertEq(IERC20(result.token).balanceOf(address(lpm)), 0);
        assertEq(IERC721(address(lpm)).ownerOf(result.positionTokenId), address(result.positionLocker));
        assertEq(result.positionLocker.feeRecipient(), address(this));
        assertEq(address(result.positionLocker.positionManager()), address(lpm));
        assertEq(uint256(result.hook.state()), uint256(GameState.Funding));
        assertEq(result.hook.registrar(), address(launcher));
        assertEq(result.hook.launchedToken(), result.token);
        assertEq(result.hook.canonicalPoolId(), result.poolId);
        assertEq(result.hookCreationCodeHash, launcher.approvedHookCreationCodeHash());
        assertEq(result.hookRuntimeCodeHash, bytes32(uint256(keccak256(address(result.hook).code))));
        assertEq(result.routerCreationCodeHash, launcher.approvedRouterCreationCodeHash());
        assertEq(result.routerRuntimeCodeHash, bytes32(uint256(keccak256(address(result.router).code))));
        assertEq(launcher.launchHashOf(result.token), result.launchHash);
        assertGt(result.tokenLiquidityAmount, 0);
        assertGt(result.initialBuyTokenAmount, 0);
        assertGt(IERC20(result.token).balanceOf(address(this)), 0);
        assertGt(result.hook.programmableLiability(), 0);
    }

    function testLauncherRejectsFactoryWithUnreviewedHashes() public {
        MismatchedHookFactory mismatchedFactory = new MismatchedHookFactory();
        vm.expectRevert(
            abi.encodeWithSelector(
                BankrollLaunchV1.InvalidLaunchBytecodeHash.selector,
                bytes32(0),
                launcher.REVIEWED_HOOK_CREATION_CODE_HASH()
            )
        );
        new BankrollLaunchV1(
            manager,
            lpm,
            IUERC20Factory(address(tokenFactory)),
            BankrollHookFactory(address(mismatchedFactory)),
            IWETH(address(_WETH9)),
            IRandomnessAdapter(address(randomness))
        );
    }

    function testLauncherRejectsModifiedHookInitCode() public {
        string memory name = "Bankroll Launch Token";
        string memory symbol = "BANK";
        bytes32 creatorSalt = keccak256("creator salt mismatch");
        (address predictedToken,) = launcher.predictTokenAddress(name, symbol, address(this), creatorSalt);
        bytes memory constructorArgs = abi.encode(
            manager,
            address(launcher),
            predictedToken,
            IERC20(address(_WETH9)),
            IRandomnessAdapter(address(randomness)),
            config
        );
        bytes memory modifiedConstructorArgs = abi.encode(
            manager,
            address(launcher),
            predictedToken,
            IERC20(address(_WETH9)),
            IRandomnessAdapter(address(randomness)),
            config
        );
        modifiedConstructorArgs[modifiedConstructorArgs.length - 1] =
            bytes1(uint8(modifiedConstructorArgs[modifiedConstructorArgs.length - 1]) ^ 1);
        bytes memory modifiedInitCode = abi.encodePacked(type(BankrollHook).creationCode, modifiedConstructorArgs);
        (, bytes32 hookSalt) = HookMiner.find(
            address(hookFactory), hookFactory.REQUIRED_HOOK_FLAGS(), type(BankrollHook).creationCode, constructorArgs
        );
        BankrollLaunchV1.LaunchParameters memory parameters = BankrollLaunchV1.LaunchParameters({
            name: name,
            symbol: symbol,
            creatorSalt: creatorSalt,
            hookSalt: hookSalt,
            hookInitCode: modifiedInitCode,
            minimumInitialBuyTokenAmount: 0,
            metadata: UERC20Metadata({ description: "A fixed test token", website: "", image: "", extraData: "" }),
            game: config
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                BankrollHookFactory.InvalidHookConstructorArgs.selector,
                keccak256(modifiedConstructorArgs),
                keccak256(constructorArgs)
            )
        );
        launcher.launch(parameters);
    }

    function testLauncherRejectsModifiedHookCreationCode() public {
        string memory name = "Bankroll Launch Token";
        string memory symbol = "BANK";
        bytes32 creatorSalt = keccak256("creator salt creation mismatch");
        (address predictedToken,) = launcher.predictTokenAddress(name, symbol, address(this), creatorSalt);
        bytes memory constructorArgs = abi.encode(
            manager,
            address(launcher),
            predictedToken,
            IERC20(address(_WETH9)),
            IRandomnessAdapter(address(randomness)),
            config
        );
        bytes memory modifiedCreationCode = type(BankrollHook).creationCode;
        modifiedCreationCode[0] = bytes1(uint8(modifiedCreationCode[0]) ^ 1);
        bytes memory modifiedInitCode = abi.encodePacked(modifiedCreationCode, constructorArgs);
        (, bytes32 hookSalt) = HookMiner.find(
            address(hookFactory), hookFactory.REQUIRED_HOOK_FLAGS(), type(BankrollHook).creationCode, constructorArgs
        );
        BankrollLaunchV1.LaunchParameters memory parameters = BankrollLaunchV1.LaunchParameters({
            name: name,
            symbol: symbol,
            creatorSalt: creatorSalt,
            hookSalt: hookSalt,
            hookInitCode: modifiedInitCode,
            minimumInitialBuyTokenAmount: 0,
            metadata: UERC20Metadata({ description: "A fixed test token", website: "", image: "", extraData: "" }),
            game: config
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                BankrollHookFactory.InvalidHookCreationCodeHash.selector,
                keccak256(modifiedCreationCode),
                hookFactory.approvedHookCreationCodeHash()
            )
        );
        launcher.launch(parameters);
    }

    function testZeroAndMinimumInitialBuyLaunches() public {
        BankrollLaunchV1.LaunchParameters memory zeroBuy =
            _launchParameters(launcher, "Zero Buy Token", "ZERO", keccak256("zero buy"));
        BankrollLaunchV1.LaunchResult memory zeroResult = launcher.launch(zeroBuy);
        assertEq(zeroResult.initialBuyNativeAmount, 0);
        assertEq(zeroResult.initialBuyTokenAmount, 0);
        assertEq(zeroResult.hook.programmableLiability(), 0);

        BankrollLaunchV1.LaunchParameters memory minimumBuy =
            _launchParameters(launcher, "Minimum Buy Token", "MIN", keccak256("minimum buy"));
        BankrollLaunchV1.LaunchResult memory minimumResult =
            launcher.launch{ value: launcher.MIN_NONZERO_INITIAL_BUY() }(minimumBuy);
        assertEq(minimumResult.initialBuyNativeAmount, launcher.MIN_NONZERO_INITIAL_BUY());
        assertGt(minimumResult.initialBuyTokenAmount, 0);
    }

    function testInvalidMinedHookRevertsBeforeTokenCreation() public {
        BankrollLaunchV1.LaunchParameters memory parameters =
            _launchParameters(launcher, "Invalid Hook Token", "BAD", keccak256("invalid hook"));
        address predictedToken = _predictedToken(launcher, parameters);
        parameters.hookSalt = bytes32(uint256(parameters.hookSalt) + 1);

        vm.expectPartialRevert(BankrollHookFactory.InvalidHookAddress.selector);
        launcher.launch(parameters);
        assertEq(predictedToken.code.length, 0);
        assertEq(launcher.launchHashOf(predictedToken), bytes32(0));
    }

    function testRepeatedLaunchParametersRejectTokenCollisionWithoutNewPosition() public {
        BankrollLaunchV1.LaunchParameters memory parameters =
            _launchParameters(launcher, "Collision Token", "COLL", keccak256("collision"));
        BankrollLaunchV1.LaunchResult memory result = launcher.launch(parameters);
        uint256 nextTokenId = lpm.nextTokenId();
        bytes32 launchHash = result.launchHash;

        vm.expectRevert(abi.encodeWithSelector(BankrollLaunchV1.TokenAlreadyExists.selector, result.token));
        launcher.launch(parameters);
        assertEq(lpm.nextTokenId(), nextTokenId);
        assertEq(launcher.launchHashOf(result.token), launchHash);
        assertEq(IERC721(address(lpm)).ownerOf(result.positionTokenId), address(result.positionLocker));
    }

    function testLockedPositionFeeCollectionPathKeepsPermanentCustody() public {
        BankrollLaunchV1.LaunchParameters memory parameters =
            _launchParameters(launcher, "Fee Collection Token", "FEES", keccak256("fees"));
        BankrollLaunchV1.LaunchResult memory result = launcher.launch{ value: 1 ether }(parameters);

        result.positionLocker.collectFees(result.positionTokenId);
        assertEq(IERC721(address(lpm)).ownerOf(result.positionTokenId), address(result.positionLocker));
        assertEq(result.positionLocker.feeRecipient(), address(this));
    }

    function testHostileFactoryWrongReturnRevertsEveryLaunchSideEffect() public {
        HostileUERC20Factory hostile = new HostileUERC20Factory();
        BankrollLaunchV1 hostileLauncher = _newLauncher(IUERC20Factory(address(hostile)));
        address predictedToken = makeAddr("hostile predicted token");
        MockFixedToken wrongToken = new MockFixedToken("Wrong", "WRONG", 1 ether, address(this));
        hostile.configure(predictedToken, address(wrongToken), HostileUERC20Factory.Mode.WrongReturn);
        BankrollLaunchV1.LaunchParameters memory parameters =
            _launchParameters(hostileLauncher, "Hostile Token", "HOST", keccak256("hostile wrong return"));

        _assertFailedLaunchIsAtomic(
            hostileLauncher,
            parameters,
            abi.encodeWithSelector(BankrollLaunchV1.TokenAddressMismatch.selector, address(wrongToken), predictedToken)
        );
        assertEq(hostile.createCalls(), 0);
    }

    function testHostileFactoryNoTokenRevertsEveryLaunchSideEffect() public {
        HostileUERC20Factory hostile = new HostileUERC20Factory();
        BankrollLaunchV1 hostileLauncher = _newLauncher(IUERC20Factory(address(hostile)));
        address predictedToken = makeAddr("missing predicted token");
        hostile.configure(predictedToken, address(0), HostileUERC20Factory.Mode.NoToken);
        BankrollLaunchV1.LaunchParameters memory parameters =
            _launchParameters(hostileLauncher, "Missing Token", "MISS", keccak256("hostile no token"));

        _assertFailedLaunchIsAtomic(hostileLauncher, parameters, bytes(""));
        assertEq(hostile.createCalls(), 0);
    }

    function testLargeInitialBuySlippageRevertsEveryLaunchSideEffect() public {
        BankrollLaunchV1.LaunchParameters memory parameters =
            _launchParameters(launcher, "Slippage Token", "SLIP", keccak256("slippage"));
        parameters.minimumInitialBuyTokenAmount = type(uint256).max;
        _assertFailedLaunchIsAtomic(launcher, parameters, bytes(""), 1 ether);
    }

    function _newLauncher(IUERC20Factory factory) private returns (BankrollLaunchV1) {
        return new BankrollLaunchV1(
            manager, lpm, factory, hookFactory, IWETH(address(_WETH9)), IRandomnessAdapter(address(randomness))
        );
    }

    function _launchParameters(BankrollLaunchV1 target, string memory name, string memory symbol, bytes32 creatorSalt)
        private
        view
        returns (BankrollLaunchV1.LaunchParameters memory parameters)
    {
        (address predictedToken,) = target.predictTokenAddress(name, symbol, address(this), creatorSalt);
        bytes memory constructorArgs = abi.encode(
            manager,
            address(target),
            predictedToken,
            IERC20(address(_WETH9)),
            IRandomnessAdapter(address(randomness)),
            config
        );
        (, bytes32 hookSalt) = HookMiner.find(
            address(hookFactory), hookFactory.REQUIRED_HOOK_FLAGS(), type(BankrollHook).creationCode, constructorArgs
        );
        parameters = BankrollLaunchV1.LaunchParameters({
            name: name,
            symbol: symbol,
            creatorSalt: creatorSalt,
            hookSalt: hookSalt,
            hookInitCode: abi.encodePacked(type(BankrollHook).creationCode, constructorArgs),
            minimumInitialBuyTokenAmount: 0,
            metadata: UERC20Metadata({ description: "A fixed test token", website: "", image: "", extraData: "" }),
            game: config
        });
    }

    function _predictedToken(BankrollLaunchV1 target, BankrollLaunchV1.LaunchParameters memory parameters)
        private
        view
        returns (address token)
    {
        (token,) = target.predictTokenAddress(parameters.name, parameters.symbol, address(this), parameters.creatorSalt);
    }

    function _assertFailedLaunchIsAtomic(
        BankrollLaunchV1 target,
        BankrollLaunchV1.LaunchParameters memory parameters,
        bytes memory expectedRevert
    ) private {
        _assertFailedLaunchIsAtomic(target, parameters, expectedRevert, 0);
    }

    function _assertFailedLaunchIsAtomic(
        BankrollLaunchV1 target,
        BankrollLaunchV1.LaunchParameters memory parameters,
        bytes memory expectedRevert,
        uint256 value
    ) private {
        address predictedToken = _predictedToken(target, parameters);
        address predictedHook = hookFactory.predict(parameters.hookSalt, parameters.hookInitCode);
        bytes32 routerSalt = keccak256(abi.encode("BANKROLL_ROUTER_V1", predictedHook));
        address predictedRouter = routerFactory.predict(
            routerSalt, manager, BankrollHook(predictedHook), IERC20(predictedToken), IWETH(address(_WETH9))
        );
        bytes32 lockerSalt = keccak256(abi.encode("BANKROLL_POSITION_V1", predictedToken, address(this)));
        bytes memory lockerCode =
            abi.encodePacked(type(PermanentPositionLocker).creationCode, abi.encode(lpm, address(this)));
        address predictedLocker = Create2.computeAddress(lockerSalt, keccak256(lockerCode), address(target));
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(predictedToken),
            fee: target.LP_FEE_PIPS(),
            tickSpacing: target.TICK_SPACING(),
            hooks: BankrollHook(predictedHook)
        });
        uint256 nextTokenId = lpm.nextTokenId();

        if (expectedRevert.length == 0) vm.expectRevert();
        else vm.expectRevert(expectedRevert);
        target.launch{ value: value }(parameters);

        assertEq(predictedToken.code.length, 0);
        assertEq(predictedHook.code.length, 0);
        assertEq(predictedRouter.code.length, 0);
        assertEq(predictedLocker.code.length, 0);
        assertEq(lpm.nextTokenId(), nextTokenId);
        assertEq(target.launchHashOf(predictedToken), bytes32(0));
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(PoolId.wrap(PoolId.unwrap(key.toId())));
        assertEq(sqrtPriceX96, 0);
    }
}
