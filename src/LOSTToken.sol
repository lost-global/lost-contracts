// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title LOSTToken
 * @dev LOST Protocol Gaming Token - The currency of skill
 * @notice This token powers the LOST gaming economy where skill equals value
 * Features:
 * - Gameplay-based minting (only earned through achievement)
 * - Dynamic reward distribution based on performance
 * - Burn mechanism for NFT upgrades and tournament entries
 * - Anti-cheat verification before minting
 */
contract LOSTToken is 
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant GAME_CONTROLLER_ROLE = keccak256("GAME_CONTROLLER_ROLE");
    bytes32 public constant TOURNAMENT_ROLE = keccak256("TOURNAMENT_ROLE");

    // Tokenomics configuration
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10**18; // 1 million LOST
    uint256 public constant MAX_SUPPLY = 100_000_000 * 10**18; // 100 million LOST cap
    
    // Reward amounts (in wei)
    uint256 public constant PUZZLE_COMPLETION_REWARD = 100 * 10**18; // 100 LOST
    uint256 public constant SPEEDRUN_ACHIEVEMENT_REWARD = 500 * 10**18; // 500 LOST
    uint256 public constant WORLD_FIRST_REWARD = 1000 * 10**18; // 1000 LOST
    uint256 public constant DAILY_CHALLENGE_REWARD = 50 * 10**18; // 50 LOST
    
    // Anti-inflation mechanisms
    uint256 public totalMinted;
    uint256 public totalBurned;
    
    // Player reward tracking
    mapping(address => uint256) public playerLifetimeEarnings;
    mapping(address => uint256) public playerLastRewardTimestamp;
    mapping(address => uint256) public playerRewardStreak;
    
    // Achievement-based minting caps
    mapping(address => mapping(bytes32 => bool)) public achievementClaimed;
    mapping(bytes32 => uint256) public achievementRewardAmount;
    
    // Tournament prize pools
    mapping(uint256 => uint256) public tournamentPrizePools;
    
    // Skill-based multipliers (basis points, 10000 = 1x)
    mapping(address => uint256) public playerSkillMultiplier;
    
    // Anti-cheat verification
    mapping(bytes32 => bool) public verifiedGameplaySessions;
    
    // Puzzle completion tracking
    mapping(address => uint256) public playerPuzzlesCompleted;
    mapping(address => mapping(bytes32 => bool)) public puzzleCompleted;
    mapping(address => uint256) public playerCurrentLevel;
    
    // Events
    event RewardMinted(
        address indexed player,
        uint256 amount,
        string rewardType,
        bytes32 sessionHash
    );
    
    event AchievementUnlocked(
        address indexed player,
        bytes32 indexed achievementId,
        uint256 reward
    );
    
    event TournamentPrizeDistributed(
        uint256 indexed tournamentId,
        address indexed winner,
        uint256 prize
    );
    
    event SkillMultiplierUpdated(
        address indexed player,
        uint256 oldMultiplier,
        uint256 newMultiplier
    );
    
    event TokensBurned(
        address indexed burner,
        uint256 amount,
        string purpose
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the LOST token contract
     * @param admin The admin address that will have DEFAULT_ADMIN_ROLE
     */
    function initialize(address admin) public initializer {
        __ERC20_init("LOST Token", "LOST");
        __ERC20Burnable_init();
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        
        // Mint initial supply to treasury
        _mint(admin, INITIAL_SUPPLY);
        totalMinted = INITIAL_SUPPLY;
        
        // Initialize default achievement rewards
        _initializeAchievementRewards();
    }

    /**
     * @dev Initialize default achievement reward amounts
     */
    function _initializeAchievementRewards() private {
        achievementRewardAmount[keccak256("FIRST_STEPS")] = 100 * 10**18;
        achievementRewardAmount[keccak256("SPEED_DEMON")] = 500 * 10**18;
        achievementRewardAmount[keccak256("PUZZLE_MASTER")] = 250 * 10**18;
        achievementRewardAmount[keccak256("ELITE_ESCAPER")] = 750 * 10**18;
        achievementRewardAmount[keccak256("WORLD_FIRST")] = 1000 * 10**18;
        achievementRewardAmount[keccak256("PERFECT_RUN")] = 600 * 10**18;
        achievementRewardAmount[keccak256("SECRET_FINDER")] = 300 * 10**18;
    }

    /**
     * @dev Mint rewards for puzzle completion
     * @param player The player address
     * @param sessionHash The verified gameplay session hash
     * @param puzzleId The puzzle identifier
     * @param completionTime The time taken to complete the puzzle
     */
    function mintPuzzleReward(
        address player,
        bytes32 sessionHash,
        bytes32 puzzleId,
        uint256 completionTime
    ) external onlyRole(GAME_CONTROLLER_ROLE) nonReentrant whenNotPaused {
        require(player != address(0), "Invalid player address");
        require(verifiedGameplaySessions[sessionHash], "Unverified gameplay session");
        require(totalMinted + PUZZLE_COMPLETION_REWARD <= MAX_SUPPLY, "Max supply exceeded");
        
        // Track puzzle completion (avoid double rewards for same puzzle)
        if (!puzzleCompleted[player][puzzleId]) {
            puzzleCompleted[player][puzzleId] = true;
            playerPuzzlesCompleted[player]++;
            
            // Update current level based on puzzles completed
            if (playerPuzzlesCompleted[player] >= 4) {
                playerCurrentLevel[player] = 2; // Completed all 4 puzzles, move to level 2
            } else {
                playerCurrentLevel[player] = 1; // Still on level 1
            }
        }
        
        uint256 baseReward = PUZZLE_COMPLETION_REWARD;
        uint256 skillMultiplier = playerSkillMultiplier[player];
        if (skillMultiplier == 0) skillMultiplier = 10000; // Default 1x multiplier
        
        // Apply time bonus for fast completion (max 2x for under 60 seconds)
        uint256 timeBonus = 10000;
        if (completionTime < 60) {
            timeBonus = 20000; // 2x multiplier
        } else if (completionTime < 120) {
            timeBonus = 15000; // 1.5x multiplier
        } else if (completionTime < 180) {
            timeBonus = 12500; // 1.25x multiplier
        }
        
        uint256 finalReward = (baseReward * skillMultiplier * timeBonus) / (10000 * 10000);
        
        _mint(player, finalReward);
        totalMinted += finalReward;
        playerLifetimeEarnings[player] += finalReward;
        playerLastRewardTimestamp[player] = block.timestamp;
        
        emit RewardMinted(player, finalReward, "PUZZLE_COMPLETION", sessionHash);
    }

    /**
     * @dev Mint rewards for achievements
     * @param player The player address
     * @param achievementId The achievement identifier
     * @param sessionHash The verified gameplay session hash
     */
    function mintAchievementReward(
        address player,
        bytes32 achievementId,
        bytes32 sessionHash
    ) external onlyRole(GAME_CONTROLLER_ROLE) nonReentrant whenNotPaused {
        require(player != address(0), "Invalid player address");
        require(verifiedGameplaySessions[sessionHash], "Unverified gameplay session");
        require(!achievementClaimed[player][achievementId], "Achievement already claimed");
        
        uint256 reward = achievementRewardAmount[achievementId];
        require(reward > 0, "Unknown achievement");
        require(totalMinted + reward <= MAX_SUPPLY, "Max supply exceeded");
        
        achievementClaimed[player][achievementId] = true;
        
        _mint(player, reward);
        totalMinted += reward;
        playerLifetimeEarnings[player] += reward;
        playerLastRewardTimestamp[player] = block.timestamp;
        
        emit AchievementUnlocked(player, achievementId, reward);
        emit RewardMinted(player, reward, "ACHIEVEMENT", sessionHash);
    }

    /**
     * @dev Mint daily challenge rewards
     * @param player The player address
     * @param challengeId The daily challenge identifier
     */
    function mintDailyChallengeReward(
        address player,
        bytes32 challengeId
    ) external onlyRole(GAME_CONTROLLER_ROLE) nonReentrant whenNotPaused {
        require(player != address(0), "Invalid player address");
        require(!achievementClaimed[player][challengeId], "Challenge already claimed today");
        require(totalMinted + DAILY_CHALLENGE_REWARD <= MAX_SUPPLY, "Max supply exceeded");
        
        // Check if player maintained streak
        uint256 lastReward = playerLastRewardTimestamp[player];
        if (lastReward > 0 && block.timestamp - lastReward <= 1 days + 1 hours) {
            playerRewardStreak[player]++;
        } else {
            playerRewardStreak[player] = 1;
        }
        
        // Apply streak bonus (up to 2x at 7 day streak)
        uint256 streakMultiplier = 10000 + (playerRewardStreak[player] * 1428); // ~14.28% per day
        if (streakMultiplier > 20000) streakMultiplier = 20000; // Cap at 2x
        
        uint256 finalReward = (DAILY_CHALLENGE_REWARD * streakMultiplier) / 10000;
        
        achievementClaimed[player][challengeId] = true;
        
        _mint(player, finalReward);
        totalMinted += finalReward;
        playerLifetimeEarnings[player] += finalReward;
        playerLastRewardTimestamp[player] = block.timestamp;
        
        emit RewardMinted(player, finalReward, "DAILY_CHALLENGE", challengeId);
    }

    /**
     * @dev Distribute tournament prizes
     * @param tournamentId The tournament identifier
     * @param winners Array of winner addresses
     * @param prizes Array of prize amounts
     */
    function distributeTournamentPrizes(
        uint256 tournamentId,
        address[] calldata winners,
        uint256[] calldata prizes
    ) external onlyRole(TOURNAMENT_ROLE) nonReentrant whenNotPaused {
        require(winners.length == prizes.length, "Mismatched arrays");
        require(tournamentPrizePools[tournamentId] > 0, "Invalid tournament");
        
        uint256 totalPrizes = 0;
        for (uint256 i = 0; i < prizes.length; i++) {
            totalPrizes += prizes[i];
        }
        require(totalPrizes <= tournamentPrizePools[tournamentId], "Prizes exceed pool");
        
        for (uint256 i = 0; i < winners.length; i++) {
            if (winners[i] != address(0) && prizes[i] > 0) {
                _mint(winners[i], prizes[i]);
                totalMinted += prizes[i];
                playerLifetimeEarnings[winners[i]] += prizes[i];
                
                emit TournamentPrizeDistributed(tournamentId, winners[i], prizes[i]);
            }
        }
        
        tournamentPrizePools[tournamentId] -= totalPrizes;
    }

    /**
     * @dev Burn tokens for NFT upgrades
     * @param amount The amount to burn
     */
    function burnForNFTUpgrade(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        _burn(msg.sender, amount);
        totalBurned += amount;
        emit TokensBurned(msg.sender, amount, "NFT_UPGRADE");
    }

    /**
     * @dev Burn tokens for tournament entry
     * @param tournamentId The tournament to enter
     * @param entryFee The entry fee amount
     */
    function burnForTournamentEntry(
        uint256 tournamentId,
        uint256 entryFee
    ) external nonReentrant whenNotPaused {
        require(entryFee > 0, "Invalid entry fee");
        _burn(msg.sender, entryFee);
        totalBurned += entryFee;
        tournamentPrizePools[tournamentId] += entryFee;
        emit TokensBurned(msg.sender, entryFee, "TOURNAMENT_ENTRY");
    }

    /**
     * @dev Update player skill multiplier based on performance
     * @param player The player address
     * @param newMultiplier The new multiplier (basis points)
     */
    function updatePlayerSkillMultiplier(
        address player,
        uint256 newMultiplier
    ) external onlyRole(GAME_CONTROLLER_ROLE) {
        require(newMultiplier >= 5000 && newMultiplier <= 30000, "Invalid multiplier range");
        
        uint256 oldMultiplier = playerSkillMultiplier[player];
        playerSkillMultiplier[player] = newMultiplier;
        
        emit SkillMultiplierUpdated(player, oldMultiplier, newMultiplier);
    }

    /**
     * @dev Mark a gameplay session as verified
     * @param sessionHash The session hash to verify
     */
    function verifyGameplaySession(
        bytes32 sessionHash
    ) external onlyRole(GAME_CONTROLLER_ROLE) {
        verifiedGameplaySessions[sessionHash] = true;
    }

    /**
     * @dev Set achievement reward amount
     * @param achievementId The achievement identifier
     * @param rewardAmount The reward amount in wei
     */
    function setAchievementReward(
        bytes32 achievementId,
        uint256 rewardAmount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(rewardAmount > 0 && rewardAmount <= 10000 * 10**18, "Invalid reward amount");
        achievementRewardAmount[achievementId] = rewardAmount;
    }

    /**
     * @dev Get player statistics
     * @param player The player address
     */
    function getPlayerStats(address player) external view returns (
        uint256 balance,
        uint256 lifetimeEarnings,
        uint256 lastRewardTimestamp,
        uint256 rewardStreak,
        uint256 skillMultiplier,
        uint256 puzzlesCompleted
    ) {
        return (
            balanceOf(player),
            playerLifetimeEarnings[player],
            playerLastRewardTimestamp[player],
            playerRewardStreak[player],
            playerSkillMultiplier[player] > 0 ? playerSkillMultiplier[player] : 10000,
            playerPuzzlesCompleted[player]
        );
    }
    
    /**
     * @dev Get puzzle completion status for a player
     * @param player The player address
     * @param puzzleId The puzzle identifier
     */
    function isPuzzleCompleted(address player, bytes32 puzzleId) external view returns (bool) {
        return puzzleCompleted[player][puzzleId];
    }
    
    /**
     * @dev Get player progress (current level)
     * @param player The player address
     * @return currentLevel The player's current level
     */
    function getPlayerProgress(address player) external view returns (uint256) {
        uint256 level = playerCurrentLevel[player];
        return level > 0 ? level : 1; // Default to level 1 if not set
    }

    /**
     * @dev Get token economics data
     */
    function getTokenomics() external view returns (
        uint256 currentSupply,
        uint256 maxSupply,
        uint256 minted,
        uint256 burned,
        uint256 circulatingSupply
    ) {
        return (
            totalSupply(),
            MAX_SUPPLY,
            totalMinted,
            totalBurned,
            totalSupply()
        );
    }

    // Admin functions
    
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}

    // Override required functions
    
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override whenNotPaused {
        super._update(from, to, value);
    }
}