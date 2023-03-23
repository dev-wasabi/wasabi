const truffleAssert = require('truffle-assertions');

import { toEth, toBN, makeRequest, makeConfig, metadata, signRequest, gasOfTxn, assertIncreaseInBalance, advanceTime } from "./util/TestUtils";
import { OptionRequest, OptionType, ZERO_ADDRESS } from "./util/TestTypes";
import { TestERC721Instance } from "../types/truffle-contracts/TestERC721.js";
import { WasabiPoolFactoryInstance } from "../types/truffle-contracts/WasabiPoolFactory.js";
import { WasabiOptionInstance } from "../types/truffle-contracts/WasabiOption.js";
import { OptionIssued, ETHWasabiPoolInstance } from "../types/truffle-contracts/ETHWasabiPool.js";

const WasabiPoolFactory = artifacts.require("WasabiPoolFactory");
const WasabiOption = artifacts.require("WasabiOption");
const TestERC721 = artifacts.require("TestERC721");
const ETHWasabiPool = artifacts.require("ETHWasabiPool");

contract("ETHWasabiPool: Expiring CallOption execution", accounts => {
    let poolFactory: WasabiPoolFactoryInstance;
    let option: WasabiOptionInstance;
    let testNft: TestERC721Instance;
    let pool: ETHWasabiPoolInstance;
    let optionId: BN;
    let request: OptionRequest;
    let tokenToSell: number;

    const lp = accounts[2];
    const buyer = accounts[3];
    const someoneElse = accounts[5];

    const duration = 10000;

    before("Prepare State", async function () {
        testNft = await TestERC721.deployed();
        option = await WasabiOption.deployed();
        poolFactory = await WasabiPoolFactory.deployed();
        await option.setFactory(poolFactory.address);

        let mintResult = await testNft.mint(metadata(lp));
        tokenToSell = (mintResult.logs.find(e => e.event == 'Transfer')?.args[2] as BN).toNumber();
    });
    
    it("Create Pool", async () => {
        await testNft.setApprovalForAll.sendTransaction(poolFactory.address, true, metadata(lp));

        const config = makeConfig(1, 100, 222, 2630000 /* one month */);
        const types = [OptionType.CALL];
        const createPoolResult = await poolFactory.createPool(testNft.address, [tokenToSell], config, types, ZERO_ADDRESS, metadata(lp));
        truffleAssert.eventEmitted(createPoolResult, "NewPool", null, "Pool wasn't created");
        truffleAssert.eventEmitted(createPoolResult, "OwnershipTransferred", { previousOwner: ZERO_ADDRESS, newOwner: lp }, "Pool didn't change owners correctly");

        const poolAddress = createPoolResult.logs.find(e => e.event == "NewPool")!.args[0];
        pool = await ETHWasabiPool.at(poolAddress);
        assert.equal(await pool.owner(), lp, "Pool creator and owner not same");
        assert.deepEqual((await pool.getAllTokenIds()).map(a => a.toNumber()), [tokenToSell], "Pool doesn't have the correct tokens");
    });

    it("Write Option (only owner)", async () => {
        const id = 1;
        let blockNumber = await web3.eth.getBlockNumber();
        let timestamp = Number((await web3.eth.getBlock(blockNumber)).timestamp);
        let expiry = timestamp + duration;
        let orderExpiry = timestamp + duration;

        request = makeRequest(id, pool.address, OptionType.CALL, 10, 1, expiry, tokenToSell, orderExpiry);
        const writeOptionResult = await pool.writeOption(request, await signRequest(request, lp), metadata(buyer, 1));
        truffleAssert.eventEmitted(writeOptionResult, "OptionIssued", null, "Asset wasn't locked");
        assert.equal(await web3.eth.getBalance(pool.address), request.premium, "Incorrect balance in pool");

        const log = writeOptionResult.logs.find(l => l.event == "OptionIssued")! as Truffle.TransactionLog<OptionIssued>;
        optionId = log.args.optionId;
        assert.equal(await option.ownerOf(optionId), buyer, "Buyer not the owner of option");
    });

    it("Execute Option (option expires)", async () => {
        await advanceTime(duration * 2);
        await truffleAssert.reverts(
            pool.executeOption(optionId, metadata(buyer, 10)),
            "Option has expired",
            "Expired option cannot be exercised");
    });
});
