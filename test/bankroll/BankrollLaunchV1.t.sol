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
        assertEq(launcher.launchHashOf(result.token), result.launchHash);
        assertGt(result.tokenLiquidityAmount, 0);
        assertGt(result.initialBuyTokenAmount, 0);
        assertGt(IERC20(result.token).balanceOf(address(this)), 0);
        assertGt(result.hook.programmableLiability(), 0);
    }
}
