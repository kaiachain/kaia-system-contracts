import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { deployAddressBook } from "../helpers/utils";

const name = "AddressBook";
const ABOOK_ADDRESS = "0x0000000000000000000000000000000000000400";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getChainId } = hre;

  if ((await getChainId()) != "31337") {
    console.log("Skipping AddressBook deployment because it's not a localhost network");
    return;
  }
  await deployAddressBook();
  console.log(`${name} deployed at ${ABOOK_ADDRESS}`);
};

func.tags = [name];
export default func;
