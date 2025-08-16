const { ethers } = require("hardhat");

async function main() {
    console.log("🔍 Starting contract verification...");

    // Load deployment info
    const fs = require("fs");
    let deploymentInfo;
    try {
        deploymentInfo = JSON.parse(fs.readFileSync("./deployment-info.json", "utf8"));
    } catch (error) {
        console.error("❌ Could not load deployment-info.json");
        console.error("Please run deploy.js first");
        process.exit(1);
    }

    const contracts = deploymentInfo.contracts;
    const [deployer] = await ethers.getSigners();

    console.log("Verifying contracts deployed by:", deployer.address);
    console.log("Network:", deploymentInfo.network);

    // Validate that all contract addresses exist
    const requiredContracts = [
        'LOST_TOKEN_CONTRACT_ID',
        'TREASURY_CONTRACT_ID',
        'ACHIEVEMENT_NFT_CONTRACT_ID',
        'GAMEPLAY_VERIFICATION_CONTRACT_ID',
        'LEADERBOARD_CONTRACT_ID',
        'TOURNAMENT_CONTRACT_ID',
        'MARKETPLACE_CONTRACT_ID',
        'PAYMENT_BRIDGE_CONTRACT_ID',
        'DATA_MONETIZATION_CONTRACT_ID',
        'STAKING_CONTRACT_ID'
    ];

    console.log("\n📋 Validating contract addresses...");
    for (const contractName of requiredContracts) {
        if (!contracts[contractName]) {
            console.error(`❌ Missing contract address: ${contractName}`);
            process.exit(1);
        }
    }

    let allVerified = true;

    // Verify LOST Token
    console.log("\n🔍 Verifying LOST Token...");
    try {
        const lostToken = await ethers.getContractAt("LOSTToken", contracts.LOST_TOKEN_CONTRACT_ID);
        const name = await lostToken.name();
        const symbol = await lostToken.symbol();
        const totalSupply = await lostToken.totalSupply();
        
        console.log("✅ LOST Token verified:");
        console.log(`   Address: ${contracts.LOST_TOKEN_CONTRACT_ID}`);
        console.log(`   Name: ${name}`);
        console.log(`   Symbol: ${symbol}`);
        console.log(`   Total Supply: ${ethers.formatUnits(totalSupply, 18)} LOST`);
    } catch (error) {
        console.error("❌ LOST Token verification failed:", error.message);
        allVerified = false;
    }

    // Verify Treasury
    console.log("\n🔍 Verifying Treasury...");
    try {
        const treasury = await ethers.getContractAt("Treasury", contracts.TREASURY_CONTRACT_ID);
        const lostTokenAddress = await treasury.lostTokenAddress();
        const usdcTokenAddress = await treasury.usdcTokenAddress();
        
        console.log("✅ Treasury verified:");
        console.log(`   Address: ${contracts.TREASURY_CONTRACT_ID}`);
        console.log(`   LOST Token: ${lostTokenAddress}`);
        console.log(`   USDC Token: ${usdcTokenAddress}`);
    } catch (error) {
        console.error("❌ Treasury verification failed:", error.message);
        allVerified = false;
    }

    // Verify Achievement NFT
    console.log("\n🔍 Verifying Achievement NFT...");
    try {
        const achievementNFT = await ethers.getContractAt("LOSTAchievementNFT", contracts.ACHIEVEMENT_NFT_CONTRACT_ID);
        const name = await achievementNFT.name();
        const symbol = await achievementNFT.symbol();
        
        console.log("✅ Achievement NFT verified:");
        console.log(`   Address: ${contracts.ACHIEVEMENT_NFT_CONTRACT_ID}`);
        console.log(`   Name: ${name}`);
        console.log(`   Symbol: ${symbol}`);
    } catch (error) {
        console.error("❌ Achievement NFT verification failed:", error.message);
        allVerified = false;
    }

    // Verify Gameplay Verification
    console.log("\n🔍 Verifying Gameplay Verification...");
    try {
        const gameplayVerification = await ethers.getContractAt("GameplayVerification", contracts.GAMEPLAY_VERIFICATION_CONTRACT_ID);
        const maxViolations = await gameplayVerification.MAX_VIOLATIONS();
        const sessionTimeout = await gameplayVerification.SESSION_TIMEOUT();
        
        console.log("✅ Gameplay Verification verified:");
        console.log(`   Address: ${contracts.GAMEPLAY_VERIFICATION_CONTRACT_ID}`);
        console.log(`   Max Violations: ${maxViolations}`);
        console.log(`   Session Timeout: ${Number(sessionTimeout) / 3600} hours`);
    } catch (error) {
        console.error("❌ Gameplay Verification verification failed:", error.message);
        allVerified = false;
    }

    // Verify Decentralized Leaderboard
    console.log("\n🔍 Verifying Decentralized Leaderboard...");
    try {
        const leaderboard = await ethers.getContractAt("DecentralizedLeaderboard", contracts.LEADERBOARD_CONTRACT_ID);
        const currentSeason = await leaderboard.currentSeason();
        const totalPlayers = await leaderboard.totalPlayers();
        
        console.log("✅ Decentralized Leaderboard verified:");
        console.log(`   Address: ${contracts.LEADERBOARD_CONTRACT_ID}`);
        console.log(`   Current Season: ${currentSeason}`);
        console.log(`   Total Players: ${totalPlayers}`);
    } catch (error) {
        console.error("❌ Decentralized Leaderboard verification failed:", error.message);
        allVerified = false;
    }

    // Verify Tournament
    console.log("\n🔍 Verifying Tournament...");
    try {
        const tournament = await ethers.getContractAt("Tournament", contracts.TOURNAMENT_CONTRACT_ID);
        const nextTournamentId = await tournament.nextTournamentId();
        const protocolFeePercentage = await tournament.protocolFeePercentage();
        
        console.log("✅ Tournament verified:");
        console.log(`   Address: ${contracts.TOURNAMENT_CONTRACT_ID}`);
        console.log(`   Next Tournament ID: ${nextTournamentId}`);
        console.log(`   Protocol Fee: ${Number(protocolFeePercentage) / 100}%`);
    } catch (error) {
        console.error("❌ Tournament verification failed:", error.message);
        allVerified = false;
    }

    // Verify Marketplace
    console.log("\n🔍 Verifying Marketplace...");
    try {
        const marketplace = await ethers.getContractAt("Marketplace", contracts.MARKETPLACE_CONTRACT_ID);
        const nextListingId = await marketplace.nextListingId();
        const marketplaceFeePercentage = await marketplace.marketplaceFeePercentage();
        
        console.log("✅ Marketplace verified:");
        console.log(`   Address: ${contracts.MARKETPLACE_CONTRACT_ID}`);
        console.log(`   Next Listing ID: ${nextListingId}`);
        console.log(`   Marketplace Fee: ${Number(marketplaceFeePercentage) / 100}%`);
    } catch (error) {
        console.error("❌ Marketplace verification failed:", error.message);
        allVerified = false;
    }

    // Verify USDC Payment Bridge
    console.log("\n🔍 Verifying USDC Payment Bridge...");
    try {
        const paymentBridge = await ethers.getContractAt("USDCPaymentBridge", contracts.PAYMENT_BRIDGE_CONTRACT_ID);
        const nextWithdrawalId = await paymentBridge.nextWithdrawalId();
        const lostToUsdcRate = await paymentBridge.lostToUsdcRate();
        
        console.log("✅ USDC Payment Bridge verified:");
        console.log(`   Address: ${contracts.PAYMENT_BRIDGE_CONTRACT_ID}`);
        console.log(`   Next Withdrawal ID: ${nextWithdrawalId}`);
        console.log(`   LOST to USDC Rate: ${lostToUsdcRate}`);
    } catch (error) {
        console.error("❌ USDC Payment Bridge verification failed:", error.message);
        allVerified = false;
    }

    // Verify Data Monetization
    console.log("\n🔍 Verifying Data Monetization...");
    try {
        const dataMonetization = await ethers.getContractAt("DataMonetization", contracts.DATA_MONETIZATION_CONTRACT_ID);
        const nextPackageId = await dataMonetization.nextPackageId();
        const revenueSharePercentage = await dataMonetization.revenueSharePercentage();
        
        console.log("✅ Data Monetization verified:");
        console.log(`   Address: ${contracts.DATA_MONETIZATION_CONTRACT_ID}`);
        console.log(`   Next Package ID: ${nextPackageId}`);
        console.log(`   Revenue Share: ${Number(revenueSharePercentage) / 100}%`);
    } catch (error) {
        console.error("❌ Data Monetization verification failed:", error.message);
        allVerified = false;
    }

    // Verify Staking
    console.log("\n🔍 Verifying Staking...");
    try {
        const staking = await ethers.getContractAt("Staking", contracts.STAKING_CONTRACT_ID);
        const nextProposalId = await staking.nextProposalId();
        const totalStaked = await staking.totalStaked();
        
        console.log("✅ Staking verified:");
        console.log(`   Address: ${contracts.STAKING_CONTRACT_ID}`);
        console.log(`   Next Proposal ID: ${nextProposalId}`);
        console.log(`   Total Staked: ${ethers.formatUnits(totalStaked, 18)} LOST`);
    } catch (error) {
        console.error("❌ Staking verification failed:", error.message);
        allVerified = false;
    }

    // Test basic role configurations (optional)
    console.log("\n🔍 Verifying basic contract access...");
    try {
        const lostToken = await ethers.getContractAt("LOSTToken", contracts.LOST_TOKEN_CONTRACT_ID);
        const achievementNFT = await ethers.getContractAt("LOSTAchievementNFT", contracts.ACHIEVEMENT_NFT_CONTRACT_ID);
        
        // Test basic contract accessibility
        const tokenName = await lostToken.name();
        const nftName = await achievementNFT.name();
        
        console.log("✅ Contract access verified:");
        console.log(`   Token contract accessible: ${tokenName}`);
        console.log(`   NFT contract accessible: ${nftName}`);
    } catch (error) {
        console.error("❌ Contract access verification failed:", error.message);
        allVerified = false;
    }

    // Test basic contract balances
    console.log("\n🔍 Verifying contract balances...");
    try {
        const lostToken = await ethers.getContractAt("LOSTToken", contracts.LOST_TOKEN_CONTRACT_ID);
        const treasury = await ethers.getContractAt("Treasury", contracts.TREASURY_CONTRACT_ID);
        
        const totalSupply = await lostToken.totalSupply();
        const treasuryBalance = await lostToken.balanceOf(contracts.TREASURY_CONTRACT_ID);
        
        console.log("✅ Contract balances verified:");
        console.log(`   Total Supply: ${ethers.formatUnits(totalSupply, 18)} LOST`);
        console.log(`   Treasury Balance: ${ethers.formatUnits(treasuryBalance, 18)} LOST`);
    } catch (error) {
        console.error("❌ Balance verification failed:", error.message);
        allVerified = false;
    }

    // Final verification summary
    console.log("\n📋 Verification Summary:");
    console.log("=====================================");
    if (allVerified) {
        console.log("🎉 All contracts verified successfully!");
        console.log("✅ LOST Protocol is ready for production");
        console.log("🚀 Make Gaming Great Again! #MGGA");
    } else {
        console.log("❌ Some contracts failed verification");
        console.log("🔧 Please check and fix the issues above");
    }
    console.log("=====================================");

    // Update deployment info with verification status
    deploymentInfo.lastVerification = new Date().toISOString();
    deploymentInfo.verificationStatus = allVerified ? "PASSED" : "FAILED";
    
    fs.writeFileSync(
        "./deployment-info.json",
        JSON.stringify(deploymentInfo, null, 2)
    );

    if (!allVerified) {
        process.exit(1);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ Verification failed:");
        console.error(error);
        process.exit(1);
    });