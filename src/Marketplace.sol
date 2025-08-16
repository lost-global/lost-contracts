// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IMarketplace.sol";

/**
 * @title Marketplace
 * @dev NFT marketplace for trading LOST achievement NFTs
 * Features:
 * - Direct sales and auctions
 * - NFT rentals with collateral
 * - Fractional ownership
 * - Staking rewards for listed NFTs
 * - Automatic royalty distribution
 */
contract Marketplace is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IMarketplace
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Core contracts
    address public achievementNFTAddress;
    address public lostTokenAddress;
    address public treasuryAddress;

    // Marketplace state
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => RentalTerms) public rentalTerms;
    mapping(uint256 => AuctionData) public auctions;
    mapping(uint256 => FractionalData) private fractionalData;
    
    // Rental tracking
    mapping(uint256 => address) public currentRenter;
    mapping(uint256 => uint256) public rentalEndTime;
    mapping(address => uint256[]) public userRentals;
    
    // Staking rewards
    mapping(uint256 => uint256) public stakedSince;
    mapping(uint256 => uint256) public accumulatedRewards;
    
    // Royalties
    mapping(uint256 => address) public originalCreator;
    mapping(uint256 => uint256) public royaltyPercentage;
    
    uint256 public nextListingId;
    uint256 public marketplaceFeePercentage; // Basis points
    uint256 public defaultRoyaltyPercentage; // Basis points
    uint256 public stakingRewardRate; // Rewards per day per NFT
    
    uint256 public constant MIN_AUCTION_DURATION = 1 hours;
    uint256 public constant MAX_AUCTION_DURATION = 7 days;
    uint256 public constant MIN_RENTAL_DURATION = 1 days;
    uint256 public constant MAX_RENTAL_DURATION = 30 days;
    uint256 public constant DEFAULT_BID_INCREMENT = 5; // 5% minimum bid increment

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address _achievementNFTAddress,
        address _lostTokenAddress,
        address _treasuryAddress
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        
        achievementNFTAddress = _achievementNFTAddress;
        lostTokenAddress = _lostTokenAddress;
        treasuryAddress = _treasuryAddress;
        
        nextListingId = 1;
        marketplaceFeePercentage = 250; // 2.5%
        defaultRoyaltyPercentage = 500; // 5%
        stakingRewardRate = 10 * 10**18; // 10 LOST per day
    }

    function createListing(
        uint256 tokenId,
        uint256 price,
        ListingType listingType,
        uint256 duration
    ) external whenNotPaused nonReentrant returns (uint256) {
        IERC721 nft = IERC721(achievementNFTAddress);
        require(nft.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(price > 0, "Invalid price");
        
        if (listingType == ListingType.AUCTION) {
            require(duration >= MIN_AUCTION_DURATION && duration <= MAX_AUCTION_DURATION, "Invalid auction duration");
        }
        
        uint256 listingId = nextListingId++;
        
        Listing storage listing = listings[listingId];
        listing.listingId = listingId;
        listing.seller = msg.sender;
        listing.tokenId = tokenId;
        listing.price = price;
        listing.listingType = listingType;
        listing.status = ListingStatus.ACTIVE;
        listing.startTime = block.timestamp;
        listing.endTime = duration > 0 ? block.timestamp + duration : 0;
        
        // Transfer NFT to marketplace
        nft.transferFrom(msg.sender, address(this), tokenId);
        
        // Initialize type-specific data
        if (listingType == ListingType.AUCTION) {
            AuctionData storage auction = auctions[listingId];
            auction.startingBid = price;
            auction.currentBid = 0;
            auction.bidIncrement = (price * DEFAULT_BID_INCREMENT) / 100;
            auction.endTime = block.timestamp + duration;
        } else if (listingType == ListingType.RENT) {
            RentalTerms storage rental = rentalTerms[listingId];
            rental.dailyRate = price;
            rental.minDuration = MIN_RENTAL_DURATION;
            rental.maxDuration = MAX_RENTAL_DURATION;
            rental.collateral = price * 10; // 10x daily rate as collateral
        } else if (listingType == ListingType.FRACTIONAL) {
            FractionalData storage fractional = fractionalData[listingId];
            fractional.totalShares = 10000; // 100% = 10000 shares
            fractional.availableShares = 10000;
            fractional.pricePerShare = price;
        }
        
        // Track original creator for royalties
        if (originalCreator[tokenId] == address(0)) {
            originalCreator[tokenId] = msg.sender;
            royaltyPercentage[tokenId] = defaultRoyaltyPercentage;
        }
        
        // Start staking rewards
        stakedSince[tokenId] = block.timestamp;
        
        emit ListingCreated(listingId, msg.sender, tokenId, price, listingType);
        
        return listingId;
    }

    function buyNFT(uint256 listingId) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");
        require(listing.listingType == ListingType.SALE, "Not a sale listing");
        require(msg.value >= listing.price, "Insufficient payment");
        
        listing.status = ListingStatus.SOLD;
        listing.buyer = msg.sender;
        
        // Calculate fees and royalties
        uint256 marketplaceFee = (listing.price * marketplaceFeePercentage) / 10000;
        uint256 royaltyAmount = (listing.price * royaltyPercentage[listing.tokenId]) / 10000;
        uint256 sellerAmount = listing.price - marketplaceFee - royaltyAmount;
        
        // Distribute payments
        _distributeFunds(listing.seller, sellerAmount);
        _distributeFunds(originalCreator[listing.tokenId], royaltyAmount);
        _distributeFunds(treasuryAddress, marketplaceFee);
        
        // Calculate and distribute staking rewards
        _distributeStakingRewards(listing.tokenId, listing.seller);
        
        // Transfer NFT to buyer
        IERC721(achievementNFTAddress).transferFrom(address(this), msg.sender, listing.tokenId);
        
        // Refund excess payment
        if (msg.value > listing.price) {
            (bool refundSuccess, ) = msg.sender.call{value: msg.value - listing.price}("");
            require(refundSuccess, "Refund failed");
        }
        
        emit ListingSold(listingId, msg.sender, listing.price);
    }

    function rentNFT(uint256 listingId, uint256 duration) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        RentalTerms storage rental = rentalTerms[listingId];
        
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");
        require(listing.listingType == ListingType.RENT, "Not a rental listing");
        require(currentRenter[listing.tokenId] == address(0), "Already rented");
        require(duration >= rental.minDuration && duration <= rental.maxDuration, "Invalid rental duration");
        
        uint256 rentalDays = duration / 1 days;
        uint256 totalCost = rental.dailyRate * rentalDays;
        uint256 totalPayment = totalCost + rental.collateral;
        
        require(msg.value >= totalPayment, "Insufficient payment");
        
        currentRenter[listing.tokenId] = msg.sender;
        rentalEndTime[listing.tokenId] = block.timestamp + duration;
        userRentals[msg.sender].push(listing.tokenId);
        
        // Distribute rental payment (keep collateral in contract)
        uint256 marketplaceFee = (totalCost * marketplaceFeePercentage) / 10000;
        uint256 sellerAmount = totalCost - marketplaceFee;
        
        _distributeFunds(listing.seller, sellerAmount);
        _distributeFunds(treasuryAddress, marketplaceFee);
        
        // Refund excess payment
        if (msg.value > totalPayment) {
            (bool refundSuccess, ) = msg.sender.call{value: msg.value - totalPayment}("");
            require(refundSuccess, "Refund failed");
        }
        
        emit RentalStarted(listing.tokenId, msg.sender, duration, totalCost);
    }

    function returnRentedNFT(uint256 tokenId) external whenNotPaused nonReentrant {
        require(currentRenter[tokenId] == msg.sender, "Not the renter");
        require(block.timestamp >= rentalEndTime[tokenId], "Rental period not ended");
        
        // Find the listing
        uint256 listingId = _findListingByTokenId(tokenId);
        RentalTerms storage rental = rentalTerms[listingId];
        
        // Return collateral to renter
        (bool collateralReturn, ) = msg.sender.call{value: rental.collateral}("");
        require(collateralReturn, "Collateral return failed");
        
        // Clear rental data
        currentRenter[tokenId] = address(0);
        rentalEndTime[tokenId] = 0;
        
        // Remove from user rentals
        _removeFromUserRentals(msg.sender, tokenId);
    }

    function placeBid(uint256 listingId) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        AuctionData storage auction = auctions[listingId];
        
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");
        require(listing.listingType == ListingType.AUCTION, "Not an auction");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(msg.value >= auction.startingBid, "Bid below starting price");
        
        if (auction.currentBid > 0) {
            require(msg.value >= auction.currentBid + auction.bidIncrement, "Bid increment too low");
            
            // Refund previous bidder
            (bool refundSuccess, ) = auction.highestBidder.call{value: auction.currentBid}("");
            require(refundSuccess, "Refund to previous bidder failed");
        }
        
        auction.currentBid = msg.value;
        auction.highestBidder = msg.sender;
        
        emit AuctionBid(listingId, msg.sender, msg.value);
    }

    function claimAuctionNFT(uint256 listingId) external whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        AuctionData storage auction = auctions[listingId];
        
        require(listing.listingType == ListingType.AUCTION, "Not an auction");
        require(block.timestamp >= auction.endTime, "Auction not ended");
        require(auction.highestBidder == msg.sender, "Not the winner");
        require(listing.status == ListingStatus.ACTIVE, "Already claimed");
        
        listing.status = ListingStatus.SOLD;
        listing.buyer = msg.sender;
        
        // Calculate fees and royalties
        uint256 salePrice = auction.currentBid;
        uint256 marketplaceFee = (salePrice * marketplaceFeePercentage) / 10000;
        uint256 royaltyAmount = (salePrice * royaltyPercentage[listing.tokenId]) / 10000;
        uint256 sellerAmount = salePrice - marketplaceFee - royaltyAmount;
        
        // Distribute payments
        _distributeFunds(listing.seller, sellerAmount);
        _distributeFunds(originalCreator[listing.tokenId], royaltyAmount);
        _distributeFunds(treasuryAddress, marketplaceFee);
        
        // Calculate and distribute staking rewards
        _distributeStakingRewards(listing.tokenId, listing.seller);
        
        // Transfer NFT to winner
        IERC721(achievementNFTAddress).transferFrom(address(this), msg.sender, listing.tokenId);
        
        emit ListingSold(listingId, msg.sender, salePrice);
    }

    function buyFractionalShares(uint256 tokenId, uint256 shares) external payable whenNotPaused nonReentrant {
        uint256 listingId = _findListingByTokenId(tokenId);
        Listing storage listing = listings[listingId];
        FractionalData storage fractional = fractionalData[listingId];
        
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");
        require(listing.listingType == ListingType.FRACTIONAL, "Not fractional listing");
        require(shares > 0 && shares <= fractional.availableShares, "Invalid share amount");
        
        uint256 totalCost = fractional.pricePerShare * shares;
        require(msg.value >= totalCost, "Insufficient payment");
        
        fractional.availableShares -= shares;
        fractional.shareholderBalances[msg.sender] += shares;
        
        // Distribute payment
        uint256 marketplaceFee = (totalCost * marketplaceFeePercentage) / 10000;
        uint256 sellerAmount = totalCost - marketplaceFee;
        
        _distributeFunds(listing.seller, sellerAmount);
        _distributeFunds(treasuryAddress, marketplaceFee);
        
        // Refund excess payment
        if (msg.value > totalCost) {
            (bool refundSuccess, ) = msg.sender.call{value: msg.value - totalCost}("");
            require(refundSuccess, "Refund failed");
        }
        
        emit FractionalSharesPurchased(tokenId, msg.sender, shares, totalCost);
    }

    function cancelListing(uint256 listingId) external whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender || hasRole(ADMIN_ROLE, msg.sender), "Not authorized");
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");
        
        if (listing.listingType == ListingType.AUCTION) {
            AuctionData storage auction = auctions[listingId];
            require(auction.currentBid == 0, "Auction has bids");
        } else if (listing.listingType == ListingType.RENT) {
            require(currentRenter[listing.tokenId] == address(0), "Currently rented");
        }
        
        listing.status = ListingStatus.CANCELLED;
        
        // Calculate and distribute staking rewards
        _distributeStakingRewards(listing.tokenId, listing.seller);
        
        // Return NFT to seller
        IERC721(achievementNFTAddress).transferFrom(address(this), listing.seller, listing.tokenId);
    }

    function _distributeFunds(address recipient, uint256 amount) private {
        if (amount > 0 && recipient != address(0)) {
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "Transfer failed");
        }
    }

    function _distributeStakingRewards(uint256 tokenId, address recipient) private {
        if (stakedSince[tokenId] > 0) {
            uint256 stakingDuration = block.timestamp - stakedSince[tokenId];
            uint256 rewards = (stakingDuration * stakingRewardRate) / 1 days;
            
            if (rewards > 0 && lostTokenAddress != address(0)) {
                IERC20(lostTokenAddress).transfer(recipient, rewards);
                accumulatedRewards[tokenId] += rewards;
            }
            
            stakedSince[tokenId] = 0;
        }
    }

    function _findListingByTokenId(uint256 tokenId) private view returns (uint256) {
        for (uint256 i = 1; i < nextListingId; i++) {
            if (listings[i].tokenId == tokenId && listings[i].status == ListingStatus.ACTIVE) {
                return i;
            }
        }
        revert("Listing not found");
    }

    function _removeFromUserRentals(address user, uint256 tokenId) private {
        uint256[] storage rentals = userRentals[user];
        for (uint256 i = 0; i < rentals.length; i++) {
            if (rentals[i] == tokenId) {
                rentals[i] = rentals[rentals.length - 1];
                rentals.pop();
                break;
            }
        }
    }

    function getFractionalBalances(uint256 listingId, address shareholder) external view returns (uint256) {
        return fractionalData[listingId].shareholderBalances[shareholder];
    }

    function updateMarketplaceFee(uint256 newFeePercentage) external onlyRole(ADMIN_ROLE) {
        require(newFeePercentage <= 1000, "Fee too high"); // Max 10%
        marketplaceFeePercentage = newFeePercentage;
    }

    function updateStakingRewardRate(uint256 newRate) external onlyRole(ADMIN_ROLE) {
        stakingRewardRate = newRate;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}