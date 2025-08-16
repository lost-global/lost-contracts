// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPaymentBridge
 * @dev Interface for USDC payment bridge and withdrawals
 */
interface IPaymentBridge {
    struct WithdrawalRequest {
        uint256 requestId;
        address player;
        uint256 amount;
        address token;
        uint256 timestamp;
        WithdrawalStatus status;
        bytes32 txHash;
    }

    struct PaymentChannel {
        address participant1;
        address participant2;
        uint256 balance1;
        uint256 balance2;
        uint256 nonce;
        bool isOpen;
    }

    enum WithdrawalStatus {
        PENDING,
        PROCESSING,
        COMPLETED,
        FAILED,
        CANCELLED
    }

    enum PaymentType {
        REWARD,
        PRIZE,
        REFUND,
        PURCHASE,
        STAKE_RETURN
    }

    event WithdrawalRequested(
        uint256 indexed requestId,
        address indexed player,
        uint256 amount,
        address token
    );

    event WithdrawalCompleted(
        uint256 indexed requestId,
        address indexed player,
        uint256 amount,
        bytes32 txHash
    );

    event PaymentChannelOpened(
        bytes32 indexed channelId,
        address indexed participant1,
        address indexed participant2,
        uint256 initialDeposit
    );

    event PaymentChannelClosed(
        bytes32 indexed channelId,
        uint256 finalBalance1,
        uint256 finalBalance2
    );

    event USDCBridged(
        address indexed from,
        address indexed to,
        uint256 amount,
        PaymentType paymentType
    );

    function requestWithdrawal(
        uint256 amount,
        address token
    ) external returns (uint256 requestId);

    function processWithdrawal(uint256 requestId) external;

    function cancelWithdrawal(uint256 requestId) external;

    function bridgeUSDC(
        address recipient,
        uint256 amount,
        PaymentType paymentType
    ) external;

    function openPaymentChannel(
        address participant,
        uint256 deposit
    ) external returns (bytes32 channelId);

    function updateChannel(
        bytes32 channelId,
        uint256 balance1,
        uint256 balance2,
        uint256 nonce,
        bytes memory signature1,
        bytes memory signature2
    ) external;

    function closeChannel(bytes32 channelId) external;

    function getWithdrawalStatus(uint256 requestId) external view returns (WithdrawalStatus);

    function getPendingWithdrawals(address player) external view returns (uint256[] memory);
}