// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILOSTProtocol
 * @dev Core interface for LOST Protocol contracts
 */
interface ILOSTProtocol {
    // Achievement Types
    enum AchievementType {
        SPEEDRUN,
        FIRST_CLEAR,
        SKILL_TIER,
        PUZZLE_MASTER,
        PERFECT_RUN,
        SECRET_FINDER,
        TOURNAMENT_WINNER,
        ELITE_ESCAPER
    }

    // Game Session State
    enum SessionState {
        NOT_STARTED,
        IN_PROGRESS,
        COMPLETED,
        VERIFIED,
        FAILED
    }

    // Tournament State
    enum TournamentState {
        REGISTRATION,
        IN_PROGRESS,
        FINALIZING,
        COMPLETED,
        CANCELLED
    }

    // Core structures
    struct GameSession {
        address player;
        uint256 startTime;
        uint256 endTime;
        bytes32 sessionHash;
        bytes32 merkleRoot;
        SessionState state;
        uint256 score;
        bool rewarded;
    }

    struct PlayerData {
        address walletAddress;
        bytes32 did; // Decentralized Identifier
        uint256 skillRating;
        uint256 totalEarnings;
        uint256 achievementCount;
        uint256 lastActiveTimestamp;
    }

    struct Achievement {
        AchievementType achievementType;
        uint256 timestamp;
        uint256 completionTime;
        uint256 score;
        bytes32 gameplayHash;
        string ipfsHash;
        bool isWorldFirst;
        uint256 tokenId;
    }

    // Events
    event SessionStarted(bytes32 indexed sessionId, address indexed player);
    event SessionCompleted(bytes32 indexed sessionId, address indexed player, uint256 score);
    event AchievementUnlocked(address indexed player, AchievementType achievementType, uint256 tokenId);
    event RewardDistributed(address indexed player, uint256 amount, string rewardType);
    event DataCommittedToHedera(bytes32 indexed dataHash, uint256 timestamp);
}