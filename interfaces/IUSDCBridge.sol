// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IUSDCBridge {
    function openChannel(uint256 amount, uint256 duration) external returns (bytes32);
    function closeChannel(bytes32 channelId, uint256 finalAmount, uint256 nonce, bytes memory signature) external;
    function withdrawUSDC(uint256 amount, address recipient) external;
    function convertLOSTToUSDC(uint256 lostAmount) external;
    function addLiquidity(uint256 amount) external;
    function getWithdrawableBalance(address user) external view returns (uint256);
    function getRemainingDailyLimit(address user) external view returns (uint256);
}