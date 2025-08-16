const { ethers, upgrades } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Upgrading contracts with the account:", deployer.address);

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
        console.log(`✅ ${contractName}: ${contracts[contractName]}`);
    }

    console.log("\n🔄 Starting contract upgrades...");

    // Upgrade LOST Token
    console.log("\n⬆️ Upgrading LOST Token...");
    const LOSTTokenV2 = await ethers.getContractFactory("LOSTToken");
    const lostTokenV2 = await upgrades.upgradeProxy(contracts.LOST_TOKEN_CONTRACT_ID, LOSTTokenV2);
    console.log("✅ LOST Token upgraded successfully");

    // Upgrade Treasury
    console.log("\n⬆️ Upgrading Treasury...");
    const TreasuryV2 = await ethers.getContractFactory("Treasury");
    const treasuryV2 = await upgrades.upgradeProxy(contracts.TREASURY_CONTRACT_ID, TreasuryV2);
    console.log("✅ Treasury upgraded successfully");

    // Upgrade Achievement NFT
    console.log("\n⬆️ Upgrading Achievement NFT...");
    const LOSTAchievementNFTV2 = await ethers.getContractFactory("LOSTAchievementNFT");
    const achievementNFTV2 = await upgrades.upgradeProxy(contracts.ACHIEVEMENT_NFT_CONTRACT_ID, LOSTAchievementNFTV2);
    console.log("✅ Achievement NFT upgraded successfully");

    // Upgrade Gameplay Verification
    console.log("\n⬆️ Upgrading Gameplay Verification...");
    const GameplayVerificationV2 = await ethers.getContractFactory("GameplayVerification");
    const gameplayVerificationV2 = await upgrades.upgradeProxy(contracts.GAMEPLAY_VERIFICATION_CONTRACT_ID, GameplayVerificationV2);
    console.log("✅ Gameplay Verification upgraded successfully");

    // Upgrade Decentralized Leaderboard
    console.log("\n⬆️ Upgrading Decentralized Leaderboard...");
    const DecentralizedLeaderboardV2 = await ethers.getContractFactory("DecentralizedLeaderboard");
    const leaderboardV2 = await upgrades.upgradeProxy(contracts.LEADERBOARD_CONTRACT_ID, DecentralizedLeaderboardV2);
    console.log("✅ Decentralized Leaderboard upgraded successfully");

    // Upgrade Tournament
    console.log("\n⬆️ Upgrading Tournament...");
    const TournamentV2 = await ethers.getContractFactory("Tournament");
    const tournamentV2 = await upgrades.upgradeProxy(contracts.TOURNAMENT_CONTRACT_ID, TournamentV2);
    console.log("✅ Tournament upgraded successfully");

    // Upgrade Marketplace
    console.log("\n⬆️ Upgrading Marketplace...");
    const MarketplaceV2 = await ethers.getContractFactory("Marketplace");
    const marketplaceV2 = await upgrades.upgradeProxy(contracts.MARKETPLACE_CONTRACT_ID, MarketplaceV2);
    console.log("✅ Marketplace upgraded successfully");

    // Upgrade USDC Payment Bridge
    console.log("\n⬆️ Upgrading USDC Payment Bridge...");
    const USDCPaymentBridgeV2 = await ethers.getContractFactory("USDCPaymentBridge");
    const paymentBridgeV2 = await upgrades.upgradeProxy(contracts.PAYMENT_BRIDGE_CONTRACT_ID, USDCPaymentBridgeV2);
    console.log("✅ USDC Payment Bridge upgraded successfully");

    // Upgrade Data Monetization
    console.log("\n⬆️ Upgrading Data Monetization...");
    const DataMonetizationV2 = await ethers.getContractFactory("DataMonetization");
    const dataMonetizationV2 = await upgrades.upgradeProxy(contracts.DATA_MONETIZATION_CONTRACT_ID, DataMonetizationV2);
    console.log("✅ Data Monetization upgraded successfully");

    // Upgrade Staking
    console.log("\n⬆️ Upgrading Staking...");
    const StakingV2 = await ethers.getContractFactory("Staking");
    const stakingV2 = await upgrades.upgradeProxy(contracts.STAKING_CONTRACT_ID, StakingV2);
    console.log("✅ Staking upgraded successfully");

    // Update deployment info with new version
    deploymentInfo.lastUpgrade = new Date().toISOString();
    deploymentInfo.version = "2.0.0";
    
    fs.writeFileSync(
        "./deployment-info.json",
        JSON.stringify(deploymentInfo, null, 2)
    );

    console.log("\n🎉 All contracts upgraded successfully!");
    console.log("📝 Deployment info updated with upgrade timestamp");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ Upgrade failed:");
        console.error(error);
        process.exit(1);
    });