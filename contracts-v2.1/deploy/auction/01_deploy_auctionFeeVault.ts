import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { env } from "../../hardhat.config";

const name = "AuctionFeeVault";

const func: DeployFunction = async ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) => {
  const { deployer } = await getNamedAccounts();

  const admin = env?.["AUCTION_FEE_VAULT_OWNER"];
  const searcherPaybackRate = env?.["AUCTION_SEARCHER_PAYBACK_RATE"];
  const validatorPaybackRate = env?.["AUCTION_VALIDATOR_PAYBACK_RATE"];

  if (!admin || !searcherPaybackRate || !validatorPaybackRate) {
    throw new Error("Missing environment variables");
  }

  const res = await deployments.deploy(name, {
    from: deployer,
    args: [admin, searcherPaybackRate, validatorPaybackRate],
    log: true,
  });

  console.log(`${name} deployed at ${res.address}`);
};

func.tags = [name];
export default func;
