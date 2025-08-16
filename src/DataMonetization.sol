// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DataMonetization
 * @dev Player data control and monetization contract for LOST Protocol
 * Features:
 * - Opt-in analytics sharing for rewards
 * - Granular privacy controls via smart contracts
 * - Retroactive consent revocation
 * - Profit sharing from AI training on gameplay patterns
 * - Heat map and telemetry data management
 */
contract DataMonetization is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant DATA_PROCESSOR_ROLE = keccak256("DATA_PROCESSOR_ROLE");
    bytes32 public constant RESEARCHER_ROLE = keccak256("RESEARCHER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    struct PlayerDataConsent {
        bool movementData;
        bool performanceMetrics;
        bool puzzleSolutions;
        bool socialInteractions;
        bool aiTrainingData;
        uint256 consentTimestamp;
        uint256 revocationTimestamp;
    }

    struct DataPackage {
        uint256 packageId;
        string dataType;
        uint256 dataPoints;
        uint256 price;
        address buyer;
        uint256 soldTimestamp;
        bool active;
    }

    struct ResearchProject {
        uint256 projectId;
        string name;
        address researcher;
        uint256 budget;
        uint256 spent;
        uint256 startTime;
        uint256 endTime;
        bool active;
        mapping(address => bool) participants;
        uint256 participantCount;
    }

    struct PlayerTelemetry {
        uint256 totalPlaytime;
        uint256 puzzlesSolved;
        uint256 secretsFound;
        uint256 averageCompletionTime;
        bytes32[] movementHashes;
        mapping(uint256 => bytes32) heatmapData;
    }

    // Data consent management
    mapping(address => PlayerDataConsent) public playerConsents;
    mapping(address => uint256) public dataRevenueShare;
    mapping(address => uint256) public pendingRewards;
    
    // Data packages for sale
    mapping(uint256 => DataPackage) public dataPackages;
    uint256 public nextPackageId;
    
    // Research projects
    mapping(uint256 => ResearchProject) public researchProjects;
    uint256 public nextProjectId;
    
    // Player telemetry
    mapping(address => PlayerTelemetry) private playerTelemetry;
    
    // Anonymized aggregate data
    mapping(bytes32 => uint256) public aggregateMetrics;
    mapping(uint256 => mapping(uint256 => uint256)) public globalHeatmap;
    
    // Revenue tracking
    uint256 public totalDataRevenue;
    uint256 public playerRevenuePool;
    mapping(address => uint256) public playerDataContributions;
    
    // Privacy settings
    mapping(address => bool) public optedOut;
    mapping(address => uint256) public dataRetentionPeriod;
    
    address public lostTokenAddress;
    address public treasuryAddress;
    uint256 public revenueSharePercentage; // Basis points - share for players
    uint256 public minimumDataPoints;
    uint256 public dataRewardRate; // LOST per data point

    event DataConsentGranted(address indexed player, string dataTypes);
    event DataConsentRevoked(address indexed player, string dataTypes);
    event DataPackageSold(uint256 indexed packageId, address indexed buyer, uint256 price);
    event ResearchProjectCreated(uint256 indexed projectId, string name, uint256 budget);
    event PlayerJoinedResearch(uint256 indexed projectId, address indexed player);
    event DataRewardsDistributed(address indexed player, uint256 amount);
    event TelemetryRecorded(address indexed player, string dataType, uint256 dataPoints);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address _lostTokenAddress,
        address _treasuryAddress
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DATA_PROCESSOR_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        
        lostTokenAddress = _lostTokenAddress;
        treasuryAddress = _treasuryAddress;
        
        nextPackageId = 1;
        nextProjectId = 1;
        revenueSharePercentage = 7000; // 70% to players
        minimumDataPoints = 100;
        dataRewardRate = 1 * 10**18; // 1 LOST per data point
    }

    function grantDataConsent(
        bool movementData,
        bool performanceMetrics,
        bool puzzleSolutions,
        bool socialInteractions,
        bool aiTrainingData
    ) external whenNotPaused {
        PlayerDataConsent storage consent = playerConsents[msg.sender];
        
        consent.movementData = movementData;
        consent.performanceMetrics = performanceMetrics;
        consent.puzzleSolutions = puzzleSolutions;
        consent.socialInteractions = socialInteractions;
        consent.aiTrainingData = aiTrainingData;
        consent.consentTimestamp = block.timestamp;
        consent.revocationTimestamp = 0;
        
        optedOut[msg.sender] = false;
        
        string memory dataTypes = _buildDataTypeString(consent);
        emit DataConsentGranted(msg.sender, dataTypes);
    }

    function revokeDataConsent() external {
        PlayerDataConsent storage consent = playerConsents[msg.sender];
        
        consent.movementData = false;
        consent.performanceMetrics = false;
        consent.puzzleSolutions = false;
        consent.socialInteractions = false;
        consent.aiTrainingData = false;
        consent.revocationTimestamp = block.timestamp;
        
        optedOut[msg.sender] = true;
        
        // Clear pending rewards
        uint256 rewards = pendingRewards[msg.sender];
        if (rewards > 0) {
            pendingRewards[msg.sender] = 0;
            IERC20(lostTokenAddress).transfer(msg.sender, rewards);
        }
        
        emit DataConsentRevoked(msg.sender, "All data types");
    }

    function recordTelemetry(
        address player,
        string memory dataType,
        bytes32 dataHash,
        uint256 dataPoints
    ) external onlyRole(DATA_PROCESSOR_ROLE) whenNotPaused {
        require(!optedOut[player], "Player opted out");
        
        PlayerDataConsent memory consent = playerConsents[player];
        require(_hasConsentForDataType(consent, dataType), "No consent for data type");
        
        PlayerTelemetry storage telemetry = playerTelemetry[player];
        
        if (keccak256(bytes(dataType)) == keccak256("movement")) {
            telemetry.movementHashes.push(dataHash);
        } else if (keccak256(bytes(dataType)) == keccak256("puzzle")) {
            telemetry.puzzlesSolved++;
        } else if (keccak256(bytes(dataType)) == keccak256("secret")) {
            telemetry.secretsFound++;
        }
        
        playerDataContributions[player] += dataPoints;
        
        // Calculate rewards
        uint256 reward = dataPoints * dataRewardRate;
        pendingRewards[player] += reward;
        
        emit TelemetryRecorded(player, dataType, dataPoints);
    }

    function createDataPackage(
        string memory dataType,
        uint256 dataPoints,
        uint256 price
    ) external onlyRole(DATA_PROCESSOR_ROLE) whenNotPaused returns (uint256) {
        require(dataPoints >= minimumDataPoints, "Insufficient data points");
        require(price > 0, "Invalid price");
        
        uint256 packageId = nextPackageId++;
        
        dataPackages[packageId] = DataPackage({
            packageId: packageId,
            dataType: dataType,
            dataPoints: dataPoints,
            price: price,
            buyer: address(0),
            soldTimestamp: 0,
            active: true
        });
        
        return packageId;
    }

    function purchaseDataPackage(uint256 packageId) external payable nonReentrant whenNotPaused {
        DataPackage storage package = dataPackages[packageId];
        require(package.active, "Package not available");
        require(package.buyer == address(0), "Already sold");
        require(msg.value >= package.price, "Insufficient payment");
        
        package.buyer = msg.sender;
        package.soldTimestamp = block.timestamp;
        package.active = false;
        
        // Distribute revenue
        uint256 playerShare = (package.price * revenueSharePercentage) / 10000;
        uint256 treasuryShare = package.price - playerShare;
        
        playerRevenuePool += playerShare;
        totalDataRevenue += package.price;
        
        (bool treasurySuccess, ) = treasuryAddress.call{value: treasuryShare}("");
        require(treasurySuccess, "Treasury transfer failed");
        
        // Refund excess
        if (msg.value > package.price) {
            (bool refundSuccess, ) = msg.sender.call{value: msg.value - package.price}("");
            require(refundSuccess, "Refund failed");
        }
        
        emit DataPackageSold(packageId, msg.sender, package.price);
    }

    function createResearchProject(
        string memory name,
        uint256 budget,
        uint256 duration
    ) external onlyRole(RESEARCHER_ROLE) whenNotPaused returns (uint256) {
        require(bytes(name).length > 0, "Invalid name");
        require(budget > 0, "Invalid budget");
        require(duration > 0, "Invalid duration");
        
        uint256 projectId = nextProjectId++;
        
        ResearchProject storage project = researchProjects[projectId];
        project.projectId = projectId;
        project.name = name;
        project.researcher = msg.sender;
        project.budget = budget;
        project.spent = 0;
        project.startTime = block.timestamp;
        project.endTime = block.timestamp + duration;
        project.active = true;
        project.participantCount = 0;
        
        emit ResearchProjectCreated(projectId, name, budget);
        
        return projectId;
    }

    function joinResearchProject(uint256 projectId) external whenNotPaused {
        ResearchProject storage project = researchProjects[projectId];
        require(project.active, "Project not active");
        require(block.timestamp < project.endTime, "Project ended");
        require(!project.participants[msg.sender], "Already participating");
        require(playerConsents[msg.sender].aiTrainingData, "AI training consent required");
        
        project.participants[msg.sender] = true;
        project.participantCount++;
        
        emit PlayerJoinedResearch(projectId, msg.sender);
    }

    function claimDataRewards() external nonReentrant whenNotPaused {
        uint256 rewards = pendingRewards[msg.sender];
        require(rewards > 0, "No rewards to claim");
        
        // Calculate share from revenue pool
        uint256 contribution = playerDataContributions[msg.sender];
        uint256 totalContributions = _getTotalContributions();
        
        if (totalContributions > 0 && playerRevenuePool > 0) {
            uint256 revenueShare = (playerRevenuePool * contribution) / totalContributions;
            rewards += revenueShare;
            playerRevenuePool -= revenueShare;
        }
        
        pendingRewards[msg.sender] = 0;
        dataRevenueShare[msg.sender] += rewards;
        
        IERC20(lostTokenAddress).transfer(msg.sender, rewards);
        
        emit DataRewardsDistributed(msg.sender, rewards);
    }

    function updateHeatmap(
        uint256 x,
        uint256 y,
        uint256 intensity
    ) external onlyRole(DATA_PROCESSOR_ROLE) {
        globalHeatmap[x][y] += intensity;
        aggregateMetrics[keccak256("heatmap_updates")]++;
    }

    function setDataRetentionPeriod(uint256 _days) external {
        require(_days >= 30 && _days <= 365, "Invalid retention period");
        dataRetentionPeriod[msg.sender] = _days * 1 days;
    }

    function deletePlayerData(address player) external onlyRole(DATA_PROCESSOR_ROLE) {
        require(
            optedOut[player] || 
            (dataRetentionPeriod[player] > 0 && 
             block.timestamp > playerConsents[player].revocationTimestamp + dataRetentionPeriod[player]),
            "Cannot delete data"
        );
        
        delete playerTelemetry[player];
        delete playerDataContributions[player];
    }

    function _hasConsentForDataType(
        PlayerDataConsent memory consent,
        string memory dataType
    ) private pure returns (bool) {
        bytes32 typeHash = keccak256(bytes(dataType));
        
        if (typeHash == keccak256("movement")) return consent.movementData;
        if (typeHash == keccak256("performance")) return consent.performanceMetrics;
        if (typeHash == keccak256("puzzle")) return consent.puzzleSolutions;
        if (typeHash == keccak256("social")) return consent.socialInteractions;
        if (typeHash == keccak256("ai")) return consent.aiTrainingData;
        
        return false;
    }

    function _buildDataTypeString(PlayerDataConsent memory consent) private pure returns (string memory) {
        string memory types = "";
        if (consent.movementData) types = string(abi.encodePacked(types, "movement,"));
        if (consent.performanceMetrics) types = string(abi.encodePacked(types, "performance,"));
        if (consent.puzzleSolutions) types = string(abi.encodePacked(types, "puzzles,"));
        if (consent.socialInteractions) types = string(abi.encodePacked(types, "social,"));
        if (consent.aiTrainingData) types = string(abi.encodePacked(types, "ai,"));
        return types;
    }

    function _getTotalContributions() private view returns (uint256) {
        return aggregateMetrics[keccak256("total_contributions")];
    }

    function getPlayerConsent(address player) external view returns (PlayerDataConsent memory) {
        return playerConsents[player];
    }

    function getResearchParticipants(uint256 projectId) external view returns (uint256) {
        return researchProjects[projectId].participantCount;
    }

    function isParticipatingInResearch(uint256 projectId, address player) external view returns (bool) {
        return researchProjects[projectId].participants[player];
    }

    function updateRevenueShare(uint256 newPercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newPercentage >= 5000 && newPercentage <= 9000, "Invalid percentage");
        revenueSharePercentage = newPercentage;
    }

    function updateDataRewardRate(uint256 newRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        dataRewardRate = newRate;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}