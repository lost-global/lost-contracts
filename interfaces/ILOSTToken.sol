// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ILOSTToken {
    function mint(address to, uint256 amount) external;
    function pause() external;
    function unpause() external;
    function snapshot() external returns (uint256);
    function getCurrentSnapshotId() external view returns (uint256);
    function balanceOfAt(address account, uint256 snapshotId) external view returns (uint256);
    function totalSupplyAt(uint256 snapshotId) external view returns (uint256);
}