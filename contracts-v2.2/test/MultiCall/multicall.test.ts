import { loadFixture, setCode } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { AddressBookBumped__factory, MultiCallContract__factory } from "../../typechain-types";
import { ZeroAddress } from "ethers";

const ABOOK_ADDRESS = "0x0000000000000000000000000000000000000400";

describe("Multicall", function () {
  async function baseFixture() {
    const [deployer] = await ethers.getSigners();

    const tmp = await new AddressBookBumped__factory(deployer).deploy();
    await setCode(ABOOK_ADDRESS, await ethers.provider.getCode(tmp.target));
    const addressBook = AddressBookBumped__factory.connect(ABOOK_ADDRESS, deployer);
    await addressBook.constructContract([deployer.address], 1);

    const multiCall = await new MultiCallContract__factory(deployer).deploy();
    return { addressBook, multiCall, deployer };
  }

  describe("multiCallStakingInfo", function () {
    it("returns empty arrays when AB not activated", async function () {
      const { multiCall } = await loadFixture(baseFixture);
      const [, , stakingAmounts] = await multiCall.multiCallStakingInfo();
      expect(stakingAmounts).to.have.lengthOf(0);
    });

    it("returns ZeroAddress spare when not set", async function () {
      const { multiCall } = await loadFixture(baseFixture);
      const [, , , spare] = await multiCall.multiCallStakingInfo();
      expect(spare).to.equal(ZeroAddress);
    });

    it("returns updated spare address", async function () {
      const { addressBook, multiCall } = await loadFixture(baseFixture);
      const spareAddr = ethers.getAddress("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
      await addressBook.submitUpdateSpareContract(spareAddr);
      const [, , , spare] = await multiCall.multiCallStakingInfo();
      expect(spare).to.equal(spareAddr);
    });
  });
});
