// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IStaking.sol";

/**
 * @title Staking
 * @dev LOST token staking contract with governance voting power
 * Features:
 * - Lock tokens for leaderboard voting power
 * - Tiered staking with different lock periods
 * - Penalty-free emergency unstaking with slashing
 * - Governance voting with stake-weighted power
 * - Reward distribution from protocol fees
 * - Delegation mechanism for voting power
 */
contract Staking is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IStaking
{
    using SafeERC20 for IERC20;

    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    bytes32 public constant REWARDS_DISTRIBUTOR_ROLE = keccak256("REWARDS_DISTRIBUTOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    enum StakingTier {
        BRONZE,   // 30 days lock
        SILVER,   // 90 days lock
        GOLD,     // 180 days lock
        PLATINUM, // 365 days lock
        DIAMOND   // 730 days lock
    }

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        StakingTier tier;
        uint256 votingPower;
        uint256 rewardDebt;
        bool active;
    }

    struct UserStaking {
        mapping(uint256 => StakeInfo) stakes;
        uint256 stakeCount;
        uint256 totalStaked;
        uint256 totalVotingPower;
        address delegate;
        uint256 pendingRewards;
    }

    struct GovernanceProposal {
        uint256 proposalId;
        address proposer;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        bool cancelled;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) voteWeights;
    }

    struct TierConfig {
        uint256 lockDuration;
        uint256 votingMultiplier;  // Multiplier for voting power (basis points)
        uint256 rewardMultiplier;  // Multiplier for rewards (basis points)
        uint256 minStakeAmount;
        uint256 slashingPenalty;   // Penalty for early unstaking (basis points)
    }

    // Core addresses
    address public lostTokenAddress;
    address public treasuryAddress;
    
    // Staking data
    mapping(address => UserStaking) private userStaking;
    mapping(address => mapping(address => uint256)) public delegatedVotingPower;
    
    // Governance
    mapping(uint256 => GovernanceProposal) public proposals;
    uint256 public nextProposalId;
    uint256 public proposalThreshold; // Minimum voting power needed to create proposal
    uint256 public votingDuration;
    
    // Tier configurations
    mapping(StakingTier => TierConfig) public tierConfigs;
    
    // Rewards
    uint256 public accRewardPerShare;
    uint256 public totalRewardsDistributed;
    uint256 public lastRewardBlock;
    uint256 public rewardRate; // Rewards per block
    
    // Statistics
    uint256 public totalStaked;
    uint256 public totalVotingPower;
    uint256 public totalStakers;
    uint256 public totalSlashed;
    
    // Emergency controls
    bool public emergencyWithdrawEnabled;
    uint256 public emergencySlashingRate; // Basis points

    uint256 public constant PRECISION = 1e18;
    uint256 public constant GOVERNANCE_QUORUM = 2000; // 20% of total voting power needed
    uint256 public constant PROPOSAL_DURATION = 7 days;

    event TokensStaked(
        address indexed user,
        uint256 indexed stakeId,
        uint256 amount,
        StakingTier tier,
        uint256 lockDuration
    );
    
    event TokensUnstaked(
        address indexed user,
        uint256 indexed stakeId,
        uint256 amount,
        uint256 penalty
    );
    
    event VotingPowerDelegated(
        address indexed delegator,
        address indexed delegate,
        uint256 votingPower
    );
    
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description
    );
    
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 weight
    );
    
    event RewardsDistributed(uint256 amount, uint256 newAccRewardPerShare);
    event RewardsClaimed(address indexed user, uint256 amount);
    event EmergencyUnstaked(address indexed user, uint256 amount, uint256 penalty);

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
        _grantRole(STAKING_MANAGER_ROLE, admin);
        _grantRole(REWARDS_DISTRIBUTOR_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        
        lostTokenAddress = _lostTokenAddress;
        treasuryAddress = _treasuryAddress;
        
        nextProposalId = 1;
        proposalThreshold = 10000 * 10**18; // 10,000 LOST needed to propose
        votingDuration = PROPOSAL_DURATION;
        rewardRate = 1 * 10**18; // 1 LOST per block default
        emergencySlashingRate = 5000; // 50% penalty for emergency withdrawal
        
        _initializeTierConfigs();
    }

    function _initializeTierConfigs() private {
        tierConfigs[StakingTier.BRONZE] = TierConfig({
            lockDuration: 30 days,
            votingMultiplier: 10000,  // 1x voting power
            rewardMultiplier: 10000,  // 1x rewards
            minStakeAmount: 100 * 10**18, // 100 LOST minimum
            slashingPenalty: 1000     // 10% penalty
        });
        
        tierConfigs[StakingTier.SILVER] = TierConfig({
            lockDuration: 90 days,
            votingMultiplier: 12500,  // 1.25x voting power
            rewardMultiplier: 12500,  // 1.25x rewards
            minStakeAmount: 500 * 10**18, // 500 LOST minimum
            slashingPenalty: 800      // 8% penalty
        });
        
        tierConfigs[StakingTier.GOLD] = TierConfig({
            lockDuration: 180 days,
            votingMultiplier: 15000,  // 1.5x voting power
            rewardMultiplier: 15000,  // 1.5x rewards
            minStakeAmount: 1000 * 10**18, // 1,000 LOST minimum
            slashingPenalty: 600      // 6% penalty
        });
        
        tierConfigs[StakingTier.PLATINUM] = TierConfig({
            lockDuration: 365 days,
            votingMultiplier: 20000,  // 2x voting power
            rewardMultiplier: 20000,  // 2x rewards
            minStakeAmount: 5000 * 10**18, // 5,000 LOST minimum
            slashingPenalty: 400      // 4% penalty
        });
        
        tierConfigs[StakingTier.DIAMOND] = TierConfig({
            lockDuration: 730 days,
            votingMultiplier: 30000,  // 3x voting power
            rewardMultiplier: 30000,  // 3x rewards
            minStakeAmount: 10000 * 10**18, // 10,000 LOST minimum
            slashingPenalty: 200      // 2% penalty
        });
    }

    function _stakeInternal(uint256 amount, StakingTier tier) internal {
        require(amount > 0, "Invalid amount");
        TierConfig memory config = tierConfigs[tier];
        require(amount >= config.minStakeAmount, "Below minimum stake");
        
        _updateRewards();
        UserStaking storage user = userStaking[msg.sender];
        
        // Calculate voting power
        uint256 votingPower = (amount * config.votingMultiplier) / 10000;
        
        // Create stake record
        uint256 stakeId = user.stakeCount++;
        StakeInfo storage stakeInfo = user.stakes[stakeId];
        stakeInfo.amount = amount;
        stakeInfo.startTime = block.timestamp;
        stakeInfo.endTime = block.timestamp + config.lockDuration;
        stakeInfo.tier = tier;
        stakeInfo.votingPower = votingPower;
        stakeInfo.rewardDebt = (amount * accRewardPerShare) / PRECISION;
        stakeInfo.active = true;
        
        // Update user stats
        if (user.totalStaked == 0) {
            totalStakers++;
        }
        user.totalStaked += amount;
        user.totalVotingPower += votingPower;
        
        // Update global stats
        totalStaked += amount;
        totalVotingPower += votingPower;
        
        // Transfer tokens
        IERC20(lostTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        
        emit TokensStaked(msg.sender, stakeId, amount, tier, config.lockDuration);
    }

    function unstake(uint256 stakeId) external nonReentrant {
        UserStaking storage user = userStaking[msg.sender];
        StakeInfo storage stakeInfo = user.stakes[stakeId];
        
        require(stakeInfo.active, "Stake not active");
        require(block.timestamp >= stakeInfo.endTime, "Lock period not ended");
        
        _updateRewards();
        
        uint256 amount = stakeInfo.amount;
        uint256 votingPower = stakeInfo.votingPower;
        
        // Calculate pending rewards
        uint256 pendingReward = ((amount * accRewardPerShare) / PRECISION) - stakeInfo.rewardDebt;
        
        // Update user stats
        user.totalStaked -= amount;
        user.totalVotingPower -= votingPower;
        user.pendingRewards += pendingReward;
        
        if (user.totalStaked == 0) {
            totalStakers--;
        }
        
        // Update global stats
        totalStaked -= amount;
        totalVotingPower -= votingPower;
        
        // Deactivate stake
        stakeInfo.active = false;
        
        // Transfer tokens back
        IERC20(lostTokenAddress).safeTransfer(msg.sender, amount);
        
        emit TokensUnstaked(msg.sender, stakeId, amount, 0);
    }

    function emergencyUnstake(uint256 stakeId) external nonReentrant {
        require(emergencyWithdrawEnabled, "Emergency withdraw disabled");
        
        UserStaking storage user = userStaking[msg.sender];
        StakeInfo storage stakeInfo = user.stakes[stakeId];
        
        require(stakeInfo.active, "Stake not active");
        
        _updateRewards();
        
        uint256 amount = stakeInfo.amount;
        uint256 votingPower = stakeInfo.votingPower;
        TierConfig memory config = tierConfigs[stakeInfo.tier];
        
        // Calculate penalty
        uint256 penalty = (amount * config.slashingPenalty) / 10000;
        uint256 withdrawAmount = amount - penalty;
        
        // Update user stats
        user.totalStaked -= amount;
        user.totalVotingPower -= votingPower;
        
        if (user.totalStaked == 0) {
            totalStakers--;
        }
        
        // Update global stats
        totalStaked -= amount;
        totalVotingPower -= votingPower;
        totalSlashed += penalty;
        
        // Deactivate stake
        stakeInfo.active = false;
        
        // Transfer slashed tokens to treasury
        if (penalty > 0) {
            IERC20(lostTokenAddress).safeTransfer(treasuryAddress, penalty);
        }
        
        // Transfer remaining tokens to user
        IERC20(lostTokenAddress).safeTransfer(msg.sender, withdrawAmount);
        
        emit EmergencyUnstaked(msg.sender, withdrawAmount, penalty);
    }

    function claimRewards() external nonReentrant {
        _updateRewards();
        UserStaking storage user = userStaking[msg.sender];
        
        uint256 totalRewards = user.pendingRewards;
        
        // Calculate rewards from active stakes
        for (uint256 i = 0; i < user.stakeCount; i++) {
            StakeInfo storage stakeInfo = user.stakes[i];
            if (stakeInfo.active) {
                uint256 pendingReward = ((stakeInfo.amount * accRewardPerShare) / PRECISION) - stakeInfo.rewardDebt;
                totalRewards += pendingReward;
                stakeInfo.rewardDebt = (stakeInfo.amount * accRewardPerShare) / PRECISION;
            }
        }
        
        if (totalRewards > 0) {
            user.pendingRewards = 0;
            IERC20(lostTokenAddress).safeTransfer(msg.sender, totalRewards);
            emit RewardsClaimed(msg.sender, totalRewards);
        }
    }

    function delegateVotingPower(address delegate) external {
        require(delegate != address(0) && delegate != msg.sender, "Invalid delegate");
        
        UserStaking storage user = userStaking[msg.sender];
        address oldDelegate = user.delegate;
        
        // Remove from old delegate
        if (oldDelegate != address(0)) {
            delegatedVotingPower[oldDelegate][msg.sender] = 0;
        }
        
        // Add to new delegate
        user.delegate = delegate;
        delegatedVotingPower[delegate][msg.sender] = user.totalVotingPower;
        
        emit VotingPowerDelegated(msg.sender, delegate, user.totalVotingPower);
    }

    function createProposal(string memory description) external returns (uint256) {
        uint256 userVotingPower = getUserVotingPower(msg.sender);
        require(userVotingPower >= proposalThreshold, "Insufficient voting power");
        require(bytes(description).length > 0, "Description required");
        
        uint256 proposalId = nextProposalId++;
        
        GovernanceProposal storage proposal = proposals[proposalId];
        proposal.proposalId = proposalId;
        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + votingDuration;
        
        emit ProposalCreated(proposalId, msg.sender, description);
        
        return proposalId;
    }

    function vote(uint256 proposalId, bool support) external {
        GovernanceProposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.startTime, "Voting not started");
        require(block.timestamp < proposal.endTime, "Voting ended");
        require(!proposal.executed && !proposal.cancelled, "Proposal finalized");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        
        uint256 votingPower = getUserVotingPower(msg.sender);
        require(votingPower > 0, "No voting power");
        
        proposal.hasVoted[msg.sender] = true;
        proposal.voteWeights[msg.sender] = votingPower;
        
        if (support) {
            proposal.votesFor += votingPower;
        } else {
            proposal.votesAgainst += votingPower;
        }
        
        emit VoteCast(proposalId, msg.sender, support, votingPower);
    }

    function executeProposal(uint256 proposalId) external onlyRole(STAKING_MANAGER_ROLE) {
        GovernanceProposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.endTime, "Voting not ended");
        require(!proposal.executed && !proposal.cancelled, "Already finalized");
        
        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        uint256 requiredQuorum = (totalVotingPower * GOVERNANCE_QUORUM) / 10000;
        
        require(totalVotes >= requiredQuorum, "Quorum not met");
        
        proposal.executed = true;
        
        // Implementation would depend on proposal type
        // For now, just mark as executed
    }

    function distributeRewards(uint256 amount) external onlyRole(REWARDS_DISTRIBUTOR_ROLE) {
        require(amount > 0, "Invalid amount");
        require(totalStaked > 0, "No stakes to reward");
        
        IERC20(lostTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        
        accRewardPerShare += (amount * PRECISION) / totalStaked;
        totalRewardsDistributed += amount;
        
        emit RewardsDistributed(amount, accRewardPerShare);
    }

    function _updateRewards() private {
        if (block.number <= lastRewardBlock || totalStaked == 0) {
            return;
        }
        
        uint256 blocks = block.number - lastRewardBlock;
        uint256 rewards = blocks * rewardRate;
        
        if (rewards > 0) {
            accRewardPerShare += (rewards * PRECISION) / totalStaked;
        }
        
        lastRewardBlock = block.number;
    }

    function getUserVotingPower(address user) public view returns (uint256) {
        UserStaking storage userInfo = userStaking[user];
        uint256 totalPower = userInfo.totalVotingPower;
        
        // Add delegated voting power
        // This would require tracking all delegators, simplified for now
        
        return totalPower;
    }

    function getUserStakeInfo(address user, uint256 stakeId) external view returns (StakeInfo memory) {
        return userStaking[user].stakes[stakeId];
    }

    function getUserStakingStats(address user) external view returns (
        uint256 totalStaked_,
        uint256 totalVotingPower_,
        uint256 stakeCount_,
        uint256 pendingRewards_
    ) {
        UserStaking storage userInfo = userStaking[user];
        return (
            userInfo.totalStaked,
            userInfo.totalVotingPower,
            userInfo.stakeCount,
            userInfo.pendingRewards
        );
    }

    function getGlobalStats() external view returns (
        uint256 totalStaked_,
        uint256 totalVotingPower_,
        uint256 totalStakers_,
        uint256 totalRewardsDistributed_,
        uint256 totalSlashed_
    ) {
        return (totalStaked, totalVotingPower, totalStakers, totalRewardsDistributed, totalSlashed);
    }

    function updateTierConfig(
        StakingTier tier,
        uint256 lockDuration,
        uint256 votingMultiplier,
        uint256 rewardMultiplier,
        uint256 minStakeAmount,
        uint256 slashingPenalty
    ) external onlyRole(STAKING_MANAGER_ROLE) {
        tierConfigs[tier] = TierConfig({
            lockDuration: lockDuration,
            votingMultiplier: votingMultiplier,
            rewardMultiplier: rewardMultiplier,
            minStakeAmount: minStakeAmount,
            slashingPenalty: slashingPenalty
        });
    }

    function setEmergencyWithdraw(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emergencyWithdrawEnabled = enabled;
    }

    function updateRewardRate(uint256 newRate) external onlyRole(STAKING_MANAGER_ROLE) {
        _updateRewards();
        rewardRate = newRate;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    // Interface implementations for IStaking
    function getVotingPower(address user) external view returns (uint256) {
        return userStaking[user].totalVotingPower;
    }
    
    function getTotalVotingPower() external view returns (uint256) {
        return totalVotingPower;
    }
    
    // Wrapper function to match interface signature
    function stake(uint256 amount, uint256 tier) external whenNotPaused nonReentrant {
        _stakeInternal(amount, StakingTier(tier));
    }
    
    // Overloaded function with StakingTier enum
    function stake(uint256 amount, StakingTier tier) external whenNotPaused nonReentrant {
        _stakeInternal(amount, tier);
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}