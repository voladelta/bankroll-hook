// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

enum GameState {
    Uninitialized,
    Funding,
    Active,
    Closed,
    RandomnessRequested,
    Seeded,
    Expired,
    Finalized,
    Cancelled
}

enum TicketStatus {
    None,
    Open,
    Won,
    Lost,
    Claimed
}

struct BankrollConfig {
    uint128 minimumWager;
    uint128 maximumWager;
    uint128 minimumBankrollAssets;
    uint64 fundingBlocks;
    uint64 activeBlocks;
    uint64 requestGraceBlocks;
    uint64 fulfillmentTimeoutBlocks;
    uint16 maximumSettlementBatch;
}

struct PendingWager {
    address player;
    uint128 stake;
    uint128 exposure;
    uint64 stagedBlock;
    bool exists;
}

struct Ticket {
    address player;
    uint128 stake;
    uint128 grossPayout;
    TicketStatus status;
}
