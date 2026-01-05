import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { env } from "../../hardhat.config";

const name = "AuctionEntryPoint";

const func: DeployFunction = async ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) => {
  const { deployer } = await getNamedAccounts();

  const admin = env?.["AUCTION_ENTRYPOINT_OWNER"];
  const auctioneer = env?.["AUCTIONEER"];
  if (!admin || !auctioneer) {
    throw new Error("Missing environment variables");
  }

  const auctionDepositVault = await deployments.get("AuctionDepositVault");
  if (!auctionDepositVault) {
    throw new Error("AuctionDepositVault not found");
  }

  const res = await deployments.deploy(name, {
    from: deployer,
    args: [admin, auctionDepositVault.address, auctioneer],
    log: true,
  });

  console.log(`${name} deployed at ${res.address}`);
};

func.tags = [name];
export default func;
