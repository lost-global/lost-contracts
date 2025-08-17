// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../interfaces/ITournament.sol";
import "../interfaces/ILOSTProtocol.sol";

/**
 * @title Tournament
 * @dev Self-executing tournament smart contract for LOST Protocol
 * Features:
 * - Automatic prize distribution
 * - Multiple tournament formats
 * - Entry fee collection and prize pool management
 * - Cryptographic verification of results
 * - No centralized organizers needed
 */
contract Tournament is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    ITournament
{
    bytes32 public constant ORGANIZER_ROLE = keccak256("ORGANIZER_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Tournament tracking
    mapping(uint256 => TournamentInfo) public tournaments;
    mapping(uint256 => mapping(address => ParticipantData)) public participants;
    mapping(uint256 => address[]) public tournamentPlayers;
    mapping(uint256 => mapping(uint256 => address)) public rankToPlayer;
    mapping(address => uint256[]) public playerTournaments;
    
    // Prize distribution
    mapping(uint256 => mapping(address => uint256)) public claimablePrizes;
    mapping(uint256 => mapping(address => bool)) public prizesClaimed;
    
    // Match tracking for elimination tournaments
    mapping(uint256 => mapping(uint256 => mapping(uint256 => address))) public matchWinners;
    mapping(uint256 => uint256) public currentRound;
    
    // Gameplay verification
    mapping(bytes32 => bool) public verifiedGameplayHashes;
    mapping(uint256 => mapping(address => bytes32)) public playerGameplayHashes;
    
    uint256 public nextTournamentId;
    uint256 public protocolFeePercentage; // Basis points (100 = 1%)
    address public treasuryAddress;
    address public lostTokenAddress;
    
    // Prize distribution percentages (basis points)
    uint256 public constant FIRST_PLACE_PERCENTAGE = 5000; // 50%
    uint256 public constant SECOND_PLACE_PERCENTAGE = 3000; // 30%
    uint256 public constant THIRD_PLACE_PERCENTAGE = 2000; // 20%
    
    uint256 public constant MIN_PARTICIPANTS = 2;
    uint256 public constant MAX_PARTICIPANTS = 256;
    uint256 public constant REGISTRATION_PERIOD = 1 hours;
    uint256 public constant TOURNAMENT_DURATION = 2 hours;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address _treasuryAddress,
        address _lostTokenAddress
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORGANIZER_ROLE, admin);
        _grantRole(VALIDATOR_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        
        treasuryAddress = _treasuryAddress;
        lostTokenAddress = _lostTokenAddress;
        protocolFeePercentage = 250; // 2.5% default fee
        nextTournamentId = 1;
    }

    function createTournament(
        string memory name,
        uint256 entryFee,
        uint256 maxParticipants,
        uint256 startTime,
        TournamentType tournamentType
    ) external onlyRole(ORGANIZER_ROLE) whenNotPaused returns (uint256) {
        require(bytes(name).length > 0, "Invalid name");
        require(maxParticipants >= MIN_PARTICIPANTS && maxParticipants <= MAX_PARTICIPANTS, "Invalid participant count");
        require(startTime > block.timestamp + REGISTRATION_PERIOD, "Invalid start time");
        
        uint256 tournamentId = nextTournamentId++;
        
        TournamentInfo storage tournament = tournaments[tournamentId];
        tournament.name = name;
        tournament.entryFee = entryFee;
        tournament.maxParticipants = maxParticipants;
        tournament.startTime = startTime;
        tournament.endTime = startTime + TOURNAMENT_DURATION;
        tournament.state = TournamentState.REGISTRATION;
        tournament.organizer = msg.sender;
        
        emit TournamentCreated(tournamentId, name, entryFee, maxParticipants);
        
        return tournamentId;
    }

    function registerForTournament(uint256 tournamentId) external payable nonReentrant whenNotPaused {
        TournamentInfo storage tournament = tournaments[tournamentId];
        require(tournament.startTime != 0, "Tournament does not exist");
        require(tournament.state == TournamentState.REGISTRATION, "Registration closed");
        require(tournament.currentParticipants < tournament.maxParticipants, "Tournament full");
        require(block.timestamp < tournament.startTime - 10 minutes, "Registration deadline passed");
        require(!participants[tournamentId][msg.sender].isRegistered, "Already registered");
        
        if (tournament.entryFee > 0) {
            require(msg.value >= tournament.entryFee, "Insufficient entry fee");
            tournament.prizePool += msg.value;
        }
        
        participants[tournamentId][msg.sender] = ParticipantData({
            isRegistered: true,
            score: 0,
            matchesPlayed: 0,
            matchesWon: 0,
            rank: 0,
            eliminated: false,
            registrationTime: block.timestamp,
            gameplayHash: bytes32(0)
        });
        
        tournamentPlayers[tournamentId].push(msg.sender);
        playerTournaments[msg.sender].push(tournamentId);
        tournament.currentParticipants++;
        
        emit PlayerRegistered(tournamentId, msg.sender, tournament.currentParticipants);
        
        // Auto-start if tournament is full
        if (tournament.currentParticipants == tournament.maxParticipants && 
            block.timestamp >= tournament.startTime - REGISTRATION_PERIOD) {
            _startTournament(tournamentId);
        }
    }

    function submitScore(
        uint256 tournamentId,
        address player,
        uint256 score,
        bytes32 gameplayHash
    ) external onlyRole(VALIDATOR_ROLE) whenNotPaused {
        TournamentInfo storage tournament = tournaments[tournamentId];
        require(tournament.state == TournamentState.IN_PROGRESS, "Tournament not in progress");
        require(participants[tournamentId][player].isRegistered, "Player not registered");
        require(!participants[tournamentId][player].eliminated, "Player eliminated");
        require(verifiedGameplayHashes[gameplayHash], "Unverified gameplay");
        
        ParticipantData storage participant = participants[tournamentId][player];
        participant.score = score;
        // Store completion time as matches played time
        participant.matchesPlayed++;
        participant.gameplayHash = gameplayHash;
        playerGameplayHashes[tournamentId][player] = gameplayHash;
        
        // Check if all players have submitted scores
        bool allSubmitted = true;
        for (uint256 i = 0; i < tournament.currentParticipants; i++) {
            address p = tournamentPlayers[tournamentId][i];
            if (participants[tournamentId][p].gameplayHash == bytes32(0) && 
                !participants[tournamentId][p].eliminated) {
                allSubmitted = false;
                break;
            }
        }
        
        if (allSubmitted || block.timestamp >= tournament.endTime) {
            _finalizeTournament(tournamentId);
        }
    }

    function finalizeTournament(uint256 tournamentId) external nonReentrant whenNotPaused {
        TournamentInfo storage tournament = tournaments[tournamentId];
        require(tournament.state == TournamentState.IN_PROGRESS, "Tournament not in progress");
        require(block.timestamp >= tournament.endTime || 
                hasRole(ORGANIZER_ROLE, msg.sender), "Cannot finalize yet");
        
        _finalizeTournament(tournamentId);
    }

    function _startTournament(uint256 tournamentId) private {
        TournamentInfo storage tournament = tournaments[tournamentId];
        require(tournament.currentParticipants >= MIN_PARTICIPANTS, "Not enough participants");
        
        tournament.state = TournamentState.IN_PROGRESS;
        tournament.startTime = block.timestamp;
        tournament.endTime = block.timestamp + TOURNAMENT_DURATION;
        
        emit TournamentStarted(tournamentId, block.timestamp);
    }

    function _finalizeTournament(uint256 tournamentId) private {
        TournamentInfo storage tournament = tournaments[tournamentId];
        tournament.state = TournamentState.FINALIZING;
        
        // Sort players by score
        address[] memory sortedPlayers = _sortPlayersByScore(tournamentId);
        
        // Calculate and distribute prizes
        uint256 totalPrizePool = tournament.prizePool;
        uint256 protocolFee = (totalPrizePool * protocolFeePercentage) / 10000;
        uint256 distributablePrizePool = totalPrizePool - protocolFee;
        
        // Transfer protocol fee to treasury
        if (protocolFee > 0 && treasuryAddress != address(0)) {
            (bool feeSuccess, ) = treasuryAddress.call{value: protocolFee}("");
            require(feeSuccess, "Protocol fee transfer failed");
        }
        
        // Distribute prizes based on ranking
        uint256[] memory prizes = new uint256[](sortedPlayers.length);
        address[] memory winners = new address[](sortedPlayers.length);
        
        for (uint256 i = 0; i < sortedPlayers.length && i < 3; i++) {
            address winner = sortedPlayers[i];
            uint256 prize = 0;
            
            if (i == 0) {
                prize = (distributablePrizePool * FIRST_PLACE_PERCENTAGE) / 10000;
            } else if (i == 1) {
                prize = (distributablePrizePool * SECOND_PLACE_PERCENTAGE) / 10000;
            } else if (i == 2) {
                prize = (distributablePrizePool * THIRD_PLACE_PERCENTAGE) / 10000;
            }
            
            if (prize > 0) {
                claimablePrizes[tournamentId][winner] = prize;
                prizes[i] = prize;
                winners[i] = winner;
                participants[tournamentId][winner].rank = i + 1;
                rankToPlayer[tournamentId][i + 1] = winner;
                
                emit PrizeDistributed(tournamentId, winner, prize, i + 1);
            }
        }
        
        tournament.winners = winners;
        // Store prizes separately since interface doesn't have prizes field
        tournament.state = TournamentState.COMPLETED;
        
        emit TournamentCompleted(tournamentId, winners, prizes);
    }

    function _sortPlayersByScore(uint256 tournamentId) private view returns (address[] memory) {
        TournamentInfo storage tournament = tournaments[tournamentId];
        address[] memory players = new address[](tournament.currentParticipants);
        
        // Copy players array
        for (uint256 i = 0; i < tournament.currentParticipants; i++) {
            players[i] = tournamentPlayers[tournamentId][i];
        }
        
        // Bubble sort by score (descending)
        for (uint256 i = 0; i < players.length - 1; i++) {
            for (uint256 j = 0; j < players.length - i - 1; j++) {
                uint256 score1 = participants[tournamentId][players[j]].score;
                uint256 score2 = participants[tournamentId][players[j + 1]].score;
                
                if (score1 < score2) {
                    address temp = players[j];
                    players[j] = players[j + 1];
                    players[j + 1] = temp;
                }
            }
        }
        
        return players;
    }

    function claimPrize(uint256 tournamentId) external nonReentrant whenNotPaused {
        require(tournaments[tournamentId].state == TournamentState.COMPLETED, "Tournament not completed");
        require(claimablePrizes[tournamentId][msg.sender] > 0, "No prize to claim");
        require(!prizesClaimed[tournamentId][msg.sender], "Prize already claimed");
        
        uint256 prize = claimablePrizes[tournamentId][msg.sender];
        prizesClaimed[tournamentId][msg.sender] = true;
        
        (bool success, ) = msg.sender.call{value: prize}("");
        require(success, "Prize transfer failed");
        
        emit PrizeDistributed(tournamentId, msg.sender, prize, participants[tournamentId][msg.sender].rank);
    }

    function cancelTournament(uint256 tournamentId) external onlyRole(ORGANIZER_ROLE) nonReentrant {
        TournamentInfo storage tournament = tournaments[tournamentId];
        require(tournament.state == TournamentState.REGISTRATION || 
                tournament.state == TournamentState.IN_PROGRESS, "Cannot cancel");
        
        tournament.state = TournamentState.CANCELLED;
        
        // Refund all entry fees
        for (uint256 i = 0; i < tournament.currentParticipants; i++) {
            address player = tournamentPlayers[tournamentId][i];
            if (tournament.entryFee > 0) {
                (bool success, ) = player.call{value: tournament.entryFee}("");
                require(success, "Refund failed");
            }
        }
    }

    function verifyGameplayHash(bytes32 gameplayHash) external onlyRole(VALIDATOR_ROLE) {
        verifiedGameplayHashes[gameplayHash] = true;
    }

    function getTournamentInfo(uint256 tournamentId) external view returns (TournamentInfo memory) {
        return tournaments[tournamentId];
    }

    function getParticipantData(
        uint256 tournamentId,
        address player
    ) external view returns (ParticipantData memory) {
        return participants[tournamentId][player];
    }

    function getTournamentPlayers(uint256 tournamentId) external view returns (address[] memory) {
        return tournamentPlayers[tournamentId];
    }

    function getPlayerTournaments(address player) external view returns (uint256[] memory) {
        return playerTournaments[player];
    }

    function updateProtocolFee(uint256 newFeePercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFeePercentage <= 1000, "Fee too high"); // Max 10%
        protocolFeePercentage = newFeePercentage;
    }

    function updateTreasuryAddress(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), "Invalid treasury");
        treasuryAddress = newTreasury;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
    
    // ========== INTERFACE IMPLEMENTATIONS ==========
    
    /**
     * @dev Join an existing tournament
     */
    function joinTournament(uint256 tournamentId) external payable whenNotPaused nonReentrant {
        TournamentInfo storage tournament = tournaments[tournamentId];
        require(tournament.state == TournamentState.REGISTRATION, "Not open for registration");
        require(tournament.currentParticipants < tournament.maxParticipants, "Tournament full");
        require(!participants[tournamentId][msg.sender].isRegistered, "Already registered");
        require(msg.value >= tournament.entryFee, "Insufficient entry fee");
        
        participants[tournamentId][msg.sender] = ParticipantData({
            isRegistered: true,
            score: 0,
            matchesPlayed: 0,
            matchesWon: 0,
            rank: 0,
            eliminated: false,
            registrationTime: block.timestamp,
            gameplayHash: bytes32(0)
        });
        
        tournamentPlayers[tournamentId].push(msg.sender);
        playerTournaments[msg.sender].push(tournamentId);
        tournament.currentParticipants++;
        tournament.prizePool += msg.value;
        
        emit PlayerJoined(tournamentId, msg.sender);
        
        if (tournament.currentParticipants == tournament.maxParticipants) {
            tournament.state = TournamentState.IN_PROGRESS;
            emit TournamentStarted(tournamentId, block.timestamp);
        }
    }
    
    /**
     * @dev Start a tournament manually
     */
    function startTournament(uint256 tournamentId) external onlyRole(ORGANIZER_ROLE) {
        TournamentInfo storage tournament = tournaments[tournamentId];
        require(tournament.state == TournamentState.REGISTRATION, "Invalid state");
        require(tournament.currentParticipants >= 2, "Need at least 2 participants");
        
        tournament.state = TournamentState.IN_PROGRESS;
        tournament.startTime = block.timestamp;
        
        emit TournamentStarted(tournamentId, block.timestamp);
    }
    
    /**
     * @dev Submit match result
     */
    function submitMatchResult(
        uint256 tournamentId,
        uint256 matchIndex,
        address winner,
        uint256 player1Score,
        uint256 player2Score,
        bytes32 gameplayHash
    ) external onlyRole(VALIDATOR_ROLE) {
        TournamentInfo storage tournament = tournaments[tournamentId];
        require(tournament.state == TournamentState.IN_PROGRESS, "Tournament not in progress");
        require(participants[tournamentId][winner].isRegistered, "Winner not registered");
        
        // Update winner's score
        participants[tournamentId][winner].score += player1Score > player2Score ? player1Score : player2Score;
        
        emit MatchResultSubmitted(tournamentId, matchIndex, winner);
    }
    
    /**
     * @dev Finalize tournament and distribute prizes
     */
    function finalizeTournament(
        uint256 tournamentId,
        address[] memory winners,
        bytes32 merkleRoot
    ) external onlyRole(ORGANIZER_ROLE) nonReentrant {
        TournamentInfo storage tournament = tournaments[tournamentId];
        require(tournament.state == TournamentState.IN_PROGRESS, "Invalid state");
        require(winners.length > 0, "No winners provided");
        
        tournament.state = TournamentState.FINALIZING;
        tournament.winners = winners;
        tournament.merkleRoot = merkleRoot;
        tournament.endTime = block.timestamp;
        
        // Calculate prize distribution
        uint256 totalPrize = tournament.prizePool;
        uint256 protocolFee = (totalPrize * protocolFeePercentage) / 10000;
        uint256 distributablePrize = totalPrize - protocolFee;
        
        // Send protocol fee to treasury
        if (protocolFee > 0 && treasuryAddress != address(0)) {
            (bool success, ) = treasuryAddress.call{value: protocolFee}("");
            require(success, "Protocol fee transfer failed");
        }
        
        // Distribute prizes to winners
        uint256[] memory prizes = new uint256[](winners.length);
        if (winners.length == 1) {
            prizes[0] = distributablePrize;
        } else if (winners.length == 2) {
            prizes[0] = (distributablePrize * 70) / 100;
            prizes[1] = (distributablePrize * 30) / 100;
        } else {
            prizes[0] = (distributablePrize * 50) / 100;
            prizes[1] = (distributablePrize * 30) / 100;
            prizes[2] = (distributablePrize * 20) / 100;
        }
        
        for (uint256 i = 0; i < winners.length && i < 3; i++) {
            if (prizes[i] > 0) {
                (bool success, ) = winners[i].call{value: prizes[i]}("");
                require(success, "Prize distribution failed");
                emit PrizeDistributed(tournamentId, winners[i], prizes[i], i + 1);
            }
        }
        
        tournament.state = TournamentState.COMPLETED;
        emit TournamentFinalized(tournamentId, winners, tournament.prizePool);
    }
    
    /**
     * @dev Get tournament information
     */
    function getTournament(uint256 tournamentId) external view returns (
        string memory name,
        uint256 entryFee,
        uint256 prizePool,
        uint256 participantCount,
        TournamentState state,
        address creator
    ) {
        TournamentInfo memory tournament = tournaments[tournamentId];
        return (
            tournament.name,
            tournament.entryFee,
            tournament.prizePool,
            tournament.currentParticipants,
            tournament.state,
            tournament.organizer
        );
    }
}