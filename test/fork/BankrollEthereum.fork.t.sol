// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import { BankrollHook } from "../../src/bankroll/BankrollHook.sol";
import { BankrollHookFactory, BankrollRouterFactory } from "../../src/bankroll/BankrollHookFactory.sol";
import { BankrollLaunchV1, IUERC20Factory, UERC20Metadata } from "../../src/bankroll/BankrollLaunchV1.sol";
import { IWETH } from "../../src/bankroll/BankrollRouter.sol";
import { IRandomnessAdapter } from "../../src/bankroll/interfaces/IRandomnessAdapter.sol";
import { ChainlinkVrfV25Adapter } from "../../src/bankroll/randomness/ChainlinkVrfV25Adapter.sol";
import { BankrollConfig, GameState } from "../../src/bankroll/types/BankrollTypes.sol";

interface IVRFWrapperView {
    function typeAndVersion() external view returns (string memory);

    function calculateRequestPriceNative(uint32 callbackGasLimit, uint32 numberOfWords) external view returns (uint256);
}

contract BankrollEthereumForkTest is Test {
    uint256 internal constant PINNED_BLOCK = 25_690_000;
    bytes32 internal constant PINNED_PARENT_BLOCK_HASH =
        0xac456a672fed18164f423bb4efee5519ec87f1dc34ff37a6fe2cf9b4bcda79be;

    address internal constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address internal constant UERC20_FACTORY = 0x000000e200088D55C39a11F609E5F667729ad49b;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant VRF_WRAPPER = 0x02aae1A04f9828517b3007f83f6181900CaD910c;

    bytes32 internal constant POOL_MANAGER_RUNTIME_HASH =
        0x785f1014552b7ce7d5fb7d0c970ca60edee94fd00425d7ca21609acac7ce1293;
    bytes32 internal constant POSITION_MANAGER_RUNTIME_HASH =
        0x77e36c08b19959a30dde46dec9abe6208e371ff2f56884a56fe1e1a53615528b;
    bytes32 internal constant UERC20_FACTORY_RUNTIME_HASH =
        0x9f042af1533641f048ced56b55898d9e87b2ccb0ec6854292e2cd8ea733e6aeb;
    bytes32 internal constant WETH_RUNTIME_HASH = 0xd0a06b12ac47863b5c7be4185c2deaad1c61557033f56c7d4ea74429cbb25e23;
    bytes32 internal constant VRF_WRAPPER_RUNTIME_HASH =
        0x79dd04a1a325740433d8ffbbc0a9217c5d88992d6f58c58daad0982d41f639bc;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), PINNED_BLOCK);
        assertEq(block.chainid, 1);
        assertEq(block.number, PINNED_BLOCK);
        assertEq(blockhash(PINNED_BLOCK - 1), PINNED_PARENT_BLOCK_HASH);
    }

    function testPinnedDependencyRuntimeAndInterfaces() public {
        assertEq(POOL_MANAGER.code.length, 24_009);
        assertEq(POOL_MANAGER.codehash, POOL_MANAGER_RUNTIME_HASH);
        assertEq(POSITION_MANAGER.code.length, 23_877);
        assertEq(POSITION_MANAGER.codehash, POSITION_MANAGER_RUNTIME_HASH);
        assertEq(UERC20_FACTORY.code.length, 13_380);
        assertEq(UERC20_FACTORY.codehash, UERC20_FACTORY_RUNTIME_HASH);
        assertEq(WETH.code.length, 3124);
        assertEq(WETH.codehash, WETH_RUNTIME_HASH);
        assertEq(VRF_WRAPPER.code.length, 14_693);
        assertEq(VRF_WRAPPER.codehash, VRF_WRAPPER_RUNTIME_HASH);

        assertEq(address(IPositionManager(POSITION_MANAGER).poolManager()), POOL_MANAGER);
        assertEq(IVRFWrapperView(VRF_WRAPPER).typeAndVersion(), "VRFV2PlusWrapper 1.0.0");
        // The official wrapper is callable at the pinned block. Its quoted native
        // price is zero in that historical state, so liveness is proven by the
        // successful typed call rather than by inventing a non-zero invariant.
        assertEq(IVRFWrapperView(VRF_WRAPPER).calculateRequestPriceNative(200_000, 1), 0);

        vm.deal(address(this), 1 ether);
        uint256 wethBalanceBefore = IERC20(WETH).balanceOf(address(this));
        IWETH(WETH).deposit{ value: 0.1 ether }();
        assertEq(IERC20(WETH).balanceOf(address(this)), wethBalanceBefore + 0.1 ether);
    }

    function testPinnedMainnetLaunchLifecycle() public {
        ChainlinkVrfV25Adapter adapter = new ChainlinkVrfV25Adapter(VRF_WRAPPER, 200_000, 3);
        BankrollRouterFactory routerFactory = new BankrollRouterFactory();
        BankrollHookFactory hookFactory = new BankrollHookFactory(routerFactory);
        BankrollLaunchV1 launcher = new BankrollLaunchV1(
            IPoolManager(POOL_MANAGER),
            IPositionManager(POSITION_MANAGER),
            IUERC20Factory(UERC20_FACTORY),
            hookFactory,
            IWETH(WETH),
            IRandomnessAdapter(address(adapter))
        );
        BankrollConfig memory config = BankrollConfig({
            minimumWager: 0.01 ether,
            maximumWager: 10 ether,
            minimumBankrollAssets: 10 ether,
            fundingBlocks: 10,
            activeBlocks: 20,
            requestGraceBlocks: 10,
            fulfillmentTimeoutBlocks: 20,
            maximumSettlementBatch: 16
        });

        string memory name = "Bankroll Fork Evidence 25690000";
        string memory symbol = "BFORK";
        bytes32 creatorSalt = keccak256("bankroll-mainnet-fork-25690000");
        (address predictedToken,) = launcher.predictTokenAddress(name, symbol, address(this), creatorSalt);
        bytes memory constructorArgs = abi.encode(
            IPoolManager(POOL_MANAGER),
            address(launcher),
            predictedToken,
            IERC20(WETH),
            IRandomnessAdapter(address(adapter)),
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
            metadata: UERC20Metadata({
                description: "Pinned Ethereum fork evidence",
                website: "",
                image: "",
                extraData: abi.encode(PINNED_BLOCK, PINNED_PARENT_BLOCK_HASH)
            }),
            game: config
        });

        BankrollLaunchV1.LaunchResult memory result = launcher.launch(parameters);

        assertEq(result.token, predictedToken);
        assertGt(result.token.code.length, 0);
        assertEq(IERC20(result.token).totalSupply(), launcher.TOKEN_SUPPLY());
        assertEq(IERC721(POSITION_MANAGER).ownerOf(result.positionTokenId), address(result.positionLocker));
        assertEq(uint256(result.hook.state()), uint256(GameState.Funding));
        assertEq(result.hook.registrar(), address(launcher));
        assertEq(result.hook.launchedToken(), result.token);
        assertEq(launcher.launchHashOf(result.token), result.launchHash);
    }
}
