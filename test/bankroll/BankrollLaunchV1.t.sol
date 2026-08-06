// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import { PosmTestSetup } from "@uniswap/v4-periphery/test/shared/PosmTestSetup.sol";
import { PositionManager } from "@uniswap/v4-periphery/src/PositionManager.sol";
import { PositionDescriptor } from "@uniswap/v4-periphery/src/PositionDescriptor.sol";

import { BankrollLaunchV1, IUERC20Factory, UERC20Metadata } from "../../src/bankroll/BankrollLaunchV1.sol";
import { BankrollHook } from "../../src/bankroll/BankrollHook.sol";
import { BankrollHookFactory, BankrollRouterFactory } from "../../src/bankroll/BankrollHookFactory.sol";
import { IWETH } from "../../src/bankroll/BankrollRouter.sol";
import { IRandomnessAdapter } from "../../src/bankroll/interfaces/IRandomnessAdapter.sol";
import { BankrollConfig, GameState } from "../../src/bankroll/types/BankrollTypes.sol";
import { MockFixedToken, MockUERC20Factory } from "./helpers/MockAssets.sol";
import { MockRandomnessAdapter } from "./helpers/MockRandomnessAdapter.sol";

contract MismatchedHookFactory {
    function approvedHookCreationCodeHash() external pure returns (bytes32) {
        return bytes32(0);
    }
}

contract BankrollLaunchV1Test is PosmTestSetup {
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
}
