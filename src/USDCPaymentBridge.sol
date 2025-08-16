// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../interfaces/IPaymentBridge.sol";

/**
 * @title USDCPaymentBridge
 * @dev Bridge for USDC payments and withdrawals in LOST Protocol
 * Features:
 * - USDC withdrawal to player wallets
 * - Payment channels for instant transactions
 * - Cross-chain bridge integration
 * - Automatic conversion between LOST and USDC
 * - Anti-money laundering compliance
 */
contract USDCPaymentBridge is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IPaymentBridge
{
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    bytes32 public constant BRIDGE_OPERATOR_ROLE = keccak256("BRIDGE_OPERATOR_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Core addresses
    address public usdcTokenAddress;
    address public lostTokenAddress;
    address public treasuryAddress;
    address public liquidityPoolAddress;

    // Withdrawal tracking
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;
    mapping(address => uint256[]) public userWithdrawals;
    mapping(address => uint256) public pendingWithdrawalAmount;
    uint256 public nextWithdrawalId;

    // Payment channels
    mapping(bytes32 => PaymentChannel) public paymentChannels;
    mapping(address => bytes32[]) public userChannels;
    mapping(bytes32 => mapping(uint256 => bool)) public usedNonces;

    // Exchange rates and limits
    uint256 public lostToUsdcRate; // Rate with 6 decimals (1 USDC = 1000000)
    uint256 public minWithdrawalAmount;
    uint256 public maxWithdrawalAmount;
    uint256 public dailyWithdrawalLimit;
    mapping(address => uint256) public dailyWithdrawn;
    mapping(address => uint256) public lastWithdrawalDay;

    // Compliance
    mapping(address => bool) public kycVerified;
    mapping(address => bool) public blacklisted;
    mapping(address => uint256) public userTier; // 0: basic, 1: verified, 2: premium

    // Bridge fees
    uint256 public withdrawalFeePercentage; // Basis points
    uint256 public channelFeePercentage; // Basis points
    uint256 public totalFeesCollected;

    // Statistics
    uint256 public totalWithdrawn;
    uint256 public totalBridged;
    uint256 public activeChannels;

    uint256 public constant RATE_DECIMALS = 1000000; // 6 decimals for USDC
    uint256 public constant MAX_CHANNEL_DURATION = 30 days;
    uint256 public constant CHANNEL_DISPUTE_PERIOD = 1 days;

    event ExchangeRateUpdated(uint256 oldRate, uint256 newRate);
    event KYCStatusUpdated(address indexed user, bool verified);
    event WithdrawalProcessed(uint256 indexed requestId, address indexed user, uint256 amount);
    event ChannelDisputed(bytes32 indexed channelId, address disputer);
    event ComplianceAction(address indexed user, string action, string reason);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address _usdcTokenAddress,
        address _lostTokenAddress,
        address _treasuryAddress
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_OPERATOR_ROLE, admin);
        _grantRole(COMPLIANCE_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        
        usdcTokenAddress = _usdcTokenAddress;
        lostTokenAddress = _lostTokenAddress;
        treasuryAddress = _treasuryAddress;
        
        nextWithdrawalId = 1;
        lostToUsdcRate = 100000; // Initial rate: 1 LOST = 0.10 USDC
        minWithdrawalAmount = 10 * RATE_DECIMALS; // 10 USDC minimum
        maxWithdrawalAmount = 10000 * RATE_DECIMALS; // 10,000 USDC maximum
        dailyWithdrawalLimit = 50000 * RATE_DECIMALS; // 50,000 USDC daily limit
        withdrawalFeePercentage = 100; // 1% fee
        channelFeePercentage = 50; // 0.5% fee
    }

    function requestWithdrawal(
        uint256 amount,
        address token
    ) external whenNotPaused nonReentrant returns (uint256) {
        require(!blacklisted[msg.sender], "User blacklisted");
        require(kycVerified[msg.sender], "KYC not verified");
        require(amount >= minWithdrawalAmount, "Below minimum withdrawal");
        require(amount <= maxWithdrawalAmount, "Exceeds maximum withdrawal");
        require(token == usdcTokenAddress || token == lostTokenAddress, "Invalid token");
        
        // Check daily limit
        uint256 currentDay = block.timestamp / 1 days;
        if (lastWithdrawalDay[msg.sender] < currentDay) {
            dailyWithdrawn[msg.sender] = 0;
            lastWithdrawalDay[msg.sender] = currentDay;
        }
        require(dailyWithdrawn[msg.sender] + amount <= dailyWithdrawalLimit, "Exceeds daily limit");
        
        uint256 requestId = nextWithdrawalId++;
        
        // Convert LOST to USDC if needed
        uint256 usdcAmount = amount;
        if (token == lostTokenAddress) {
            usdcAmount = (amount * lostToUsdcRate) / (10**18 * RATE_DECIMALS / RATE_DECIMALS);
            IERC20(lostTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        } else {
            IERC20(usdcTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        }
        
        // Apply withdrawal fee
        uint256 fee = (usdcAmount * withdrawalFeePercentage) / 10000;
        uint256 netAmount = usdcAmount - fee;
        
        withdrawalRequests[requestId] = WithdrawalRequest({
            requestId: requestId,
            player: msg.sender,
            amount: netAmount,
            token: usdcTokenAddress,
            timestamp: block.timestamp,
            status: WithdrawalStatus.PENDING,
            txHash: bytes32(0)
        });
        
        userWithdrawals[msg.sender].push(requestId);
        pendingWithdrawalAmount[msg.sender] += netAmount;
        dailyWithdrawn[msg.sender] += amount;
        totalFeesCollected += fee;
        
        emit WithdrawalRequested(requestId, msg.sender, netAmount, usdcTokenAddress);
        
        return requestId;
    }

    function processWithdrawal(uint256 requestId) external onlyRole(BRIDGE_OPERATOR_ROLE) nonReentrant {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        require(request.status == WithdrawalStatus.PENDING, "Invalid withdrawal status");
        require(!blacklisted[request.player], "User blacklisted");
        
        request.status = WithdrawalStatus.PROCESSING;
        
        // Check liquidity
        uint256 availableBalance = IERC20(usdcTokenAddress).balanceOf(address(this));
        require(availableBalance >= request.amount, "Insufficient liquidity");
        
        // Process withdrawal
        IERC20(usdcTokenAddress).safeTransfer(request.player, request.amount);
        
        request.status = WithdrawalStatus.COMPLETED;
        request.txHash = keccak256(abi.encodePacked(requestId, request.player, request.amount, block.timestamp));
        
        pendingWithdrawalAmount[request.player] -= request.amount;
        totalWithdrawn += request.amount;
        
        emit WithdrawalCompleted(requestId, request.player, request.amount, request.txHash);
        emit WithdrawalProcessed(requestId, request.player, request.amount);
    }

    function cancelWithdrawal(uint256 requestId) external nonReentrant {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        require(request.player == msg.sender || hasRole(BRIDGE_OPERATOR_ROLE, msg.sender), "Not authorized");
        require(request.status == WithdrawalStatus.PENDING, "Cannot cancel");
        
        request.status = WithdrawalStatus.CANCELLED;
        
        // Refund the withdrawal amount
        if (request.token == lostTokenAddress) {
            uint256 lostAmount = (request.amount * 10**18 * RATE_DECIMALS) / (lostToUsdcRate * RATE_DECIMALS);
            IERC20(lostTokenAddress).safeTransfer(request.player, lostAmount);
        } else {
            IERC20(usdcTokenAddress).safeTransfer(request.player, request.amount);
        }
        
        pendingWithdrawalAmount[request.player] -= request.amount;
    }

    function bridgeUSDC(
        address recipient,
        uint256 amount,
        PaymentType paymentType
    ) external onlyRole(BRIDGE_OPERATOR_ROLE) nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(!blacklisted[recipient], "Recipient blacklisted");
        
        IERC20(usdcTokenAddress).safeTransferFrom(msg.sender, recipient, amount);
        totalBridged += amount;
        
        emit USDCBridged(msg.sender, recipient, amount, paymentType);
    }

    function openPaymentChannel(
        address participant,
        uint256 deposit
    ) external whenNotPaused nonReentrant returns (bytes32) {
        require(participant != address(0) && participant != msg.sender, "Invalid participant");
        require(deposit > 0, "Invalid deposit");
        require(kycVerified[msg.sender] && kycVerified[participant], "KYC required");
        
        bytes32 channelId = keccak256(abi.encodePacked(msg.sender, participant, block.timestamp));
        require(paymentChannels[channelId].participant1 == address(0), "Channel exists");
        
        IERC20(usdcTokenAddress).safeTransferFrom(msg.sender, address(this), deposit);
        
        paymentChannels[channelId] = PaymentChannel({
            participant1: msg.sender,
            participant2: participant,
            balance1: deposit,
            balance2: 0,
            nonce: 0,
            isOpen: true
        });
        
        userChannels[msg.sender].push(channelId);
        userChannels[participant].push(channelId);
        activeChannels++;
        
        emit PaymentChannelOpened(channelId, msg.sender, participant, deposit);
        
        return channelId;
    }

    function updateChannel(
        bytes32 channelId,
        uint256 balance1,
        uint256 balance2,
        uint256 nonce,
        bytes memory signature1,
        bytes memory signature2
    ) external nonReentrant {
        PaymentChannel storage channel = paymentChannels[channelId];
        require(channel.isOpen, "Channel closed");
        require(nonce > channel.nonce, "Invalid nonce");
        require(!usedNonces[channelId][nonce], "Nonce already used");
        
        bytes32 messageHash = keccak256(abi.encodePacked(channelId, balance1, balance2, nonce));
        
        address signer1 = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature1);
        address signer2 = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature2);
        
        require(
            (signer1 == channel.participant1 && signer2 == channel.participant2) ||
            (signer1 == channel.participant2 && signer2 == channel.participant1),
            "Invalid signatures"
        );
        
        uint256 totalBalance = channel.balance1 + channel.balance2;
        require(balance1 + balance2 == totalBalance, "Balance mismatch");
        
        channel.balance1 = balance1;
        channel.balance2 = balance2;
        channel.nonce = nonce;
        usedNonces[channelId][nonce] = true;
    }

    function closeChannel(bytes32 channelId) external nonReentrant {
        PaymentChannel storage channel = paymentChannels[channelId];
        require(channel.isOpen, "Channel already closed");
        require(
            msg.sender == channel.participant1 || msg.sender == channel.participant2,
            "Not a participant"
        );
        
        channel.isOpen = false;
        activeChannels--;
        
        // Apply channel fees
        uint256 fee1 = (channel.balance1 * channelFeePercentage) / 10000;
        uint256 fee2 = (channel.balance2 * channelFeePercentage) / 10000;
        
        uint256 payout1 = channel.balance1 - fee1;
        uint256 payout2 = channel.balance2 - fee2;
        
        if (payout1 > 0) {
            IERC20(usdcTokenAddress).safeTransfer(channel.participant1, payout1);
        }
        if (payout2 > 0) {
            IERC20(usdcTokenAddress).safeTransfer(channel.participant2, payout2);
        }
        
        totalFeesCollected += fee1 + fee2;
        
        emit PaymentChannelClosed(channelId, payout1, payout2);
    }

    function updateKYCStatus(address user, bool verified) external onlyRole(COMPLIANCE_ROLE) {
        kycVerified[user] = verified;
        if (verified) {
            userTier[user] = 1;
        } else {
            userTier[user] = 0;
        }
        emit KYCStatusUpdated(user, verified);
    }

    function blacklistUser(address user, string memory reason) external onlyRole(COMPLIANCE_ROLE) {
        blacklisted[user] = true;
        emit ComplianceAction(user, "BLACKLISTED", reason);
    }

    function unblacklistUser(address user, string memory reason) external onlyRole(COMPLIANCE_ROLE) {
        blacklisted[user] = false;
        emit ComplianceAction(user, "UNBLACKLISTED", reason);
    }

    function updateExchangeRate(uint256 newRate) external onlyRole(BRIDGE_OPERATOR_ROLE) {
        require(newRate > 0, "Invalid rate");
        uint256 oldRate = lostToUsdcRate;
        lostToUsdcRate = newRate;
        emit ExchangeRateUpdated(oldRate, newRate);
    }

    function updateWithdrawalLimits(
        uint256 _minAmount,
        uint256 _maxAmount,
        uint256 _dailyLimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minWithdrawalAmount = _minAmount;
        maxWithdrawalAmount = _maxAmount;
        dailyWithdrawalLimit = _dailyLimit;
    }

    function updateFees(
        uint256 _withdrawalFee,
        uint256 _channelFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_withdrawalFee <= 500, "Withdrawal fee too high"); // Max 5%
        require(_channelFee <= 200, "Channel fee too high"); // Max 2%
        withdrawalFeePercentage = _withdrawalFee;
        channelFeePercentage = _channelFee;
    }

    function withdrawCollectedFees() external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(treasuryAddress != address(0), "Treasury not set");
        uint256 fees = totalFeesCollected;
        totalFeesCollected = 0;
        IERC20(usdcTokenAddress).safeTransfer(treasuryAddress, fees);
    }

    function addLiquidity(uint256 amount) external onlyRole(BRIDGE_OPERATOR_ROLE) {
        IERC20(usdcTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
    }

    function removeLiquidity(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 reserveAmount = pendingWithdrawalAmount[address(0)];
        uint256 availableBalance = IERC20(usdcTokenAddress).balanceOf(address(this));
        require(availableBalance - amount >= reserveAmount, "Insufficient liquidity");
        IERC20(usdcTokenAddress).safeTransfer(treasuryAddress, amount);
    }

    function getWithdrawalStatus(uint256 requestId) external view returns (WithdrawalStatus) {
        return withdrawalRequests[requestId].status;
    }

    function getPendingWithdrawals(address player) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < userWithdrawals[player].length; i++) {
            if (withdrawalRequests[userWithdrawals[player][i]].status == WithdrawalStatus.PENDING) {
                count++;
            }
        }
        
        uint256[] memory pending = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < userWithdrawals[player].length; i++) {
            uint256 requestId = userWithdrawals[player][i];
            if (withdrawalRequests[requestId].status == WithdrawalStatus.PENDING) {
                pending[index++] = requestId;
            }
        }
        
        return pending;
    }

    function getUserChannels(address user) external view returns (bytes32[] memory) {
        return userChannels[user];
    }

    function getBridgeStatistics() external view returns (
        uint256 withdrawn,
        uint256 bridged,
        uint256 channels,
        uint256 feesCollected,
        uint256 currentRate
    ) {
        return (totalWithdrawn, totalBridged, activeChannels, totalFeesCollected, lostToUsdcRate);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}