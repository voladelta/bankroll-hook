// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Permanently holds one or more v4 positions and forwards collected fees to one immutable recipient.
/// @dev There is deliberately no position-transfer, liquidity-decrease, approval, rescue or administration function.
contract PermanentPositionLocker is IERC721Receiver, ReentrancyGuardTransient {
    IPositionManager public immutable positionManager;
    address public immutable feeRecipient;

    error InvalidDependency(address dependency);
    error InvalidPosition(uint256 tokenId);
    error UnauthorizedNftSender(address sender);

    event PositionFeesCollected(uint256 indexed tokenId, address indexed feeRecipient);

    constructor(IPositionManager positionManager_, address feeRecipient_) {
        if (address(positionManager_) == address(0) || address(positionManager_).code.length == 0) {
            revert InvalidDependency(address(positionManager_));
        }
        if (feeRecipient_ == address(0)) revert InvalidDependency(feeRecipient_);
        positionManager = positionManager_;
        feeRecipient = feeRecipient_;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(positionManager)) revert UnauthorizedNftSender(msg.sender);
        return IERC721Receiver.onERC721Received.selector;
    }

    function collectFees(uint256 tokenId) external nonReentrant {
        if (IERC721(address(positionManager)).ownerOf(tokenId) != address(this)) revert InvalidPosition(tokenId);
        (PoolKey memory key,) = positionManager.getPoolAndPositionInfo(tokenId);
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, 0, 0, 0, bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1, feeRecipient);
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);
        emit PositionFeesCollected(tokenId, feeRecipient);
    }
}
