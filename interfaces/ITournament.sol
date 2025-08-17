// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ITournament {
    enum TournamentState { REGISTRATION, IN_PROGRESS, FINALIZING, COMPLETED, CANCELLED }
    enum TournamentType { SINGLE_ELIMINATION, DOUBLE_ELIMINATION, ROUND_ROBIN, TIME_ATTACK, SURVIVAL }
    
    function createTournament(
        string memory name,
        uint256 entryFee,
        uint256 maxParticipants,
        uint256 startTime,
        TournamentType tournamentType
    ) external returns (uint256);
    
    function joinTournament(uint256 tournamentId) external;
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