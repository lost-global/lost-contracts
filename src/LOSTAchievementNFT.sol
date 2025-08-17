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
contract LOSTAchievementNFT is
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

    struct Achievement {
        AchievementType achievementType;
        uint256 timestamp;
        uint256 completionTime;
        uint256 score;
        uint256 puzzlesSolved;
        uint256 secretsFound;
        uint256 deaths;
        bytes32 gameplayHash;
        string ipfsHash;
        bool isWorldFirst;
        uint256 globalRank;
    }

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
        achievementThreshold[AchievementType.SPEEDRUN] = 120;
        achievementThreshold[AchievementType.FIRST_CLEAR] = 1;
        achievementThreshold[AchievementType.SKILL_TIER] = 80;
        achievementThreshold[AchievementType.PUZZLE_MASTER] = 10;
        achievementThreshold[AchievementType.PERFECT_RUN] = 0;
        achievementThreshold[AchievementType.SECRET_FINDER] = 5;
        achievementThreshold[AchievementType.TOURNAMENT_WINNER] = 1;
        achievementThreshold[AchievementType.ELITE_ESCAPER] = 90;
    }

    function mintAchievement(
        address player,
        AchievementType achievementType,
        Achievement memory gameplayData,
        string memory ipfsHash
    ) external onlyRole(MINTER_ROLE) nonReentrant whenNotPaused returns (uint256) {
        require(player != address(0), "Invalid player");
        // Auto-verify the gameplay hash if sent by authorized minter
        if (!verifiedGameplayHashes[gameplayData.gameplayHash]) {
            verifiedGameplayHashes[gameplayData.gameplayHash] = true;
        }
        require(bytes(ipfsHash).length > 0, "Invalid IPFS hash");

        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;

        _safeMint(player, tokenId);
        _setTokenURI(tokenId, ipfsHash);

        gameplayData.ipfsHash = ipfsHash;
        gameplayData.timestamp = block.timestamp;
        achievements[tokenId] = gameplayData;

        playerAchievements[player][achievementType].push(tokenId);

        if (_checkWorldRecord(achievementType, gameplayData.completionTime)) {
            worldRecordTokenId[achievementType] = tokenId;
            worldRecordTime[achievementType] = gameplayData.completionTime;
            emit WorldRecordSet(tokenId, player, achievementType, gameplayData.completionTime);
        }

        uint256 rarity = _calculateRarity(gameplayData);
        tokenRarityScore[tokenId] = rarity;

        emit AchievementMinted(tokenId, player, achievementType, gameplayData.completionTime, gameplayData.gameplayHash);

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
        
        if (achievement.completionTime < 60) rarity += 1000;
        else if (achievement.completionTime < 120) rarity += 500;
        else if (achievement.completionTime < 180) rarity += 250;
        
        if (achievement.deaths == 0) rarity += 750;
        if (achievement.secretsFound >= 10) rarity += 500;
        if (achievement.puzzlesSolved >= 15) rarity += 500;
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
}