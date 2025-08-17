// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IMarketplace {
    enum ListingType { DIRECT_SALE, AUCTION, RENTAL }
    enum AchievementRarity { COMMON, RARE, EPIC, LEGENDARY, MYTHIC }
    
    function listForSale(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        string memory ipfsHash,
        AchievementRarity rarity
    ) external returns (uint256);
    
    function listForAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startingPrice,
        uint256 duration,
        string memory ipfsHash,
        AchievementRarity rarity
    ) external returns (uint256);
    
    function listForRental(
        address nftContract,
        uint256 tokenId,
        uint256 dailyPrice,
        string memory ipfsHash,
        AchievementRarity rarity
    ) external returns (uint256);
    
    function buyNFT(uint256 listingId) external;
    function placeBid(uint256 listingId, uint256 bidAmount) external;
    function endAuction(uint256 listingId) external;
    function rentNFT(uint256 listingId, uint256 rentalDays) external;
    function endRental(uint256 rentalId) external;
    function cancelListing(uint256 listingId) external;
    
    function getListing(uint256 listingId) external view returns (
        address seller,
        uint256 tokenId,
        ListingType listingType,
        uint256 price,
        bool isActive,
        string memory ipfsHash
    );
}