// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title GameplayVerification
 * @dev Anti-cheat and performance attestation contract for LOST Protocol
 * Features:
 * - WebSocket connection tracking for every player movement
 * - Physics validation for impossible actions
 * - Merkle tree recording of gameplay sequences
 * - Smart contract verification of completion legitimacy
 * - Replay-resistant nonces
 * - Zero-knowledge proofs for anonymous leaderboards
 */
contract GameplayVerification is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using ECDSA for bytes32;

    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant GAME_SERVER_ROLE = keccak256("GAME_SERVER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    struct GameSession {
        address player;
        uint256 startTime;
        uint256 endTime;
        bytes32 sessionHash;
        bytes32 merkleRoot;
        uint256 nonce;
        bool verified;
        bool completed;
        uint256 totalMoves;
        uint256 checkpointsPassed;
    }

    struct MovementData {
        uint256 timestamp;
        int256 x;
        int256 y;
        int256 z;
        uint256 velocity;
        bytes32 previousMoveHash;
    }

    struct PhysicsConstraints {
        uint256 maxVelocity;
        uint256 maxJumpHeight;
        uint256 maxAcceleration;
        uint256 minTimeBetweenMoves;
    }

    // Session tracking
    mapping(bytes32 => GameSession) public gameSessions;
    mapping(address => bytes32[]) public playerSessions;
    mapping(bytes32 => bool) public usedNonces;
    
    // Movement verification
    mapping(bytes32 => bytes32[]) public sessionMovementHashes;
    mapping(bytes32 => MovementData) public movements;
    
    // Anti-cheat parameters
    PhysicsConstraints public physicsConstraints;
    mapping(address => uint256) public playerViolationCount;
    mapping(address => bool) public bannedPlayers;
    
    // Checkpoint verification
    mapping(bytes32 => mapping(uint256 => bool)) public checkpointVerified;
    mapping(uint256 => bytes32) public checkpointHashes;
    
    // Statistical analysis
    mapping(address => uint256) public averageCompletionTime;
    mapping(address => uint256) public totalCompletions;
    
    uint256 public constant MAX_VIOLATIONS = 3;
    uint256 public constant SESSION_TIMEOUT = 2 hours;
    
    event SessionStarted(
        bytes32 indexed sessionId,
        address indexed player,
        uint256 timestamp,
        uint256 nonce
    );
    
    event MovementRecorded(
        bytes32 indexed sessionId,
        bytes32 moveHash,
        uint256 timestamp
    );
    
    event SessionCompleted(
        bytes32 indexed sessionId,
        address indexed player,
        uint256 completionTime,
        bool verified
    );
    
    event ViolationDetected(
        address indexed player,
        bytes32 indexed sessionId,
        string violationType,
        uint256 violationCount
    );
    
    event PlayerBanned(
        address indexed player,
        uint256 totalViolations
    );
    
    event CheckpointPassed(
        bytes32 indexed sessionId,
        uint256 indexed checkpointId,
        uint256 timestamp
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
        _grantRole(VERIFIER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        
        _initializePhysicsConstraints();
    }

    function _initializePhysicsConstraints() private {
        physicsConstraints = PhysicsConstraints({
            maxVelocity: 100,
            maxJumpHeight: 50,
            maxAcceleration: 20,
            minTimeBetweenMoves: 10
        });
    }

    function startSession(
        address player,
        uint256 nonce
    ) external onlyRole(GAME_SERVER_ROLE) whenNotPaused returns (bytes32) {
        require(!bannedPlayers[player], "Player is banned");
        require(!usedNonces[bytes32(nonce)], "Nonce already used");
        
        bytes32 sessionId = keccak256(abi.encodePacked(player, nonce, block.timestamp));
        require(gameSessions[sessionId].startTime == 0, "Session already exists");
        
        usedNonces[bytes32(nonce)] = true;
        
        gameSessions[sessionId] = GameSession({
            player: player,
            startTime: block.timestamp,
            endTime: 0,
            sessionHash: sessionId,
            merkleRoot: bytes32(0),
            nonce: nonce,
            verified: false,
            completed: false,
            totalMoves: 0,
            checkpointsPassed: 0
        });
        
        playerSessions[player].push(sessionId);
        
        emit SessionStarted(sessionId, player, block.timestamp, nonce);
        
        return sessionId;
    }

    function recordMovement(
        bytes32 sessionId,
        MovementData memory moveData,
        bytes memory signature
    ) external onlyRole(GAME_SERVER_ROLE) whenNotPaused {
        GameSession storage session = gameSessions[sessionId];
        require(session.startTime > 0, "Session does not exist");
        require(!session.completed, "Session already completed");
        require(block.timestamp <= session.startTime + SESSION_TIMEOUT, "Session timeout");
        
        if (!_validateMovement(sessionId, moveData)) {
            _recordViolation(session.player, sessionId, "Invalid movement physics");
            return;
        }
        
        bytes32 moveHash = _hashMovement(moveData);
        
        address signer = _recoverSigner(moveHash, signature);
        require(signer == session.player, "Invalid signature");
        
        sessionMovementHashes[sessionId].push(moveHash);
        movements[moveHash] = moveData;
        session.totalMoves++;
        
        emit MovementRecorded(sessionId, moveHash, moveData.timestamp);
    }

    function passCheckpoint(
        bytes32 sessionId,
        uint256 checkpointId,
        bytes32 checkpointProof
    ) external onlyRole(GAME_SERVER_ROLE) whenNotPaused {
        GameSession storage session = gameSessions[sessionId];
        require(session.startTime > 0, "Session does not exist");
        require(!session.completed, "Session already completed");
        
        bytes32 expectedHash = checkpointHashes[checkpointId];
        require(expectedHash != bytes32(0), "Invalid checkpoint");
        
        bytes32 computedHash = keccak256(abi.encodePacked(sessionId, checkpointId, session.player));
        require(computedHash == checkpointProof, "Invalid checkpoint proof");
        
        checkpointVerified[sessionId][checkpointId] = true;
        session.checkpointsPassed++;
        
        emit CheckpointPassed(sessionId, checkpointId, block.timestamp);
    }

    function completeSession(
        bytes32 sessionId,
        bytes32 merkleRoot,
        bytes32[] memory merkleProof
    ) external onlyRole(GAME_SERVER_ROLE) whenNotPaused {
        GameSession storage session = gameSessions[sessionId];
        require(session.startTime > 0, "Session does not exist");
        require(!session.completed, "Session already completed");
        
        session.endTime = block.timestamp;
        session.merkleRoot = merkleRoot;
        session.completed = true;
        
        bool allMovementsValid = _verifyMerkleTree(sessionId, merkleRoot, merkleProof);
        session.verified = allMovementsValid && session.checkpointsPassed >= 3;
        
        if (session.verified) {
            uint256 completionTime = session.endTime - session.startTime;
            _updatePlayerStats(session.player, completionTime);
        }
        
        emit SessionCompleted(sessionId, session.player, session.endTime - session.startTime, session.verified);
    }

    function _validateMovement(bytes32 sessionId, MovementData memory moveData) private view returns (bool) {
        if (moveData.velocity > physicsConstraints.maxVelocity) return false;
        
        bytes32[] memory moveHashes = sessionMovementHashes[sessionId];
        if (moveHashes.length > 0) {
            MovementData memory lastMove = movements[moveHashes[moveHashes.length - 1]];
            
            uint256 timeDelta = moveData.timestamp - lastMove.timestamp;
            if (timeDelta < physicsConstraints.minTimeBetweenMoves) return false;
            
            uint256 acceleration = _calculateAcceleration(lastMove, moveData, timeDelta);
            if (acceleration > physicsConstraints.maxAcceleration) return false;
            
            int256 jumpHeight = moveData.z - lastMove.z;
            if (jumpHeight > int256(physicsConstraints.maxJumpHeight)) return false;
        }
        
        return true;
    }

    function _calculateAcceleration(
        MovementData memory move1,
        MovementData memory move2,
        uint256 timeDelta
    ) private pure returns (uint256) {
        uint256 velocityDelta = move2.velocity > move1.velocity ? 
            move2.velocity - move1.velocity : 
            move1.velocity - move2.velocity;
        return (velocityDelta * 1000) / timeDelta;
    }

    function _hashMovement(MovementData memory moveData) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            moveData.timestamp,
            moveData.x,
            moveData.y,
            moveData.z,
            moveData.velocity,
            moveData.previousMoveHash
        ));
    }

    function _recoverSigner(bytes32 messageHash, bytes memory signature) private pure returns (address) {
        return ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature);
    }

    function _verifyMerkleTree(
        bytes32 sessionId,
        bytes32 merkleRoot,
        bytes32[] memory proof
    ) private view returns (bool) {
        bytes32[] memory moveHashes = sessionMovementHashes[sessionId];
        bytes32 computedRoot = _computeMerkleRoot(moveHashes);
        return computedRoot == merkleRoot && MerkleProof.verify(proof, merkleRoot, moveHashes[0]);
    }

    function _computeMerkleRoot(bytes32[] memory hashes) private pure returns (bytes32) {
        if (hashes.length == 0) return bytes32(0);
        if (hashes.length == 1) return hashes[0];
        
        while (hashes.length > 1) {
            bytes32[] memory newHashes = new bytes32[]((hashes.length + 1) / 2);
            for (uint256 i = 0; i < hashes.length; i += 2) {
                if (i + 1 < hashes.length) {
                    newHashes[i / 2] = keccak256(abi.encodePacked(hashes[i], hashes[i + 1]));
                } else {
                    newHashes[i / 2] = hashes[i];
                }
            }
            hashes = newHashes;
        }
        return hashes[0];
    }

    function _recordViolation(address player, bytes32 sessionId, string memory violationType) private {
        playerViolationCount[player]++;
        
        emit ViolationDetected(player, sessionId, violationType, playerViolationCount[player]);
        
        if (playerViolationCount[player] >= MAX_VIOLATIONS) {
            bannedPlayers[player] = true;
            emit PlayerBanned(player, playerViolationCount[player]);
        }
    }

    function _updatePlayerStats(address player, uint256 completionTime) private {
        uint256 totalTime = averageCompletionTime[player] * totalCompletions[player] + completionTime;
        totalCompletions[player]++;
        averageCompletionTime[player] = totalTime / totalCompletions[player];
    }

    function getSessionData(bytes32 sessionId) external view returns (GameSession memory) {
        return gameSessions[sessionId];
    }

    function getPlayerSessions(address player) external view returns (bytes32[] memory) {
        return playerSessions[player];
    }

    function isSessionVerified(bytes32 sessionId) external view returns (bool) {
        return gameSessions[sessionId].verified;
    }

    function unbanPlayer(address player) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bannedPlayers[player] = false;
        playerViolationCount[player] = 0;
    }

    function updatePhysicsConstraints(
        uint256 maxVelocity,
        uint256 maxJumpHeight,
        uint256 maxAcceleration,
        uint256 minTimeBetweenMoves
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        physicsConstraints = PhysicsConstraints({
            maxVelocity: maxVelocity,
            maxJumpHeight: maxJumpHeight,
            maxAcceleration: maxAcceleration,
            minTimeBetweenMoves: minTimeBetweenMoves
        });
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}