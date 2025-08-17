// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IGameplayVerification {
    function verifyGameplay(
        address player,
        uint256 level,
        uint256 score,
        uint256 completionTime,
        bytes32 gameplayHash
    ) external returns (bool);
    
    function submitGameSession(
        address player,
        bytes32 sessionHash,
        uint256 startTime,
        uint256 endTime,
        bytes calldata signature
    ) external;
    
    function getPlayerStats(address player) external view returns (
        uint256 totalScore,
        uint256 gamesPlayed,
        uint256 achievements,
        uint256 lastPlayTime
    );
}