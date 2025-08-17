// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ITreasury.sol";

/**
 * @title Treasury
 * @dev Protocol treasury and economics management for LOST Protocol
 * Features:
 * - Protocol fee collection and distribution
 * - Liquidity management
 * - Reward pool allocation
 * - Ecosystem fund management
 * - Burn mechanisms
 * - Emergency functions
 */
contract Treasury is
    ITreasury,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    struct Allocation {
        uint256 rewardPool;      // For player rewards
        uint256 developmentFund;  // For protocol development
        uint256 marketingFund;    // For marketing and partnerships
        uint256 liquidityFund;    // For liquidity provisions
        uint256 stakingRewards;   // For staking rewards
        uint256 ecosystemGrants;  // For ecosystem development
        uint256 insuranceFund;    // For emergency coverage
    }

    struct FundingProposal {
        uint256 proposalId;
        address recipient;
        uint256 amount;
        string purpose;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endTime;
        bool executed;
        bool cancelled;
    }

    struct RevenueStream {
        string source;
        uint256 totalCollected;
        uint256 lastCollection;
        bool active;
    }

    // Core addresses
    address public lostTokenAddress;
    address public usdcTokenAddress;
    mapping(address => bool) public approvedTokens;
    mapping(address => bool) public protocolContracts;

    // Fund allocations
    Allocation public allocations;
    mapping(string => uint256) public fundBalances;
    
    // Revenue tracking
    mapping(string => RevenueStream) public revenueStreams;
    uint256 public totalRevenue;
    uint256 public totalDistributed;
    
    // Funding proposals
    mapping(uint256 => FundingProposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public nextProposalId;
    
    // Burn tracking
    uint256 public totalBurned;
    uint256 public burnRate; // Basis points of fees to burn
    
    // Economic parameters
    uint256 public targetLiquidity;
    uint256 public minimumReserve;
    uint256 public rewardMultiplier;
    
    // Distribution percentages (basis points)
    uint256 public constant REWARD_POOL_PERCENTAGE = 4000;      // 40%
    uint256 public constant DEVELOPMENT_PERCENTAGE = 1500;      // 15%
    uint256 public constant MARKETING_PERCENTAGE = 1000;        // 10%
    uint256 public constant LIQUIDITY_PERCENTAGE = 1500;        // 15%
    uint256 public constant STAKING_PERCENTAGE = 1000;          // 10%
    uint256 public constant ECOSYSTEM_PERCENTAGE = 500;         // 5%
    uint256 public constant INSURANCE_PERCENTAGE = 500;         // 5%

    uint256 public constant PROPOSAL_DURATION = 3 days;
    uint256 public constant MINIMUM_PROPOSAL_AMOUNT = 1000 * 10**18; // 1000 LOST

    event FundsAllocated(string fund, uint256 amount);
    event RevenueCollected(string source, uint256 amount);
    event FundsDistributed(address indexed recipient, uint256 amount, string purpose);
    event ProposalCreated(uint256 indexed proposalId, address recipient, uint256 amount);
    event ProposalExecuted(uint256 indexed proposalId, bool approved);
    event TokensBurned(uint256 amount);
    event EmergencyWithdrawal(address token, uint256 amount);
    event ProtocolContractUpdated(address contractAddress, bool approved);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address _lostTokenAddress,
        address _usdcTokenAddress
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TREASURER_ROLE, admin);
        _grantRole(ALLOCATOR_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        
        lostTokenAddress = _lostTokenAddress;
        usdcTokenAddress = _usdcTokenAddress;
        
        approvedTokens[lostTokenAddress] = true;
        approvedTokens[usdcTokenAddress] = true;
        
        nextProposalId = 1;
        burnRate = 500; // 5% burn rate
        targetLiquidity = 1000000 * 10**18; // 1M LOST target
        minimumReserve = 100000 * 10**18; // 100K LOST minimum
        rewardMultiplier = 10000; // 1x default
        
        _initializeRevenueStreams();
    }

    function _initializeRevenueStreams() private {
        revenueStreams["marketplace"] = RevenueStream("marketplace", 0, 0, true);
        revenueStreams["tournaments"] = RevenueStream("tournaments", 0, 0, true);
        revenueStreams["data_sales"] = RevenueStream("data_sales", 0, 0, true);
        revenueStreams["bridge_fees"] = RevenueStream("bridge_fees", 0, 0, true);
        revenueStreams["staking_fees"] = RevenueStream("staking_fees", 0, 0, true);
    }

    function collectRevenue(
        string memory source,
        uint256 amount,
        address token
    ) external nonReentrant {
        require(protocolContracts[msg.sender], "Not a protocol contract");
        require(approvedTokens[token], "Token not approved");
        require(revenueStreams[source].active, "Revenue stream not active");
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        revenueStreams[source].totalCollected += amount;
        revenueStreams[source].lastCollection = block.timestamp;
        totalRevenue += amount;
        
        // Apply burn mechanism
        uint256 burnAmount = (amount * burnRate) / 10000;
        if (burnAmount > 0 && token == lostTokenAddress) {
            _burnTokens(burnAmount);
            amount -= burnAmount;
        }
        
        // Allocate to funds
        _allocateFunds(amount);
        
        emit RevenueCollected(source, amount);
    }

    function _allocateFunds(uint256 amount) private {
        allocations.rewardPool += (amount * REWARD_POOL_PERCENTAGE) / 10000;
        allocations.developmentFund += (amount * DEVELOPMENT_PERCENTAGE) / 10000;
        allocations.marketingFund += (amount * MARKETING_PERCENTAGE) / 10000;
        allocations.liquidityFund += (amount * LIQUIDITY_PERCENTAGE) / 10000;
        allocations.stakingRewards += (amount * STAKING_PERCENTAGE) / 10000;
        allocations.ecosystemGrants += (amount * ECOSYSTEM_PERCENTAGE) / 10000;
        allocations.insuranceFund += (amount * INSURANCE_PERCENTAGE) / 10000;
        
        fundBalances["reward_pool"] += (amount * REWARD_POOL_PERCENTAGE) / 10000;
        fundBalances["development"] += (amount * DEVELOPMENT_PERCENTAGE) / 10000;
        fundBalances["marketing"] += (amount * MARKETING_PERCENTAGE) / 10000;
        fundBalances["liquidity"] += (amount * LIQUIDITY_PERCENTAGE) / 10000;
        fundBalances["staking"] += (amount * STAKING_PERCENTAGE) / 10000;
        fundBalances["ecosystem"] += (amount * ECOSYSTEM_PERCENTAGE) / 10000;
        fundBalances["insurance"] += (amount * INSURANCE_PERCENTAGE) / 10000;
    }

    function distributeFunds(
        address recipient,
        uint256 amount,
        string memory fund,
        string memory purpose
    ) external onlyRole(ALLOCATOR_ROLE) nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        require(fundBalances[fund] >= amount, "Insufficient fund balance");
        
        fundBalances[fund] -= amount;
        totalDistributed += amount;
        
        IERC20(lostTokenAddress).safeTransfer(recipient, amount);
        
        emit FundsDistributed(recipient, amount, purpose);
    }

    function createProposal(
        string memory title,
        string memory description,
        uint256 proposalType,
        uint256 amount,
        address recipient
    ) external onlyRole(TREASURER_ROLE) returns (uint256) {
        require(recipient != address(0), "Invalid recipient");
        require(amount >= MINIMUM_PROPOSAL_AMOUNT, "Amount below minimum");
        require(bytes(description).length > 0, "Description required");
        
        uint256 proposalId = nextProposalId++;
        
        proposals[proposalId] = FundingProposal({
            proposalId: proposalId,
            recipient: recipient,
            amount: amount,
            purpose: description,
            votesFor: 0,
            votesAgainst: 0,
            endTime: block.timestamp + PROPOSAL_DURATION,
            executed: false,
            cancelled: false
        });
        
        emit ProposalCreated(proposalId, recipient, amount);
        
        return proposalId;
    }

    function voteOnProposal(uint256 proposalId, bool support) external onlyRole(TREASURER_ROLE) {
        FundingProposal storage proposal = proposals[proposalId];
        require(block.timestamp < proposal.endTime, "Voting ended");
        require(!proposal.executed && !proposal.cancelled, "Proposal finalized");
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        
        hasVoted[proposalId][msg.sender] = true;
        
        if (support) {
            proposal.votesFor++;
        } else {
            proposal.votesAgainst++;
        }
    }

    function executeProposal(uint256 proposalId) external onlyRole(TREASURER_ROLE) nonReentrant {
        FundingProposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.endTime, "Voting not ended");
        require(!proposal.executed && !proposal.cancelled, "Already finalized");
        
        proposal.executed = true;
        
        bool approved = proposal.votesFor > proposal.votesAgainst;
        
        if (approved) {
            require(fundBalances["ecosystem"] >= proposal.amount, "Insufficient funds");
            fundBalances["ecosystem"] -= proposal.amount;
            IERC20(lostTokenAddress).safeTransfer(proposal.recipient, proposal.amount);
        }
        
        emit ProposalExecuted(proposalId, approved);
    }

    function provideLiquidity(uint256 amount) external onlyRole(TREASURER_ROLE) nonReentrant {
        require(amount > 0, "Invalid amount");
        require(fundBalances["liquidity"] >= amount, "Insufficient liquidity fund");
        
        fundBalances["liquidity"] -= amount;
        
        // Transfer to liquidity pool or DEX
        if (liquidityPoolAddress != address(0)) {
            IERC20(lostTokenAddress).safeTransfer(liquidityPoolAddress, amount);
        }
    }

    function _burnTokens(uint256 amount) private {
        IERC20(lostTokenAddress).transfer(address(0xdead), amount);
        totalBurned += amount;
        emit TokensBurned(amount);
    }

    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(amount > 0, "Invalid amount");
        
        // Ensure minimum reserve is maintained
        if (token == lostTokenAddress) {
            uint256 balance = IERC20(lostTokenAddress).balanceOf(address(this));
            require(balance - amount >= minimumReserve, "Would breach minimum reserve");
        }
        
        IERC20(token).safeTransfer(msg.sender, amount);
        
        emit EmergencyWithdrawal(token, amount);
    }

    function updateProtocolContract(address contractAddress, bool approved) external onlyRole(DEFAULT_ADMIN_ROLE) {
        protocolContracts[contractAddress] = approved;
        emit ProtocolContractUpdated(contractAddress, approved);
    }

    function updateBurnRate(uint256 newRate) external onlyRole(TREASURER_ROLE) {
        require(newRate <= 2000, "Burn rate too high"); // Max 20%
        burnRate = newRate;
    }

    function updateEconomicParameters(
        uint256 _targetLiquidity,
        uint256 _minimumReserve,
        uint256 _rewardMultiplier
    ) external onlyRole(TREASURER_ROLE) {
        targetLiquidity = _targetLiquidity;
        minimumReserve = _minimumReserve;
        rewardMultiplier = _rewardMultiplier;
    }

    function setLiquidityPoolAddress(address _liquidityPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        liquidityPoolAddress = _liquidityPool;
    }

    function approveToken(address token, bool approved) external onlyRole(DEFAULT_ADMIN_ROLE) {
        approvedTokens[token] = approved;
    }

    function getTreasuryBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function getAllocations() external view returns (Allocation memory) {
        return allocations;
    }

    function getFundBalance(string memory fund) external view returns (uint256) {
        return fundBalances[fund];
    }

    function getRevenueStream(string memory source) external view returns (RevenueStream memory) {
        return revenueStreams[source];
    }

    function getTreasuryStatistics() external view returns (
        uint256 revenue,
        uint256 distributed,
        uint256 burned,
        uint256 lostBalance,
        uint256 usdcBalance
    ) {
        return (
            totalRevenue,
            totalDistributed,
            totalBurned,
            IERC20(lostTokenAddress).balanceOf(address(this)),
            IERC20(usdcTokenAddress).balanceOf(address(this))
        );
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // Liquidity pool address storage
    address public liquidityPoolAddress;

    // ========== INTERFACE IMPLEMENTATIONS ==========
    
    
    /**
     * @dev Cast vote on a proposal
     */
    function castVote(uint256 proposalId, bool support) external {
        // This would integrate with governance contract
        emit VoteCast(proposalId, msg.sender, support);
    }
    
    
    /**
     * @dev Deposit tokens to treasury
     */
    function depositToTreasury(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        IERC20(lostTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        totalRevenue += amount;
        emit FundsReceived("deposit", amount, msg.sender);
    }
    
    /**
     * @dev Get treasury balance of LOST tokens
     */
    function getTreasuryBalance() external view returns (uint256) {
        return IERC20(lostTokenAddress).balanceOf(address(this));
    }
    
    /**
     * @dev Get user's share in treasury (for stakers/governance participants)
     */
    function getUserShare(address user) external view returns (uint256) {
        // This would calculate based on staking/governance participation
        // For now return 0 as placeholder
        return 0;
    }
    
    // Events for new functions
    event ProposalCreated(uint256 indexed proposalId, string title, uint256 amount, address target);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed proposalId);
    event FundsReceived(string source, uint256 amount, address from);
    
    // Counter for proposals
    uint256 private proposalCounter;
}