const { expect } = require("chai")
const { ethers, deployments, network } = require('hardhat')
const { mainnet: addresses } = require('../../addresses/optionA') //TODO
const IERC20_ABI = require("../../abis/IERC20_ABI.json")//TODO
const { isCallTrace } = require("hardhat/internal/hardhat-network/stack-traces/message-trace")
const sushiABI = require("../../artifacts/interfaces/IUniswapV2Router02.sol/IUniswapV2Router02.json").abi

const USDTAddress = addresses.TOKENS.USDT
const SLPAddress = addresses.TOKENS.SLP
const DAIAddress = addresses.TOKENS.DAI
const unlockedAddress = "0x28C6c06298d514Db089934071355E5743bf21d60"//addresses.ADDRESSES.unlockedUser
const unlockedAddress2 = "0xa1D8d972560C2f8144AF871Db508F0B0B10a3fBf"//addresses.ADDRESSES.unlockedUser2


const increaseTime = async (_timeInMilliSeconds) => {
    let result = await network.provider.request({
        method: "evm_increaseTime",
        params: [_timeInMilliSeconds]
    })
}

const mine = async () => {
    let result = await network.provider.request({
        method: "evm_mine",
        params: []
    })
}
describe("OA - ETHSLP", () => {
    const setup = async () => {
        const [deployer] = await ethers.getSigners()

        const USDT = new ethers.Contract(USDTAddress, IERC20_ABI, deployer)
        const SLP = new ethers.Contract(SLPAddress, IERC20_ABI, deployer)
        const DAI = new ethers.Contract(DAIAddress, IERC20_ABI, deployer)
        const SUSHI = new ethers.Contract(addresses.TOKENS.SUSHI, IERC20_ABI, deployer)
        const WETH = new ethers.Contract(addresses.TOKENS.WETH, IERC20_ABI, deployer)
        const lpToken = new ethers.Contract(addresses.TOKENS.ETHSLPLP, IERC20_ABI, deployer)
        const SushiRouter = await ethers.getContractAt(sushiABI, addresses.SUSHI.router, deployer)

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [unlockedAddress]
        })


        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [unlockedAddress2]
        })

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [addresses.ADDRESSES.adminAddress]
        })

        const impl = await ethers.getContract("DAOVaultOptionA", deployer)
        let implArtifacts = await artifacts.readArtifact("DAOVaultOptionA")
        const Factory = await ethers.getContract("SushiOptionAFactory", deployer)
        const vaultProxyAddress = await Factory.getVault((await Factory.totalVaults()).toNumber() - 1)

        const vault = await ethers.getContractAt(implArtifacts.abi, vaultProxyAddress, deployer)

        const unlockedUser = await ethers.getSigner(unlockedAddress)
        const unlockedUser2 = await ethers.getSigner(unlockedAddress2)
        const adminSigner = await ethers.getSigner(addresses.ADDRESSES.adminAddress)

        await USDT.connect(unlockedUser).approve(vault.address, ethers.utils.parseUnits("1000000000", 18))
        await SLP.connect(unlockedUser).approve(vault.address, ethers.utils.parseUnits("1000000000", 18))
        await DAI.connect(unlockedUser).approve(vault.address, ethers.utils.parseUnits("1000000000", 18))
        await WETH.connect(unlockedUser).approve(vault.address, ethers.utils.parseUnits("1000000000", 18))
        await WETH.connect(unlockedUser).approve(SushiRouter.address, ethers.utils.parseUnits("1000000000", 18))
        await SLP.connect(unlockedUser).approve(SushiRouter.address, ethers.utils.parseUnits("1000000000", 18))
        await USDT.connect(unlockedUser).approve(SushiRouter.address, ethers.utils.parseUnits("1000000000", 18))
        await lpToken.connect(unlockedUser).approve(SushiRouter.address, ethers.utils.parseUnits("1000000000", 18))
        await lpToken.connect(unlockedUser).approve(vault.address, ethers.utils.parseUnits("1000000000", 18))

        await USDT.connect(unlockedUser2).approve(vault.address, ethers.utils.parseUnits("1000000000", 18))
        await SLP.connect(unlockedUser2).approve(vault.address, ethers.utils.parseUnits("1000000000", 18))
        await DAI.connect(unlockedUser2).approve(vault.address, ethers.utils.parseUnits("1000000000", 18))
        await WETH.connect(unlockedUser2).approve(vault.address, ethers.utils.parseUnits("1000000000", 18))
        await WETH.connect(unlockedUser2).approve(SushiRouter.address, ethers.utils.parseUnits("1000000000", 18))
        await SLP.connect(unlockedUser2).approve(SushiRouter.address, ethers.utils.parseUnits("1000000000", 18))
        await USDT.connect(unlockedUser2).approve(SushiRouter.address, ethers.utils.parseUnits("1000000000", 18))
        await lpToken.connect(unlockedUser2).approve(SushiRouter.address, ethers.utils.parseUnits("1000000000", 18))
        await lpToken.connect(unlockedUser2).approve(vault.address, ethers.utils.parseUnits("1000000000", 18))

        return { vault, USDT, SLP, DAI, WETH, lpToken, unlockedUser, unlockedUser2, adminSigner, deployer, SushiRouter }
    }

    beforeEach(async () => {
        await deployments.fixture(["oa_mainnet_deploy_pool_eth-slp"])
    })


    it("Should deploy correctly", async () => {
        const { vault, SLP, USDT, DAI, unlockedUser, unlockedUser2, adminSigner, deployer } = await setup()
        expect(await vault.communityWallet()).to.be.equal(addresses.ADDRESSES.communityWallet)
        expect(await vault.treasuryWallet()).to.be.equal(addresses.ADDRESSES.treasuryWallet)
        expect(await vault.strategist()).to.be.equal(addresses.ADDRESSES.strategist)
        expect(await vault.admin()).to.be.equal(addresses.ADDRESSES.adminAddress)

    })

    it("should work - normal flow", async () => {
        const { vault, SLP, USDT, DAI, WETH, lpToken, unlockedUser, unlockedUser2, adminSigner, deployer, SushiRouter } = await setup()
        await SushiRouter.connect(unlockedUser).swapExactTokensForTokens("10000", 0, [SLP.address, WETH.address], unlockedAddress, 32490605417);
        await SushiRouter.connect(unlockedUser).addLiquidity(SLP.address, WETH.address, "10000", ethers.utils.parseUnits("3", 18), 0, 0, unlockedAddress, 32490605417);

        await SushiRouter.connect(unlockedUser2).swapExactTokensForTokens("10000", 0, [SLP.address, WETH.address], unlockedAddress2, 32490605417);
        await SushiRouter.connect(unlockedUser2).addLiquidity(SLP.address, WETH.address, "10000", ethers.utils.parseUnits("3", 18), 0, 0, unlockedAddress2, 32490605417);

        let user1Balance = await lpToken.balanceOf(unlockedAddress);
        let user2Balance = await lpToken.balanceOf(unlockedAddress2);
        // console.log(user1Balance.toString(), user2Balance.toString())
        await vault.connect(unlockedUser).deposit(user1Balance)

        // console.log('getAllPoolInUSD', (await vault.getAllPoolInUSD()).toString())
        // console.log('getAllPoolInETH', (await vault.getAllPoolInETH()).toString())
        console.log('getPricePerFullShare', (await vault.getPricePerFullShare(true)).toString())

        await vault.connect(unlockedUser2).deposit(user2Balance)

        let shares = await vault.balanceOf(unlockedUser.address)
        console.log("SHARES", shares.toString())
        let sharesUser2 = await vault.balanceOf(unlockedUser2.address)

        // console.log(shares.toString(), sharesUser2.toString())

        await vault.connect(adminSigner).invest()

        await increaseTime(84000)
        await vault.connect(adminSigner).yield()

        await vault.connect(unlockedUser).withdraw(shares)
        await vault.connect(unlockedUser2).withdraw(sharesUser2)

        user1Balance = await lpToken.balanceOf(unlockedAddress);
        user2Balance = await lpToken.balanceOf(unlockedAddress2);
        // console.log(user1Balance.toString(), user2Balance.toString())

    })

    it("Should yield correctly", async () => {
        const { vault, strategy, SLP, USDT, WETH, lpToken, unlockedUser, unlockedUser2, adminSigner, deployer, SushiRouter } = await setup()
        await SushiRouter.connect(unlockedUser).swapExactTokensForTokens("10000", 0, [SLP.address, WETH.address], unlockedAddress, 32490605417);
        await SushiRouter.connect(unlockedUser).addLiquidity(SLP.address, WETH.address, "10000", ethers.utils.parseUnits("3", 18), 0, 0, unlockedAddress, 32490605417);

        await SushiRouter.connect(unlockedUser2).swapExactTokensForTokens("10000", 0, [SLP.address, WETH.address], unlockedAddress2, 32490605417);
        await SushiRouter.connect(unlockedUser2).addLiquidity(SLP.address, WETH.address, "10000", ethers.utils.parseUnits("3", 18), 0, 0, unlockedAddress2, 32490605417);
        let user1Balance = await lpToken.balanceOf(unlockedAddress);
        let user2Balance = await lpToken.balanceOf(unlockedAddress2);

        await vault.connect(unlockedUser).deposit(user1Balance)
        await vault.connect(unlockedUser2).deposit(user2Balance)

        await vault.connect(adminSigner).invest()
        await increaseTime(86400)//(432000)
        await mine()
        let valueInPoolBefore = await vault.balance()
        await vault.connect(adminSigner).yield()
        let valueInPoolAfter = await vault.balance()

        expect(valueInPoolAfter/* .toNumber() */).to.be.gt(valueInPoolBefore/* .toNumber() */)
    })

    it("Should withdraw all funds in emergencyWithdraw", async () => {
        const { vault, strategy, SLP, USDT, WETH, lpToken, unlockedUser, unlockedUser2, adminSigner, deployer, SushiRouter } = await setup()
        await SushiRouter.connect(unlockedUser).swapExactTokensForTokens("10000", 0, [SLP.address, WETH.address], unlockedAddress, 32490605417);
        await SushiRouter.connect(unlockedUser).addLiquidity(SLP.address, WETH.address, "10000", ethers.utils.parseUnits("3", 18), 0, 0, unlockedAddress, 32490605417);

        await SushiRouter.connect(unlockedUser2).swapExactTokensForTokens("10000", 0, [SLP.address, WETH.address], unlockedAddress2, 32490605417);
        await SushiRouter.connect(unlockedUser2).addLiquidity(SLP.address, WETH.address, "10000", ethers.utils.parseUnits("3", 18), 0, 0, unlockedAddress2, 32490605417);
        let user1Balance = await lpToken.balanceOf(unlockedAddress);
        let user2Balance = await lpToken.balanceOf(unlockedAddress2);

        await vault.connect(unlockedUser).deposit(user1Balance)
        await vault.connect(unlockedUser2).deposit(user2Balance)

        let shares = await vault.balanceOf(unlockedUser.address)
        await vault.connect(adminSigner).invest()
        await vault.connect(adminSigner).emergencyWithdraw()
        await vault.connect(unlockedUser).withdraw(shares)
        let balanceAfter = await lpToken.balanceOf(unlockedAddress);
        // console.log(balanceAfter.toString(), user1Balance.toString());
        // console.log("Withdrawn amount", (balanceAfter.sub(user1Balance)).toString())
    })
    // // 
    it("Should revert other functions on emergency", async () => {
        const { vault, strategy, SLP, USDT, WETH, lpToken, unlockedUser, unlockedUser2, adminSigner, deployer, SushiRouter } = await setup()
        await SushiRouter.connect(unlockedUser).swapExactTokensForTokens("10000", 0, [SLP.address, WETH.address], unlockedAddress, 32490605417);
        await SushiRouter.connect(unlockedUser).addLiquidity(SLP.address, WETH.address, "10000", ethers.utils.parseUnits("3", 18), 0, 0, unlockedAddress, 32490605417);

        let user1Balance = await lpToken.balanceOf(unlockedAddress);
        await vault.connect(unlockedUser).deposit(user1Balance)

        await vault.connect(adminSigner).invest()
        // 
        await vault.connect(adminSigner).emergencyWithdraw()
        await expect(vault.connect(unlockedUser).deposit(ethers.utils.parseUnits("10000", 18))).to.be.revertedWith("Deposit paused")
        await expect(vault.connect(adminSigner).invest()).to.be.revertedWith("Invest paused")
        await expect(vault.connect(adminSigner).yield()).to.be.revertedWith("yield paused")
        // 
    })

    it("Should enable all functions on reinvest", async () => {
        const { vault, strategy, SLP, USDT, WETH, lpToken, unlockedUser, unlockedUser2, adminSigner, deployer, SushiRouter } = await setup()
        await SushiRouter.connect(unlockedUser).swapExactTokensForTokens("10000", 0, [SLP.address, WETH.address], unlockedAddress, 32490605417);
        await SushiRouter.connect(unlockedUser).addLiquidity(SLP.address, WETH.address, "10000", ethers.utils.parseUnits("3", 18), 0, 0, unlockedAddress, 32490605417);

        let user1Balance = await lpToken.balanceOf(unlockedAddress);
        await vault.connect(unlockedUser).deposit(user1Balance)
        await vault.connect(adminSigner).invest()
        await increaseTime(172800)//(432000)
        await mine()
        await vault.connect(adminSigner).emergencyWithdraw()
        // 
        await vault.connect(deployer).reInvest()

        // console.log('beforeInvest')
        await vault.connect(adminSigner).invest()
        // console.log('beforeYield')
        await vault.connect(adminSigner).yield()
    })

})