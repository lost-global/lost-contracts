// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IMarketplace {
    enum ListingType { DIRECT_SALE, AUCTION, RENTAL, FRACTIONAL }
    enum ListingStatus { ACTIVE, SOLD, CANCELLED, EXPIRED }
    enum AchievementRarity { COMMON, RARE, EPIC, LEGENDARY, MYTHIC }
    
    event ListingCreated(uint256 indexed listingId, address indexed seller, uint256 tokenId, uint256 price, ListingType listingType);
    event ListingSold(uint256 indexed listingId, address indexed buyer, uint256 price);
    event AuctionBid(uint256 indexed listingId, address indexed bidder, uint256 bidAmount);
    event RentalStarted(uint256 indexed tokenId, address indexed renter, uint256 duration, uint256 totalCost);
    event FractionalSharesPurchased(uint256 indexed tokenId, address indexed buyer, uint256 shares, uint256 totalCost);
    
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        ListingType listingType;
        ListingStatus status;
        uint256 price;
        bool isActive;
        uint256 createdAt;
        uint256 expiresAt;
        string ipfsHash;
        AchievementRarity rarity;
    }
    
    struct RentalTerms {
        uint256 dailyPrice;
        uint256 maxDuration;
        uint256 minDuration;
        uint256 collateral;
        address currentRenter;
        uint256 rentalStart;
        uint256 rentalEnd;
        bool isRented;
    }
    
    struct AuctionData {
        uint256 startingPrice;
        uint256 currentBid;
        address highestBidder;
        uint256 endTime;
        bool ended;
        uint256 bidIncrement;
    }
    
    struct FractionalData {
        uint256 totalShares;
        uint256 availableShares;
        uint256 pricePerShare;
        mapping(address => uint256) shareholderBalances;
    }
    
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
    
    function buyNFT(uint256 listingId) external payable;
    function placeBid(uint256 listingId, uint256 bidAmount) external payable;
    function endAuction(uint256 listingId) external;
    function rentNFT(uint256 listingId, uint256 rentalDays) external payable;
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