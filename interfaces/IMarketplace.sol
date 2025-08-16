// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMarketplace
 * @dev Interface for NFT marketplace functionality
 */
interface IMarketplace {
    enum ListingType {
        SALE,
        RENT,
        AUCTION,
        FRACTIONAL
    }

    enum ListingStatus {
        ACTIVE,
        SOLD,
        CANCELLED,
        EXPIRED
    }

    struct Listing {
        uint256 listingId;
        address seller;
        uint256 tokenId;
        uint256 price;
        ListingType listingType;
        ListingStatus status;
        uint256 startTime;
        uint256 endTime;
        address buyer;
    }

    struct RentalTerms {
        uint256 dailyRate;
        uint256 minDuration;
        uint256 maxDuration;
        uint256 collateral;
    }

    struct AuctionData {
        uint256 startingBid;
        uint256 currentBid;
        address highestBidder;
        uint256 bidIncrement;
        uint256 endTime;
    }

    struct FractionalData {
        uint256 totalShares;
        uint256 availableShares;
        uint256 pricePerShare;
        mapping(address => uint256) shareholderBalances;
    }

    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        uint256 indexed tokenId,
        uint256 price,
        ListingType listingType
    );

    event ListingSold(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 price
    );

    event RentalStarted(
        uint256 indexed tokenId,
        address indexed renter,
        uint256 duration,
        uint256 totalCost
    );

    event AuctionBid(
        uint256 indexed listingId,
        address indexed bidder,
        uint256 bidAmount
    );

    event FractionalSharesPurchased(
        uint256 indexed tokenId,
        address indexed buyer,
        uint256 shares,
        uint256 totalCost
    );

    function createListing(
        uint256 tokenId,
        uint256 price,
        ListingType listingType,
        uint256 duration
    ) external returns (uint256 listingId);

    function buyNFT(uint256 listingId) external payable;

    function rentNFT(
        uint256 listingId,
        uint256 duration
    ) external payable;

    function placeBid(uint256 listingId) external payable;

    function buyFractionalShares(
        uint256 tokenId,
        uint256 shares
    ) external payable;

    function cancelListing(uint256 listingId) external;

    function claimAuctionNFT(uint256 listingId) external;

    function returnRentedNFT(uint256 tokenId) external;
}