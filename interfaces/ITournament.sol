// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ITournament {
    enum TournamentState { REGISTRATION, IN_PROGRESS, FINALIZING, COMPLETED, CANCELLED }
    enum TournamentType { SINGLE_ELIMINATION, DOUBLE_ELIMINATION, ROUND_ROBIN, TIME_ATTACK, SURVIVAL }
    
    struct TournamentInfo {
        string name;
        uint256 entryFee;
        uint256 prizePool;
        uint256 maxParticipants;
        uint256 currentParticipants;
        uint256 startTime;
        uint256 endTime;
        TournamentState state;
        TournamentType tournamentType;
        address organizer;
        address[] winners;
        bytes32 merkleRoot;
        bool emergencyStop;
    }
    
    struct ParticipantData {
        bool isRegistered;
        uint256 score;
        uint256 matchesPlayed;
        uint256 matchesWon;
        uint256 rank;
        bool eliminated;
        uint256 registrationTime;
        bytes32 gameplayHash;
    }
    
    event TournamentCreated(uint256 indexed tournamentId, string name, uint256 entryFee, uint256 maxParticipants);
    event PlayerJoined(uint256 indexed tournamentId, address indexed player);
    event PlayerRegistered(uint256 indexed tournamentId, address indexed player, uint256 participantCount);
    event TournamentStarted(uint256 indexed tournamentId, uint256 startTime);
    event MatchResultSubmitted(uint256 indexed tournamentId, uint256 matchIndex, address winner);
    event TournamentFinalized(uint256 indexed tournamentId, address[] winners, uint256 prizePool);
    event TournamentCompleted(uint256 indexed tournamentId, address[] winners, uint256[] prizes);
    event PrizeDistributed(uint256 indexed tournamentId, address indexed winner, uint256 amount, uint256 rank);
    
    function createTournament(
        string memory name,
        uint256 entryFee,
        uint256 maxParticipants,
        uint256 startTime,
        TournamentType tournamentType
    ) external returns (uint256);
    
    function joinTournament(uint256 tournamentId) external payable;
    function startTournament(uint256 tournamentId) external;
    function submitMatchResult(
        uint256 tournamentId,
        uint256 matchIndex,
        address winner,
        uint256 player1Score,
        uint256 player2Score,
        bytes32 gameplayHash
    ) external;
    function finalizeTournament(
        uint256 tournamentId,
        address[] memory winners,
        bytes32 merkleRoot
    ) external;
    function cancelTournament(uint256 tournamentId) external;
    function getTournament(uint256 tournamentId) external view returns (
        string memory name,
        uint256 entryFee,
        uint256 prizePool,
        uint256 participants,
        TournamentState state,
        address creator
    );
}