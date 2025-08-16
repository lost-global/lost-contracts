const { ethers } = require("hardhat");

async function testContracts() {
    console.log("🧪 Testing LOST Protocol Smart Contracts");
    console.log("==========================================");
    
    try {
        const [signer] = await ethers.getSigners();
        console.log("✅ Connected with signer:", signer.address);
        
        // Test LOST Token
        console.log("\n📊 Testing LOST Token Contract...");
        const lostToken = await ethers.getContractAt("LOSTToken", "0xC813050218DEA42BCA945b0d50dF2F4c710DEc1b");
        
        const name = await lostToken.name();
        const symbol = await lostToken.symbol();
        const totalSupply = await lostToken.totalSupply();
        const balance = await lostToken.balanceOf(signer.address);
        
        console.log("  Name:", name);
        console.log("  Symbol:", symbol);
        console.log("  Total Supply:", ethers.formatUnits(totalSupply, 18), "LOST");
        console.log("  Owner Balance:", ethers.formatUnits(balance, 18), "LOST");
        
        // Test Treasury
        console.log("\n🏛️ Testing Treasury Contract...");
        const treasury = await ethers.getContractAt("Treasury", "0x3568d8dA5571628A8f4C1a643f67E898a6F5cbf2");
        const treasuryLostToken = await treasury.lostTokenAddress();
        const treasuryUsdcToken = await treasury.usdcTokenAddress();
        
        console.log("  LOST Token Address:", treasuryLostToken);
        console.log("  USDC Token Address:", treasuryUsdcToken);
        
        // Test Achievement NFT
        console.log("\n🏆 Testing Achievement NFT Contract...");
        const achievementNFT = await ethers.getContractAt("LOSTAchievementNFT", "0x64Ab630b8c081544cFE383924f3e06e0E01539Aa");
        const nftName = await achievementNFT.name();
        const nftSymbol = await achievementNFT.symbol();
        const totalNFTs = await achievementNFT.totalSupply();
        
        console.log("  NFT Name:", nftName);
        console.log("  NFT Symbol:", nftSymbol);
        console.log("  Total NFTs Minted:", totalNFTs.toString());
        
        // Test Tournament Contract
        console.log("\n🏟️ Testing Tournament Contract...");
        const tournament = await ethers.getContractAt("Tournament", "0x4FAA3e38fFd4AFbc3A36dA5a9BA3e995Bae055D5");
        const nextTournamentId = await tournament.nextTournamentId();
        
        console.log("  Next Tournament ID:", nextTournamentId.toString());
        console.log("  Tournaments Created:", (nextTournamentId - 1n).toString());
        
        // Test Marketplace
        console.log("\n🛒 Testing Marketplace Contract...");
        const marketplace = await ethers.getContractAt("Marketplace", "0x01F3F300Af18601691ee1A89D11c15A3dc3b185C");
        const nextListingId = await marketplace.nextListingId();
        
        console.log("  Next Listing ID:", nextListingId.toString());
        console.log("  Total Listings:", (nextListingId - 1n).toString());
        
        console.log("\n🎉 All contract tests completed successfully!");
        console.log("✅ LOST Protocol is ready for production!");
        console.log("🚀 Ready to Make Gaming Great Again! #MGGA");
        
    } catch (error) {
        console.error("❌ Contract test failed:", error.message);
        throw error;
    }
}

testContracts()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ Test execution failed:", error);
        process.exit(1);
    });