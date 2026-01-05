import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { cnV3PublicDelegationFixture } from "./publicDelegation";
import { Delegator__factory } from "../../../typechain-types";

export async function delegatorTestFixture() {
  const fixture = await loadFixture(cnV3PublicDelegationFixture);
  // [cnV3s, pd1, pd2, deployer, user1, user2, user3]

  const delegatorContract = await new Delegator__factory(fixture.deployer).deploy(
    fixture.deployer.address,
    fixture.contractValidator.address,
    fixture.pd1.target,
  );

  return {
    delegator: fixture.deployer,
    delegatee: fixture.contractValidator,
    cn: fixture.cnV3s[0],
    pd: fixture.pd1,
    dc: delegatorContract,
    user: fixture.user1,
  };
}
