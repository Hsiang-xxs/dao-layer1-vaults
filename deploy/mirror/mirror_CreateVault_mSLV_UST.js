const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses/mirror");


module.exports = async ({ deployments }) => {
    const { deploy, catchUnknownSigner } = deployments;
    const [deployer] = await ethers.getSigners();

    let Factory = await ethers.getContract("MirrorFactory")


    let implArtifacts = await artifacts.readArtifact("MirrorVault")

    let implABI = implArtifacts.abi


    let implInterfacec = new ethers.utils.Interface(implABI)
    let data = implInterfacec.encodeFunctionData("initialize", ["DAOVaultETHUSDC", "daoETHUSDC",
        network_.MIRROR.mSLV_UST_POOL, network_.TOKENS.mSLV, network_.LPTOKENS.mSLV_UST,
        network_.ADDRESSES.treasuryWallet, network_.ADDRESSES.communityWallet, network_.ADDRESSES.strategist, network_.ADDRESSES.adminAddress])

    await Factory.connect(deployer).createVault(data)
    const vaultProxyAddress = await Factory.getVault((await Factory.totalVaults()).toNumber() - 1)

    console.log("mSLV_UST Proxy :", vaultProxyAddress);


};

module.exports.tags = ["mirror_mainnet_deploy_pool_mslv_ust"];
module.exports.dependencies = ["mirror_mainnet_deploy_factory"]