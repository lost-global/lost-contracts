// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ITreasury {
    function createProposal(
        string memory title,
        string memory description,
        uint256 proposalType,
        uint256 amount,
        address recipient
    ) external returns (uint256);
    
    function castVote(uint256 proposalId, bool support) external;
    function executeProposal(uint256 proposalId) external;
    function depositToTreasury(uint256 amount) external;
    function getTreasuryBalance() external view returns (uint256);
    function getUserShare(address user) external view returns (uint256);
}