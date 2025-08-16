const { ethers, upgrades } = require("hardhat");
require("dotenv").config();

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Network: Hedera Testnet");
    
    // Configuration - using official Hedera testnet defaults
    const usdcAddress = process.env.USDC_TOKEN_ADDRESS || "0xa0b86a33e6417efE68308F44A32B32BbceFE18E4"; // Official USDC on Hedera testnet
    const nftBaseUri = process.env.NFT_METADATA_BASE_URI || "https://api.lost-protocol.com/metadata/";
    
    console.log("\n📝 Configuration:");
    console.log("  USDC Token Address:", usdcAddress, usdcAddress === "0xa0b86a33e6417efE68308F44A32B32BbceFE18E4" ? "(Official Hedera testnet USDC)" : "(Custom)");
    console.log("  NFT Metadata Base URI:", nftBaseUri, nftBaseUri === "https://api.lost-protocol.com/metadata/" ? "(Default)" : "(Custom)");

    const contractAddresses = {};

    // Deploy LOST Token first
    console.log("\n🚀 Deploying LOST Token...");
    const LOSTToken = await ethers.getContractFactory("LOSTToken");
    const lostToken = await upgrades.deployProxy(LOSTToken, [deployer.address], {
        initializer: "initialize",
        kind: "uups"
    });
    await lostToken.waitForDeployment();
    const lostTokenAddress = await lostToken.getAddress();
    console.log("✅ LOST Token deployed to:", lostTokenAddress);
    contractAddresses.LOST_TOKEN_CONTRACT_ID = lostTokenAddress;

    // Deploy Treasury
    console.log("\n🚀 Deploying Treasury...");
    const Treasury = await ethers.getContractFactory("Treasury");
    const treasury = await upgrades.deployProxy(Treasury, [
        deployer.address,
        lostTokenAddress,
        usdcAddress
    ], {
        initializer: "initialize",
        kind: "uups"
    });
    await treasury.waitForDeployment();
    const treasuryAddress = await treasury.getAddress();
    console.log("✅ Treasury deployed to:", treasuryAddress);
    contractAddresses.TREASURY_CONTRACT_ID = treasuryAddress;

    // Deploy Achievement NFT
    console.log("\n🚀 Deploying Achievement NFT...");
    const LOSTAchievementNFT = await ethers.getContractFactory("LOSTAchievementNFT");
    const achievementNFT = await upgrades.deployProxy(LOSTAchievementNFT, [
        deployer.address,
        nftBaseUri
    ], {
        initializer: "initialize",
        kind: "uups"
    });
    await achievementNFT.waitForDeployment();
    const achievementNFTAddress = await achievementNFT.getAddress();
    console.log("✅ Achievement NFT deployed to:", achievementNFTAddress);
    contractAddresses.ACHIEVEMENT_NFT_CONTRACT_ID = achievementNFTAddress;

    // Deploy Gameplay Verification
    console.log("\n🚀 Deploying Gameplay Verification...");
    const GameplayVerification = await ethers.getContractFactory("GameplayVerification");
    const gameplayVerification = await upgrades.deployProxy(GameplayVerification, [
        deployer.address
    ], {
        initializer: "initialize",
        kind: "uups"
    });
    await gameplayVerification.waitForDeployment();
    const gameplayVerificationAddress = await gameplayVerification.getAddress();
    console.log("✅ Gameplay Verification deployed to:", gameplayVerificationAddress);
    contractAddresses.GAMEPLAY_VERIFICATION_CONTRACT_ID = gameplayVerificationAddress;

    // Deploy Decentralized Leaderboard
    console.log("\n🚀 Deploying Decentralized Leaderboard...");
    const DecentralizedLeaderboard = await ethers.getContractFactory("DecentralizedLeaderboard");
    const leaderboard = await upgrades.deployProxy(DecentralizedLeaderboard, [
        deployer.address
    ], {
        initializer: "initialize",
        kind: "uups"
    });
    await leaderboard.waitForDeployment();
    const leaderboardAddress = await leaderboard.getAddress();
    console.log("✅ Decentralized Leaderboard deployed to:", leaderboardAddress);
    contractAddresses.LEADERBOARD_CONTRACT_ID = leaderboardAddress;

    // Deploy Tournament
    console.log("\n🚀 Deploying Tournament...");
    const Tournament = await ethers.getContractFactory("Tournament");
    const tournament = await upgrades.deployProxy(Tournament, [
        deployer.address,
        treasuryAddress,
        lostTokenAddress
    ], {
        initializer: "initialize",
        kind: "uups"
    });
    await tournament.waitForDeployment();
    const tournamentAddress = await tournament.getAddress();
    console.log("✅ Tournament deployed to:", tournamentAddress);
    contractAddresses.TOURNAMENT_CONTRACT_ID = tournamentAddress;

    // Deploy Marketplace
    console.log("\n🚀 Deploying Marketplace...");
    const Marketplace = await ethers.getContractFactory("Marketplace");
    const marketplace = await upgrades.deployProxy(Marketplace, [
        deployer.address,
        achievementNFTAddress,
        lostTokenAddress,
        treasuryAddress
    ], {
        initializer: "initialize",
        kind: "uups"
    });
    await marketplace.waitForDeployment();
    const marketplaceAddress = await marketplace.getAddress();
    console.log("✅ Marketplace deployed to:", marketplaceAddress);
    contractAddresses.MARKETPLACE_CONTRACT_ID = marketplaceAddress;

    // Deploy USDC Payment Bridge
    console.log("\n🚀 Deploying USDC Payment Bridge...");
    const USDCPaymentBridge = await ethers.getContractFactory("USDCPaymentBridge");
    const paymentBridge = await upgrades.deployProxy(USDCPaymentBridge, [
        deployer.address,
        usdcAddress,
        lostTokenAddress,
        treasuryAddress
    ], {
        initializer: "initialize",
        kind: "uups"
    });
    await paymentBridge.waitForDeployment();
    const paymentBridgeAddress = await paymentBridge.getAddress();
    console.log("✅ USDC Payment Bridge deployed to:", paymentBridgeAddress);
    contractAddresses.PAYMENT_BRIDGE_CONTRACT_ID = paymentBridgeAddress;

    // Deploy Data Monetization
    console.log("\n🚀 Deploying Data Monetization...");
    const DataMonetization = await ethers.getContractFactory("DataMonetization");
    const dataMonetization = await upgrades.deployProxy(DataMonetization, [
        deployer.address,
        lostTokenAddress,
        treasuryAddress
    ], {
        initializer: "initialize",
        kind: "uups"
    });
    await dataMonetization.waitForDeployment();
    const dataMonetizationAddress = await dataMonetization.getAddress();
    console.log("✅ Data Monetization deployed to:", dataMonetizationAddress);
    contractAddresses.DATA_MONETIZATION_CONTRACT_ID = dataMonetizationAddress;

    // Deploy Staking
    console.log("\n🚀 Deploying Staking...");
    const Staking = await ethers.getContractFactory("Staking");
    const staking = await upgrades.deployProxy(Staking, [
        deployer.address,
        lostTokenAddress,
        treasuryAddress
    ], {
        initializer: "initialize",
        kind: "uups"
    });
    await staking.waitForDeployment();
    const stakingAddress = await staking.getAddress();
    console.log("✅ Staking deployed to:", stakingAddress);
    contractAddresses.STAKING_CONTRACT_ID = stakingAddress;

    // Output deployment summary
    console.log("\n📋 Deployment Summary:");
    console.log("=====================================");
    Object.entries(contractAddresses).forEach(([name, address]) => {
        console.log(`${name}: ${address}`);
    });
    console.log("=====================================");

    // Save deployment info
    const deploymentInfo = {
        network: "hedera_testnet",
        deployer: deployer.address,
        timestamp: new Date().toISOString(),
        contracts: contractAddresses
    };

    const fs = require("fs");
    fs.writeFileSync("./deployment-info.json", JSON.stringify(deploymentInfo, null, 2));
    console.log("✅ Deployment info saved to deployment-info.json");

    // Generate environment variables
    const envUpdates = Object.entries(contractAddresses)
        .map(([key, value]) => `${key}=${value}`)
        .join('\n');

    console.log("\n📝 Add these to your .env file:");
    console.log("=====================================");
    console.log(envUpdates);
    console.log("=====================================");

    console.log("\n🎉 LOST Protocol deployment completed successfully!");
    console.log("🚀 Ready to Make Gaming Great Again! #MGGA");

    return contractAddresses;
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ Deployment failed:");
        console.error(error);
        process.exit(1);
    });