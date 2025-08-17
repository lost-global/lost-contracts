const hre = require("hardhat");
const fs = require("fs");

async function main() {
    console.log("🔧 Initializing LOST Protocol contracts...");
    
    // Load deployment info
    const deploymentInfo = JSON.parse(fs.readFileSync("./deployment-info.json", "utf8"));
    const contracts = deploymentInfo.contracts;
    
    const [deployer] = await hre.ethers.getSigners();
    console.log("Initializing with account:", deployer.address);
    
    // Connect to contracts
    const LOSTToken = await hre.ethers.getContractAt("LOSTToken", contracts.LOST_TOKEN_CONTRACT_ID);
    const GameplayVerification = await hre.ethers.getContractAt("GameplayVerification", contracts.GAMEPLAY_VERIFICATION_CONTRACT_ID);
    const AchievementNFT = await hre.ethers.getContractAt("LOSTAchievementNFT", contracts.ACHIEVEMENT_NFT_CONTRACT_ID);
    const Leaderboard = await hre.ethers.getContractAt("DecentralizedLeaderboard", contracts.LEADERBOARD_CONTRACT_ID);
    
    console.log("\n📝 Granting roles...");
    
    // Grant GAME_CONTROLLER_ROLE to API operator
    const GAME_CONTROLLER_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("GAME_CONTROLLER_ROLE"));
    const MINTER_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("MINTER_ROLE"));
    const VERIFIER_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("VERIFIER_ROLE"));
    const GAME_SERVER_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("GAME_SERVER_ROLE"));
    const UPDATER_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("UPDATER_ROLE"));
    const VALIDATOR_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("VALIDATOR_ROLE"));
    
    // Grant roles to deployer (who will act as the game controller)
    console.log("Granting GAME_CONTROLLER_ROLE to deployer...");
    await LOSTToken.grantRole(GAME_CONTROLLER_ROLE, deployer.address);
    
    console.log("Granting MINTER_ROLE to deployer...");
    await LOSTToken.grantRole(MINTER_ROLE, deployer.address);
    
    console.log("Granting VERIFIER_ROLE for GameplayVerification...");
    await GameplayVerification.grantRole(VERIFIER_ROLE, deployer.address);
    
    console.log("Granting GAME_SERVER_ROLE for GameplayVerification...");
    await GameplayVerification.grantRole(GAME_SERVER_ROLE, deployer.address);
    
    console.log("Granting MINTER_ROLE for AchievementNFT...");
    await AchievementNFT.grantRole(MINTER_ROLE, deployer.address);
    
    console.log("Granting UPDATER_ROLE for Leaderboard...");
    await Leaderboard.grantRole(UPDATER_ROLE, deployer.address);
    
    console.log("Granting VALIDATOR_ROLE for Leaderboard...");
    await Leaderboard.grantRole(VALIDATOR_ROLE, deployer.address);
    
    // Grant contract permissions
    console.log("\nGranting inter-contract permissions...");
    await LOSTToken.grantRole(GAME_CONTROLLER_ROLE, contracts.GAMEPLAY_VERIFICATION_CONTRACT_ID);
    await LOSTToken.grantRole(GAME_CONTROLLER_ROLE, contracts.TREASURY_CONTRACT_ID);
    
    console.log("\n✅ Contract initialization complete!");
    console.log("All roles have been granted successfully.");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ Initialization failed:");
        console.error(error);
        process.exit(1);
    });