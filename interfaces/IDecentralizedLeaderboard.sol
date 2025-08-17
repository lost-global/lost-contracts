// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IDecentralizedLeaderboard {
    struct LeaderboardEntry {
        address player;
        uint256 score;
        uint256 level;
        uint256 completionTime;
        uint256 votes;
        bytes32 gameplayHash;
        uint256 timestamp;
    }
    
    function submitScore(
        uint256 level,
        uint256 score,
        uint256 completionTime,
        bytes32 gameplayHash
    ) external;
    
    function voteForEntry(uint256 entryId, uint256 votingPower) external;
    
    function getTopPlayers(uint256 count) external view returns (LeaderboardEntry[] memory);
    function getPlayerRank(address player) external view returns (uint256);
    function getPlayerBestScore(address player) external view returns (uint256);
    function getTotalVotes(uint256 entryId) external view returns (uint256);
    
    function startNewSeason() external;
    function distributePrizes(address[] memory winners, uint256[] memory amounts) external;
}