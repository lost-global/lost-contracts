// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITournament
 * @dev Interface for tournament functionality
 */
interface ITournament {
    struct TournamentInfo {
        uint256 tournamentId;
        string name;
        uint256 entryFee;
        uint256 prizePool;
        uint256 maxParticipants;
        uint256 currentParticipants;
        uint256 startTime;
        uint256 endTime;
        TournamentState state;
        address[] winners;
        uint256[] prizes;
    }

    struct ParticipantData {
        address player;
        uint256 score;
        uint256 completionTime;
        bytes32 gameplayHash;
        uint256 rank;
        bool eliminated;
    }

    enum TournamentState {
        REGISTRATION,
        IN_PROGRESS,
        FINALIZING,
        COMPLETED,
        CANCELLED
    }

    enum TournamentType {
        SINGLE_ELIMINATION,
        DOUBLE_ELIMINATION,
        ROUND_ROBIN,
        TIME_ATTACK,
        SURVIVAL
    }

    event TournamentCreated(
        uint256 indexed tournamentId,
        string name,
        uint256 entryFee,
        uint256 maxParticipants
    );

    event PlayerRegistered(
        uint256 indexed tournamentId,
        address indexed player,
        uint256 entryNumber
    );

    event TournamentStarted(
        uint256 indexed tournamentId,
        uint256 timestamp
    );

    event MatchCompleted(
        uint256 indexed tournamentId,
        address indexed winner,
        address indexed loser,
        uint256 round
    );

    event TournamentCompleted(
        uint256 indexed tournamentId,
        address[] winners,
        uint256[] prizes
    );

    event PrizeDistributed(
        uint256 indexed tournamentId,
        address indexed winner,
        uint256 prize,
        uint256 rank
    );

    function createTournament(
        string memory name,
        uint256 entryFee,
        uint256 maxParticipants,
        uint256 startTime,
        TournamentType tournamentType
    ) external returns (uint256 tournamentId);

    function registerForTournament(uint256 tournamentId) external payable;

    function submitScore(
        uint256 tournamentId,
        address player,
        uint256 score,
        bytes32 gameplayHash
    ) external;

    function finalizeTournament(uint256 tournamentId) external;

    function claimPrize(uint256 tournamentId) external;

    function cancelTournament(uint256 tournamentId) external;

    function getTournamentInfo(uint256 tournamentId) external view returns (TournamentInfo memory);

    function getParticipantData(
        uint256 tournamentId,
        address player
    ) external view returns (ParticipantData memory);
}