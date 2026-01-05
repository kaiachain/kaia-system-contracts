import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { env } from "../../hardhat.config";

const name = "AuctionDepositVault";

const func: DeployFunction = async ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) => {
  const { deployer } = await getNamedAccounts();

  const admin = env?.["AUCTION_DEPOSIT_VAULT_OWNER"];
  if (!admin) {
    throw new Error("Missing environment variables");
  }

  const auctionFeeVault = await deployments.get("AuctionFeeVault");
  if (!auctionFeeVault) {
    throw new Error("AuctionFeeVault not found");
  }

  const res = await deployments.deploy(name, {
    from: deployer,
    args: [admin, auctionFeeVault.address],
    log: true,
  });

  console.log(`${name} deployed at ${res.address}`);
};

func.tags = [name];
export default func;
