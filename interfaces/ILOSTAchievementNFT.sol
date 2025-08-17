// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ILOSTAchievementNFT is IERC721 {
    enum AchievementType { 
        PUZZLE_MASTER, 
        SPEED_DEMON, 
        FIRST_BLOOD,
        COLLECTOR,
        STRATEGIST,
        WORLD_FIRST,
        FLAWLESS_VICTORY
    }
    
    struct Achievement {
        uint256 tokenId;
        AchievementType achievementType;
        uint256 level;
        uint256 completionTime;
        uint256 attempts;
        bytes32 gameplayHash;
        string ipfsMetadata;
        uint256 mintTimestamp;
        bool isTransferable;
    }
    
    function mintAchievement(
        address player,
        AchievementType achievementType,
        uint256 level,
        uint256 completionTime,
        uint256 attempts,
        bytes32 gameplayHash,
        string memory ipfsMetadata
    ) external returns (uint256);
    
    function getAchievement(uint256 tokenId) external view returns (Achievement memory);
    function getPlayerAchievements(address player) external view returns (uint256[] memory);
    function setTransferable(uint256 tokenId, bool transferable) external;
    function updateMetadata(uint256 tokenId, string memory newIpfsHash) external;
}