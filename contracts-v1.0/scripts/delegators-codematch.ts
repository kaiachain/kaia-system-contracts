import { delegatorConstructorArgs } from "../deploy/deploy_delegator";
import hre from "hardhat";

async function main() {
  for (let i = 0; i < delegatorConstructorArgs.length; i++) {
    console.log(`Verify ${delegatorConstructorArgs[i].delegateeNames}`);
    const deployment = await hre.deployments.get(`Delegator#${delegatorConstructorArgs[i].delegateeNames}`);
    await hre.run("verify:verify", {
      address: deployment.address,
      constructorArguments: [
        delegatorConstructorArgs[i].delegatorAddrs,
        delegatorConstructorArgs[i].delegateeAddrs,
        delegatorConstructorArgs[i].publicDelegations,
      ],
    });
  }

  console.log("All code matches done");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
