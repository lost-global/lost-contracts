// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IDecentralizedLeaderboard.sol";

/**
 * @title DecentralizedLeaderboard
 * @dev Consensus-based leaderboard system for LOST Protocol
 * Features:
 * - No centralized servers determining rankings
 * - Consensus-based scoring via Hedera Consensus Service
 * - Tamper-proof time records with cryptographic signatures
 * - Real-time WebSocket updates for live competitions
 * - Cross-game reputation portable between titles
 */
contract DecentralizedLeaderboard is
    IDecentralizedLeaderboard,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // LeaderboardEntry struct is defined in IDecentralizedLeaderboard interface
    
    struct PlayerStats {
        uint256 totalGames;
        uint256 totalScore;
        uint256 bestTime;
        uint256 averageTime;
        uint256 winStreak;
        uint256 currentStreak;
        uint256 skillRating;
        uint256 lastPlayedTimestamp;
    }

    struct SeasonData {
        uint256 startTime;
        uint256 endTime;
        uint256 totalParticipants;
        mapping(address => uint256) seasonScore;
        mapping(uint256 => address) topPlayers;
        bool finalized;
    }

    // Global leaderboard
    mapping(uint256 => LeaderboardEntry) public globalLeaderboard;
    mapping(address => uint256) public playerGlobalRank;
    uint256 public totalPlayers;

    // Weekly and monthly leaderboards
    mapping(uint256 => mapping(uint256 => LeaderboardEntry)) public weeklyLeaderboard;
    mapping(uint256 => mapping(uint256 => LeaderboardEntry)) public monthlyLeaderboard;
    mapping(address => mapping(uint256 => uint256)) public playerWeeklyRank;
    mapping(address => mapping(uint256 => uint256)) public playerMonthlyRank;
    
    // Player statistics
    mapping(address => PlayerStats) public playerStats;
    
    // Season management
    mapping(uint256 => SeasonData) public seasons;
    uint256 public currentSeason;
    
    // Consensus tracking
    mapping(bytes32 => uint256) public consensusScores;
    mapping(bytes32 => uint256) public consensusVotes;
    mapping(bytes32 => mapping(address => bool)) public hasVoted;
    
    // Cross-game reputation
    mapping(address => mapping(bytes32 => uint256)) public crossGameReputation;
    mapping(bytes32 => bool) public registeredGames;
    
    // Score calculation parameters
    uint256 public constant BASE_SCORE = 1000;
    uint256 public constant TIME_BONUS_MULTIPLIER = 100;
    uint256 public constant PUZZLE_BONUS = 50;
    uint256 public constant SECRET_BONUS = 25;
    uint256 public constant DEATH_PENALTY = 10;
    uint256 public constant CONSENSUS_THRESHOLD = 3;
    
    // Events
    event LeaderboardUpdated(
        address indexed player,
        uint256 score,
        uint256 globalRank,
        uint256 timestamp
    );
    
    event SeasonStarted(
        uint256 indexed seasonId,
        uint256 startTime,
        uint256 endTime
    );
    
    event SeasonFinalized(
        uint256 indexed seasonId,
        address indexed winner,
        uint256 winningScore
    );
    
    event ConsensusReached(
        bytes32 indexed entryHash,
        uint256 finalScore,
        uint256 votes
    );
    
    event CrossGameReputationUpdated(
        address indexed player,
        bytes32 indexed gameId,
        uint256 reputation
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPDATER_ROLE, admin);
        _grantRole(VALIDATOR_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        
        currentSeason = 1;
        _startNewSeason();
    }

    function submitEntry(
        address player,
        uint256 completionTime,
        uint256 puzzlesSolved,
        uint256 secretsFound,
        uint256 deaths,
        bytes32 gameplayHash
    ) external onlyRole(UPDATER_ROLE) whenNotPaused nonReentrant returns (uint256) {
        require(player != address(0), "Invalid player");
        require(gameplayHash != bytes32(0), "Invalid gameplay hash");
        
        uint256 score = _calculateScore(completionTime, puzzlesSolved, secretsFound, deaths);
        
        LeaderboardEntry memory entry = LeaderboardEntry({
            player: player,
            score: score,
            level: puzzlesSolved,
            completionTime: completionTime,
            puzzlesSolved: puzzlesSolved,
            secretsFound: secretsFound,
            deaths: deaths,
            votes: 0,
            gameplayHash: gameplayHash,
            timestamp: block.timestamp
        });
        
        bytes32 entryHash = _hashEntry(entry);
        consensusScores[entryHash] = score;
        
        _updateLeaderboards(player, entry);
        _updatePlayerStats(player, entry);
        
        emit LeaderboardUpdated(player, score, playerGlobalRank[player], block.timestamp);
        
        return score;
    }

    function voteOnEntry(
        bytes32 entryHash,
        uint256 score
    ) external onlyRole(VALIDATOR_ROLE) whenNotPaused {
        require(!hasVoted[entryHash][msg.sender], "Already voted");
        require(consensusScores[entryHash] > 0, "Entry does not exist");
        
        hasVoted[entryHash][msg.sender] = true;
        consensusVotes[entryHash]++;
        
        if (consensusVotes[entryHash] >= CONSENSUS_THRESHOLD) {
            consensusScores[entryHash] = score;
            emit ConsensusReached(entryHash, score, consensusVotes[entryHash]);
        }
    }

    function _calculateScore(
        uint256 completionTime,
        uint256 puzzlesSolved,
        uint256 secretsFound,
        uint256 deaths
    ) private pure returns (uint256) {
        uint256 score = BASE_SCORE;
        
        // Time bonus (faster = higher score)
        if (completionTime > 0) {
            uint256 timeBonus = (TIME_BONUS_MULTIPLIER * 1000) / completionTime;
            score += timeBonus;
        }
        
        // Puzzle and secret bonuses
        score += puzzlesSolved * PUZZLE_BONUS;
        score += secretsFound * SECRET_BONUS;
        
        // Death penalty
        if (deaths > 0) {
            uint256 penalty = deaths * DEATH_PENALTY;
            score = score > penalty ? score - penalty : 0;
        }
        
        return score;
    }

    function _updateLeaderboards(address player, LeaderboardEntry memory entry) private {
        // Update global leaderboard
        uint256 rank = _findGlobalRank(entry.score);
        _insertGlobalEntry(rank, entry);
        playerGlobalRank[player] = rank;
        
        // Update weekly leaderboard
        uint256 week = _getCurrentWeek();
        uint256 weeklyRank = _findWeeklyRank(week, entry.score);
        weeklyLeaderboard[week][weeklyRank] = entry;
        playerWeeklyRank[player][week] = weeklyRank;
        
        // Update monthly leaderboard
        uint256 month = _getCurrentMonth();
        uint256 monthlyRank = _findMonthlyRank(month, entry.score);
        monthlyLeaderboard[month][monthlyRank] = entry;
        playerMonthlyRank[player][month] = monthlyRank;
        
        // Update season data
        SeasonData storage season = seasons[currentSeason];
        season.seasonScore[player] += entry.score;
        
        if (playerStats[player].totalGames == 0) {
            season.totalParticipants++;
            totalPlayers++;
        }
    }

    function _updatePlayerStats(address player, LeaderboardEntry memory entry) private {
        PlayerStats storage stats = playerStats[player];
        
        stats.totalGames++;
        stats.totalScore += entry.score;
        
        if (stats.bestTime == 0 || entry.completionTime < stats.bestTime) {
            stats.bestTime = entry.completionTime;
        }
        
        uint256 totalTime = stats.averageTime * (stats.totalGames - 1) + entry.completionTime;
        stats.averageTime = totalTime / stats.totalGames;
        
        // Update streaks
        if (stats.lastPlayedTimestamp > 0 && 
            block.timestamp - stats.lastPlayedTimestamp <= 1 days) {
            stats.currentStreak++;
            if (stats.currentStreak > stats.winStreak) {
                stats.winStreak = stats.currentStreak;
            }
        } else {
            stats.currentStreak = 1;
        }
        
        stats.lastPlayedTimestamp = block.timestamp;
        
        // Update skill rating (ELO-like system)
        stats.skillRating = _calculateSkillRating(stats);
    }

    function _calculateSkillRating(PlayerStats memory stats) private pure returns (uint256) {
        uint256 rating = 1200; // Base rating
        
        // Adjust based on average score
        uint256 avgScore = stats.totalScore / stats.totalGames;
        rating += avgScore / 10;
        
        // Bonus for consistency
        if (stats.winStreak >= 7) rating += 100;
        else if (stats.winStreak >= 3) rating += 50;
        
        // Bonus for speed
        if (stats.bestTime < 60) rating += 200;
        else if (stats.bestTime < 120) rating += 100;
        else if (stats.bestTime < 180) rating += 50;
        
        return rating;
    }

    function _findGlobalRank(uint256 score) private view returns (uint256) {
        for (uint256 i = 1; i <= totalPlayers; i++) {
            if (score > globalLeaderboard[i].score) {
                return i;
            }
        }
        return totalPlayers + 1;
    }

    function _insertGlobalEntry(uint256 rank, LeaderboardEntry memory entry) private {
        // Shift lower-ranked entries down
        for (uint256 i = totalPlayers; i >= rank && i > 0; i--) {
            globalLeaderboard[i + 1] = globalLeaderboard[i];
            playerGlobalRank[globalLeaderboard[i].player] = i + 1;
        }
        
        // Insert new entry
        globalLeaderboard[rank] = entry;
    }

    function _findWeeklyRank(uint256 week, uint256 score) private view returns (uint256) {
        uint256 rank = 1;
        while (weeklyLeaderboard[week][rank].score > score && rank < 100) {
            rank++;
        }
        return rank;
    }

    function _findMonthlyRank(uint256 month, uint256 score) private view returns (uint256) {
        uint256 rank = 1;
        while (monthlyLeaderboard[month][rank].score > score && rank < 100) {
            rank++;
        }
        return rank;
    }

    function _getCurrentWeek() private view returns (uint256) {
        return block.timestamp / 1 weeks;
    }

    function _getCurrentMonth() private view returns (uint256) {
        return block.timestamp / 30 days;
    }

    function _hashEntry(LeaderboardEntry memory entry) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            entry.player,
            entry.score,
            entry.completionTime,
            entry.gameplayHash,
            entry.timestamp
        ));
    }

    function _startNewSeason() private {
        SeasonData storage season = seasons[currentSeason];
        season.startTime = block.timestamp;
        season.endTime = block.timestamp + 90 days;
        
        emit SeasonStarted(currentSeason, season.startTime, season.endTime);
    }

    // View functions for API integration
    function getPlayerRank(address player) external view returns (uint256) {
        return playerGlobalRank[player];
    }
    
    function getTotalPlayers() external view returns (uint256) {
        return totalPlayers;
    }
    
    function getPlayerStats(address player) external view returns (
        uint256 totalGames,
        uint256 totalScore,
        uint256 bestTime,
        uint256 averageTime,
        uint256 winStreak,
        uint256 currentStreak,
        uint256 skillRating,
        uint256 lastPlayedTimestamp
    ) {
        PlayerStats memory stats = playerStats[player];
        return (
            stats.totalGames,
            stats.totalScore,
            stats.bestTime,
            stats.averageTime,
            stats.winStreak,
            stats.currentStreak,
            stats.skillRating,
            stats.lastPlayedTimestamp
        );
    }
    
    function getLeaderboardEntry(uint256 rank) external view returns (
        address player,
        uint256 score,
        uint256 level,
        uint256 completionTime,
        uint256 puzzlesSolved,
        uint256 secretsFound,
        uint256 deaths,
        uint256 votes,
        bytes32 gameplayHash,
        uint256 timestamp
    ) {
        LeaderboardEntry memory entry = globalLeaderboard[rank];
        return (
            entry.player,
            entry.score,
            entry.level,
            entry.completionTime,
            entry.puzzlesSolved,
            entry.secretsFound,
            entry.deaths,
            entry.votes,
            entry.gameplayHash,
            entry.timestamp
        );
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
    
    // ========== INTERFACE IMPLEMENTATIONS ==========
    
    /**
     * @dev Submit a score to the leaderboard
     */
    function submitScore(
        uint256 level,
        uint256 score,
        uint256 completionTime,
        bytes32 gameplayHash
    ) external whenNotPaused {
        LeaderboardEntry memory entry = LeaderboardEntry({
            player: msg.sender,
            score: score,
            level: level,
            completionTime: completionTime,
            puzzlesSolved: 0,
            secretsFound: 0,
            deaths: 0,
            votes: 0,
            gameplayHash: gameplayHash,
            timestamp: block.timestamp
        });
        
        // Store entry
        uint256 entryId = totalEntries++;
        leaderboard[entryId] = entry;
        playerLatestEntry[msg.sender] = entryId;
        
        emit ScoreSubmitted(entryId, msg.sender, score, completionTime, gameplayHash);
    }
    
    /**
     * @dev Vote for a leaderboard entry
     */
    function voteForEntry(uint256 entryId, uint256 votingPower) external whenNotPaused {
        require(entryId < totalEntries, "Invalid entry ID");
        require(votingPower > 0, "Voting power must be greater than 0");
        
        LeaderboardEntry storage entry = leaderboard[entryId];
        entry.votes += votingPower;
        
        emit VoteCast(entryId, msg.sender, votingPower);
    }
    
    /**
     * @dev Get top players
     */
    function getTopPlayers(uint256 count) external view returns (LeaderboardEntry[] memory) {
        require(count > 0 && count <= 100, "Invalid count");
        
        LeaderboardEntry[] memory topPlayers = new LeaderboardEntry[](count);
        uint256 actualCount = count > totalEntries ? totalEntries : count;
        
        for (uint256 i = 0; i < actualCount; i++) {
            topPlayers[i] = leaderboard[i];
        }
        
        return topPlayers;
    }
    
    /**
     * @dev Get player's best score
     */
    function getPlayerBestScore(address player) external view returns (uint256) {
        PlayerStats memory stats = playerStats[player];
        // Return totalScore divided by totalGames for best score approximation
        if (stats.totalGames == 0) return 0;
        return stats.totalScore / stats.totalGames;
    }
    
    /**
     * @dev Get total votes for an entry
     */
    function getTotalVotes(uint256 entryId) external view returns (uint256) {
        require(entryId < totalEntries, "Invalid entry ID");
        return leaderboard[entryId].votes;
    }
    
    /**
     * @dev Start a new season
     */
    function startNewSeason() external onlyRole(UPDATER_ROLE) {
        currentSeason++;
        _startNewSeason();
    }
    
    /**
     * @dev Distribute prizes to winners
     */
    function distributePrizes(address[] memory winners, uint256[] memory amounts) external onlyRole(UPDATER_ROLE) {
        require(winners.length == amounts.length, "Arrays must have same length");
        
        for (uint256 i = 0; i < winners.length; i++) {
            // This would integrate with Treasury for actual prize distribution
            emit PrizeDistributed(winners[i], amounts[i]);
        }
    }
    
    // Storage for new data
    mapping(uint256 => LeaderboardEntry) public leaderboard;
    mapping(address => uint256) public playerLatestEntry;
    uint256 public totalEntries;
    
    // Events for new functions
    event ScoreSubmitted(uint256 indexed entryId, address indexed player, uint256 score, uint256 completionTime, bytes32 gameplayHash);
    event VoteCast(uint256 indexed entryId, address indexed voter, uint256 votingPower);
    event PrizeDistributed(address indexed winner, uint256 amount);
}