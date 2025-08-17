// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../interfaces/ILOSTAchievementNFT.sol";

contract LOSTAchievementNFT is
    ILOSTAchievementNFT,
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant GAME_CONTROLLER_ROLE = keccak256("GAME_CONTROLLER_ROLE");

    uint256 private _tokenIdCounter;

    // AchievementType enum and Achievement struct are defined in ILOSTAchievementNFT interface

    mapping(uint256 => Achievement) public achievements;
    mapping(bytes32 => bool) public verifiedGameplayHashes;
    mapping(address => mapping(AchievementType => uint256[])) public playerAchievements;
    mapping(AchievementType => uint256) public worldRecordTokenId;
    mapping(AchievementType => uint256) public worldRecordTime;
    mapping(address => uint256) public playerSkillTier;
    mapping(AchievementType => uint256) public achievementThreshold;
    mapping(uint256 => uint256) public tokenRarityScore;

    event AchievementMinted(
        uint256 indexed tokenId,
        address indexed player,
        AchievementType indexed achievementType,
        uint256 completionTime,
        bytes32 gameplayHash
    );

    event WorldRecordSet(
        uint256 indexed tokenId,
        address indexed player,
        AchievementType indexed achievementType,
        uint256 newRecordTime
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, string memory baseURI) public initializer {
        __ERC721_init("LOST Achievement NFT", "LOST-NFT");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        
        _initializeAchievementThresholds();
    }

    function _initializeAchievementThresholds() private {
        achievementThreshold[AchievementType.PUZZLE_MASTER] = 10;
        achievementThreshold[AchievementType.SPEED_DEMON] = 120;
        achievementThreshold[AchievementType.FIRST_BLOOD] = 1;
        achievementThreshold[AchievementType.COLLECTOR] = 5;
        achievementThreshold[AchievementType.STRATEGIST] = 80;
        achievementThreshold[AchievementType.WORLD_FIRST] = 1;
        achievementThreshold[AchievementType.FLAWLESS_VICTORY] = 0;
    }

    function mintAchievement(
        address player,
        AchievementType achievementType,
        uint256 level,
        uint256 completionTime,
        uint256 attempts,
        bytes32 gameplayHash,
        string memory ipfsMetadata
    ) external onlyRole(MINTER_ROLE) nonReentrant whenNotPaused returns (uint256) {
        require(player != address(0), "Invalid player");
        require(gameplayHash != bytes32(0), "Invalid gameplay hash");
        require(bytes(ipfsMetadata).length > 0, "Invalid IPFS metadata");
        
        // Auto-verify the gameplay hash if sent by authorized minter
        if (!verifiedGameplayHashes[gameplayHash]) {
            verifiedGameplayHashes[gameplayHash] = true;
        }

        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;

        _safeMint(player, tokenId);
        _setTokenURI(tokenId, ipfsMetadata);

        // Create achievement data
        Achievement memory achievement = Achievement({
            tokenId: tokenId,
            achievementType: achievementType,
            level: level,
            completionTime: completionTime,
            attempts: attempts,
            playerScore: 0,
            playerLevel: level,
            deaths: attempts,
            secretsFound: 0,
            puzzlesSolved: 0,
            isWorldFirst: false,
            gameplayHash: gameplayHash,
            ipfsMetadata: ipfsMetadata,
            mintTimestamp: block.timestamp,
            isTransferable: false
        });
        
        achievements[tokenId] = achievement;
        playerAchievements[player][achievementType].push(tokenId);

        if (_checkWorldRecord(achievementType, completionTime)) {
            worldRecordTokenId[achievementType] = tokenId;
            worldRecordTime[achievementType] = completionTime;
            achievement.isWorldFirst = true;
            achievements[tokenId].isWorldFirst = true;
            emit WorldRecordSet(tokenId, player, achievementType, completionTime);
        }

        uint256 rarity = _calculateRarity(achievement);
        tokenRarityScore[tokenId] = rarity;

        emit AchievementMinted(tokenId, player, achievementType, completionTime, gameplayHash);

        return tokenId;
    }

    function verifyGameplayHash(bytes32 gameplayHash) external onlyRole(GAME_CONTROLLER_ROLE) {
        verifiedGameplayHashes[gameplayHash] = true;
    }

    function _checkWorldRecord(AchievementType achievementType, uint256 completionTime) private view returns (bool) {
        return worldRecordTime[achievementType] == 0 || completionTime < worldRecordTime[achievementType];
    }

    function _calculateRarity(Achievement memory achievement) private pure returns (uint256) {
        uint256 rarity = 0;
        
        // Speed bonus
        if (achievement.completionTime < 60) rarity += 1000;
        else if (achievement.completionTime < 120) rarity += 500;
        else if (achievement.completionTime < 180) rarity += 250;
        
        // Perfect run bonus
        if (achievement.deaths == 0) rarity += 750;
        
        // Exploration bonus
        if (achievement.secretsFound >= 10) rarity += 500;
        
        // Puzzle mastery bonus
        if (achievement.puzzlesSolved >= 15) rarity += 500;
        
        // World first bonus
        if (achievement.isWorldFirst) rarity += 2000;
        
        return rarity;
    }

    function getPlayerAchievements(address player, AchievementType achievementType) 
        external view returns (uint256[] memory) {
        return playerAchievements[player][achievementType];
    }

    function getAchievementDetails(uint256 tokenId) external view returns (Achievement memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return achievements[tokenId];
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) whenNotPaused returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    
    
    /**
     * @dev Get achievement details
     */
    function getAchievement(uint256 tokenId) external view returns (Achievement memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return achievements[tokenId];
    }
    
    /**
     * @dev Get all achievements for a player
     */
    function getPlayerAchievements(address player) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(player);
        uint256[] memory tokenIds = new uint256[](balance);
        
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(player, i);
        }
        
        return tokenIds;
    }
    
    /**
     * @dev Set whether an achievement NFT can be transferred
     */
    function setTransferable(uint256 tokenId, bool transferable) external {
        require(ownerOf(tokenId) == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not authorized");
        achievements[tokenId].isTransferable = transferable;
        emit TransferabilityUpdated(tokenId, transferable);
    }
    
    /**
     * @dev Update metadata for an achievement
     */
    function updateMetadata(uint256 tokenId, string memory newIpfsHash) external onlyRole(MINTER_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        achievements[tokenId].ipfsMetadata = newIpfsHash;
        _setTokenURI(tokenId, newIpfsHash);
        emit MetadataUpdated(tokenId, newIpfsHash);
    }
    
    // Override transfer to check transferability
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual {
        if (from != address(0) && to != address(0)) {
            require(achievements[tokenId].isTransferable, "Achievement is not transferable");
        }
    }
    
    // Additional events for interface compliance
    event TransferabilityUpdated(uint256 indexed tokenId, bool transferable);
    event MetadataUpdated(uint256 indexed tokenId, string newIpfsHash);
}