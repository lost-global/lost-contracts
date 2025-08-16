const { Client, AccountId, PrivateKey, TransferTransaction, Hbar } = require("@hashgraph/sdk");
require("dotenv").config();

async function fundAccount() {
    console.log("🏦 Funding Hedera testnet account for contract deployment");
    
    // Setup Hedera client with existing funded account
    const operatorId = AccountId.fromString("0.0.6412974");
    const operatorKey = PrivateKey.fromString("302e020100300506032b657004220420bb51141f1e5de49e9332acd78fd15a089981cee73336c92be52c8a59270211f2");
    
    const client = Client.forTestnet();
    client.setOperator(operatorId, operatorKey);
    
    console.log(`✅ Connected with account: ${operatorId}`);
    
    // Target EVM address that needs funding
    const targetAddress = "0xbdBf479ddd2689E898b44bE87cBC1544412f40c8";
    console.log(`🎯 Target address: ${targetAddress}`);
    
    // In Hedera, we need to create an account for the EVM address first
    // This will auto-create a hollow account when we send HBAR to it
    
    try {
        // Send HBAR to create and fund the account
        console.log("💸 Sending 100 HBAR to create and fund the account...");
        
        const transferTx = new TransferTransaction()
            .addHbarTransfer(operatorId, Hbar.fromTinybars(-10000000000)) // -100 HBAR
            .addHbarTransfer(targetAddress, Hbar.fromTinybars(10000000000)) // +100 HBAR
            .setMaxTransactionFee(new Hbar(1))
            .freezeWith(client);
        
        const transferSign = await transferTx.sign(operatorKey);
        const transferSubmit = await transferSign.execute(client);
        const transferReceipt = await transferSubmit.getReceipt(client);
        
        console.log(`✅ Transfer completed! Status: ${transferReceipt.status}`);
        console.log(`🎉 Account ${targetAddress} is now funded with 100 HBAR`);
        console.log("🚀 Ready for contract deployment!");
        
    } catch (error) {
        console.error("❌ Failed to fund account:", error.message);
        console.error("This might be because the account needs to be created through the faucet first");
        console.error("Please visit: https://portal.hedera.com/faucet");
        console.error(`Enter address: ${targetAddress}`);
    }
    
    client.close();
}

fundAccount().catch(console.error);