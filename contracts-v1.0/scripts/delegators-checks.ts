import { delegatorConstructorArgs } from "../deploy/deploy_delegator";
import hre from "hardhat";

async function main() {
  for (let i = 0; i < delegatorConstructorArgs.length; i++) {
    console.log(`Checking ${delegatorConstructorArgs[i].delegateeNames}`);

    const deployment = await hre.deployments.get(`Delegator#${delegatorConstructorArgs[i].delegateeNames}`);
    const res = await hre.ethers.getContractAt(deployment.abi, deployment.address);
    const artifact = await hre.artifacts.readArtifact("Delegator");
    console.log("1. Check bytecode");
    console.assert(deployment.deployedBytecode === artifact.deployedBytecode, "Bytecode does not match");

    console.log("2. Check delegator address");
    console.assert(
      (await res.getRoleMember(await res.DELEGATOR_ROLE(), 0)).toLowerCase() ===
        delegatorConstructorArgs[i].delegatorAddrs.toLowerCase(),
      "Delegator address mismatch",
    );
    console.log("3. Check delegatee address");
    console.assert(
      (await res.getRoleMember(await res.DELEGATEE_ROLE(), 0)).toLowerCase() ===
        delegatorConstructorArgs[i].delegateeAddrs.toLowerCase(),
      "Delegatee address mismatch",
    );
    console.log("4. Check public delegation address");
    console.assert(
      (await res.PD()).toLowerCase() === delegatorConstructorArgs[i].publicDelegations.toLowerCase(),
      "Public delegation address mismatch",
    );
    console.log("-----------------------------------");
  }

  console.log("All checks done");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
