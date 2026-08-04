// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IBankrollHook {
    function stageWager(bytes32 pendingId, address player, uint128 stake) external;
    function pendingWagerExists(bytes32 pendingId) external view returns (bool);
}
