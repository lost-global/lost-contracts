// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IStaking {
    function getVotingPower(address user) external view returns (uint256);
    function getTotalVotingPower() external view returns (uint256);
    function stake(uint256 amount, uint256 tier) external;
    function unstake(uint256 stakeId) external;
    function claimRewards() external;
}