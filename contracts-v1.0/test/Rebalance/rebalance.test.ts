import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { executionBlock, memo, rebalanceTestFixture, value } from "../materials";
import { parseEther, ZeroAddress } from "ethers";
import hre from "hardhat";

type UnPromisify<T> = T extends Promise<infer U> ? U : T;

/**
 * @dev This test is for TreasuryRebalanceV2.sol
 */
describe("TreasuryRebalanceV2", function () {
  let fixture: UnPromisify<ReturnType<typeof rebalanceTestFixture>>;
  beforeEach(async function () {
    fixture = await loadFixture(rebalanceTestFixture);
  });
  describe("Deploy", function () {
    it("Should set the correct initial values for main treasuryRebalanceV2", async function () {
      const { trV2 } = fixture;
      const currentBlock = await ethers.provider.getBlockNumber();
      expect(await trV2.status()).to.equal(0);
      expect(await trV2.getTreasuryAmount()).to.equal(0);
      expect(await trV2.rebalanceBlockNumber()).to.be.greaterThan(currentBlock);
    });

    it("Should revert if the rebalance block number is less than current block", async function () {
      const REBALANCE = await ethers.getContractFactory("TreasuryRebalanceV2");
      const currentBlock = await ethers.provider.getBlockNumber();
      await expect(REBALANCE.deploy(currentBlock)).to.be.revertedWith(
        "rebalance blockNumber should be greater than current block",
      );
    });
  });

  describe("registerZeroed", async function () {
    it("Should add a zeroed and emit a RegisterZeroed event", async function () {
      const { trV2, zeroed1 } = fixture;
      await expect(trV2.registerZeroed(zeroed1.target)).to.emit(trV2, "ZeroedRegistered").withArgs(zeroed1.target);
      const zeroedInfo = await trV2.getZeroed(zeroed1.target);
      expect(zeroedInfo[0]).to.equal(zeroed1.target);
      expect(zeroedInfo[1].length).to.equal(0);
    });

    it("Should not allow non-owner to add a zeroed", async function () {
      const { trV2, zeroedAdmins, zeroed2 } = fixture;
      await expect(trV2.connect(zeroedAdmins[0]).registerZeroed(zeroed2.target)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Should not allow adding the same zeroed twice", async function () {
      const { trV2, zeroed2 } = fixture;
      await trV2.registerZeroed(zeroed2.target);
      expect(await trV2.zeroedExists(zeroed2.target)).to.equal(true);
      await expect(trV2.registerZeroed(zeroed2.target)).to.be.revertedWith("Zeroed address is already registered");
    });

    it("Should revert if the zeroed address is zero", async function () {
      const { trV2 } = fixture;
      await expect(trV2.registerZeroed(ZeroAddress)).to.be.revertedWith("Invalid address");
    });

    it("zeroeds length should be two", async function () {
      const { trV2, zeroed1, zeroed2 } = fixture;
      await trV2.registerZeroed(zeroed1.target);
      await trV2.registerZeroed(zeroed2.target);
      expect(await trV2.getZeroedCount()).to.equal(2);
    });
  });

  describe("removeZeroed", function () {
    this.beforeEach(async function () {
      const { trV2, zeroed1, zeroed2 } = fixture;
      await trV2.registerZeroed(zeroed1.target);
      await trV2.registerZeroed(zeroed2.target);
    });

    it("Should remove a zeroed and emit a RemoveZeroed event", async function () {
      const { trV2, zeroed1 } = fixture;
      await expect(trV2.removeZeroed(zeroed1.target)).to.emit(trV2, "ZeroedRemoved").withArgs(zeroed1.target);
      await expect(trV2.getZeroed(zeroed1.target)).to.be.revertedWith("Zeroed not registered");
    });

    it("Should not allow removing a non-existent zeroed", async function () {
      const { trV2, rebalance_manager } = fixture;
      await expect(trV2.removeZeroed(rebalance_manager.address)).to.be.revertedWith("Zeroed not registered");
    });

    it("Should not allow non-owner to remove a zeroed", async function () {
      const { trV2, zeroedAdmins, zeroed2 } = fixture;
      await expect(trV2.connect(zeroedAdmins[0]).removeZeroed(zeroed2.target)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });
  });

  describe("registerAllocated", function () {
    it("Should register allocated address and its fund distribution and emit a RegisterAllocated event", async function () {
      const { trV2, allocated1 } = fixture;
      const amount = parseEther("20");

      await expect(trV2.registerAllocated(allocated1.address, amount))
        .to.emit(trV2, "AllocatedRegistered")
        .withArgs(allocated1.address, amount);
      const allocateds = await trV2.getAllocated(allocated1.address);
      expect(allocateds[0]).to.equal(allocated1.address);
      expect(allocateds[1]).to.equal(amount);
      expect(await trV2.getAllocatedCount()).to.equal(1);

      const treasuryAmount = await trV2.getTreasuryAmount();
      expect(treasuryAmount).to.equal(amount);
    });

    it("Should revert if register allocated twice", async function () {
      const { trV2, allocated1 } = fixture;
      const amount = parseEther("20");
      const amount1 = parseEther("20");

      await expect(trV2.registerAllocated(allocated1.address, amount))
        .to.emit(trV2, "AllocatedRegistered")
        .withArgs(allocated1.address, amount);
      expect(await trV2.allocatedExists(allocated1.address)).to.equal(true);
      await expect(trV2.registerAllocated(allocated1.address, amount1)).to.be.revertedWith(
        "Allocated address is already registered",
      );
    });

    it("Should not allow non-owner to add a allocated", async function () {
      const { trV2, zeroedAdmins, allocated1 } = fixture;
      const amount1 = parseEther("20");
      await expect(trV2.connect(zeroedAdmins[0]).registerAllocated(allocated1.address, amount1)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Should revert if the allocated address is zero", async function () {
      const { trV2 } = fixture;
      const amount1 = parseEther("20");
      await expect(trV2.registerAllocated(ZeroAddress, amount1)).to.be.revertedWith("Invalid address");
    });

    it("Should revert if the amount is set to 0", async function () {
      const { trV2, allocated2 } = fixture;
      await expect(trV2.registerAllocated(allocated2.address, 0)).to.be.revertedWith("Amount cannot be set to 0");
    });
  });

  describe("removeAllocated", function () {
    this.beforeEach(async function () {
      const { trV2, allocated1, allocated2 } = fixture;

      await trV2.registerAllocated(allocated1.address, value);
      await trV2.registerAllocated(allocated2.address, value);
    });

    it("Should remove allocated and emit RemoveAllocated event", async function () {
      const { trV2, allocated1 } = fixture;
      await expect(trV2.removeAllocated(allocated1.address))
        .to.emit(trV2, "AllocatedRemoved")
        .withArgs(allocated1.address);
      expect(await trV2.getAllocatedCount()).to.equal(1);
      expect(await trV2.getTreasuryAmount()).to.equal(value);
      await expect(trV2.getAllocated(allocated1.address)).to.be.revertedWith("Allocated not registered");
    });

    it("Should not remove unregistered allocated", async function () {
      const { trV2, allocated1 } = fixture;
      await expect(trV2.removeAllocated(allocated1.address))
        .to.emit(trV2, "AllocatedRemoved")
        .withArgs(allocated1.address);
      await expect(trV2.removeAllocated(allocated1.address)).to.be.reverted;
    });

    it("Should not allow non-owner to remove a allocated", async function () {
      const { trV2, allocated2 } = fixture;
      await expect(trV2.connect(allocated2).removeAllocated(allocated2.address)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });
  });

  describe("approve", function () {
    this.beforeEach(async function () {
      const { trV2, zeroed1, eoaZeroed, mockZeroed3, allocated1, allocated2 } = fixture;

      await trV2.registerZeroed(zeroed1.target);
      await trV2.registerZeroed(eoaZeroed.address);
      await trV2.registerZeroed(mockZeroed3.target);
      await trV2.registerAllocated(allocated1.address, value);
      await trV2.registerAllocated(allocated2.address, value);
      await trV2.finalizeRegistration();
    });

    it("Should approve zeroed contract if msg.sender is an admin of zeroed", async function () {
      const { trV2, zeroed1, zeroedAdmins } = fixture;
      const zeroed = await trV2.getZeroed(zeroed1.target);
      expect(zeroed[1].length).to.equal(0);
      const tx = await trV2.connect(zeroedAdmins[0]).approve(zeroed1.target);

      const updatedZeroedDetails = await trV2.getZeroed(zeroed1.target);
      expect(updatedZeroedDetails[1][0]).to.equal(zeroedAdmins[0].address);

      await expect(tx).to.emit(trV2, "Approved").withArgs(zeroed1.target, zeroedAdmins[0].address, 1);
    });

    it("Should approve zeroed eoa if msg.sender is same as zeroed eoa", async function () {
      const { trV2, eoaZeroed } = fixture;
      const zeroed = await trV2.getZeroed(eoaZeroed.address);
      expect(zeroed[0]).to.equal(eoaZeroed.address);
      await trV2.connect(eoaZeroed).approve(eoaZeroed.address);
    });

    it("Should revert if zeroed is already approved", async function () {
      const { trV2, eoaZeroed } = fixture;
      await trV2.connect(eoaZeroed).approve(eoaZeroed.address);
      await expect(trV2.connect(eoaZeroed).approve(eoaZeroed.address)).to.be.revertedWith("Already approved");
    });

    it("Should revert if zeroed is not registered", async function () {
      const { trV2, zeroed2 } = fixture;
      await expect(trV2.approve(zeroed2.target)).to.be.revertedWith("zeroed needs to be registered before approval");
    });

    it("Should revert if zeroed is a EOA and if msg.sender is not the admin of zeroed", async function () {
      const { trV2, eoaZeroed } = fixture;
      await expect(trV2.approve(eoaZeroed.address)).to.be.revertedWith("zeroedAddress is not the msg.sender");
    });

    it("Should revert if zeroed is a contract address but does not have getState() method", async function () {
      const { trV2, mockZeroed3 } = fixture;
      await mockZeroed3.mockSetShouldRevert(true);
      await expect(trV2.approve(mockZeroed3.target)).to.be.revertedWithoutReason();
    });

    it("Should revert if zeroed is a contract but adminList is empty", async function () {
      const { trV2, mockZeroed3 } = fixture;
      await expect(trV2.approve(mockZeroed3.target)).to.be.revertedWith("admin list cannot be empty");
    });

    it("Should not approve if zeroed is a contract but msg.sender is not the admin", async function () {
      const { trV2, eoaZeroed, zeroed1 } = fixture;
      await expect(trV2.connect(eoaZeroed).approve(zeroed1.target)).to.be.revertedWith("msg.sender is not the admin");
    });
  });

  describe("setStatus", function () {
    describe("FinalizeRegistration", async function () {
      this.beforeEach(async function () {
        const { trV2, zeroed1, allocated1 } = fixture;

        await trV2.registerZeroed(zeroed1.target);
        await trV2.registerAllocated(allocated1.address, value);
      });

      it("should set status to Registered and emit StatusChanged event", async function () {
        const { trV2 } = fixture;
        await expect(trV2.finalizeRegistration()).to.emit(trV2, "StatusChanged").withArgs(1);
        expect(await trV2.status()).to.equal(1);
      });

      it("Should not register zeroed when contract is not in Initialized state", async function () {
        const { trV2, zeroed2 } = fixture;
        await expect(trV2.finalizeRegistration()).to.emit(trV2, "StatusChanged").withArgs(1);
        await expect(trV2.registerZeroed(zeroed2.target)).to.be.revertedWith("Not in the designated status");
      });
      it("Should not register allocated when contract is not in Initialized state", async function () {
        const { trV2, allocated1 } = fixture;
        await expect(trV2.finalizeRegistration()).to.emit(trV2, "StatusChanged").withArgs(1);
        await expect(trV2.registerAllocated(allocated1.address, value)).to.be.revertedWith(
          "Not in the designated status",
        );
      });
      it("Should revert if the current status is tried to set again", async function () {
        const { trV2 } = fixture;
        await expect(trV2.finalizeRegistration()).to.emit(trV2, "StatusChanged").withArgs(1);
        await expect(trV2.finalizeRegistration()).to.be.revertedWith("Not in the designated status");
      });

      it("Should revert if owner tries to set pendingMemo after Registered", async function () {
        const { trV2 } = fixture;
        await expect(trV2.setPendingMemo(memo)).to.be.revertedWith("Not in the designated status");
      });
      it("should revert if not called by the owner", async () => {
        const { trV2, zeroedAdmins } = fixture;
        await expect(trV2.connect(zeroedAdmins[0]).finalizeRegistration()).to.be.revertedWith(
          "Ownable: caller is not the owner",
        );
      });
      it("Should not remove allocated when contract is not in Initialized state", async function () {
        const { trV2, allocated1 } = fixture;
        await expect(trV2.finalizeRegistration()).to.emit(trV2, "StatusChanged").withArgs(1);
        await expect(trV2.removeAllocated(allocated1.address)).to.be.revertedWith("Not in the designated status");
      });
      it("Should not remove zeroed when contract is not in Initialized state", async function () {
        const { trV2, zeroed2 } = fixture;
        await expect(trV2.finalizeRegistration()).to.emit(trV2, "StatusChanged").withArgs(1);
        await expect(trV2.removeZeroed(zeroed2.target)).to.be.revertedWith("Not in the designated status");
      });
    });

    describe("FinalizeApproval", async function () {
      this.beforeEach(async function () {
        const { trV2, zeroedAdmins, zeroed1, allocated1 } = fixture;

        await trV2.registerZeroed(zeroed1.target);
        await trV2.registerAllocated(allocated1.address, value);
        await trV2.finalizeRegistration();
        await trV2.connect(zeroedAdmins[0]).approve(zeroed1.target);
        await trV2.connect(zeroedAdmins[1]).approve(zeroed1.target);
      });
      it("should set status to Approved and emit StatusChanged event", async function () {
        const { trV2 } = fixture;
        await expect(trV2.finalizeApproval()).to.emit(trV2, "StatusChanged").withArgs(2);
        expect(await trV2.status()).to.equal(2);
      });
      it("should revert if owner tries to set Registered after Approved", async function () {
        const { trV2 } = fixture;
        await expect(trV2.finalizeRegistration()).to.be.revertedWith("Not in the designated status");
      });
      it("should revert if not called by the owner", async () => {
        const { trV2, zeroedAdmins } = fixture;
        await expect(trV2.connect(zeroedAdmins[0]).finalizeApproval()).to.be.revertedWith(
          "Ownable: caller is not the owner",
        );
      });
    });

    describe("Should revert finalizeApproval if zeroed contract can't reach Quorom", function () {
      beforeEach("Should set status to Approved and emit StatusChanged event", async function () {
        const { trV2, allocated1 } = fixture;

        await trV2.registerAllocated(allocated1.address, value);
      });

      it("Should revert if min required admins does not approve", async function () {
        const { trV2, zeroed1 } = fixture;
        await trV2.registerZeroed(zeroed1.target);
        await trV2.finalizeRegistration();
        await expect(trV2.finalizeApproval()).to.be.revertedWith("min required admins should approve");
      });

      it("Should revert if approved admin change during the contract ", async function () {
        const { trV2, mockZeroed3, rebalance_manager, zeroedAdmins } = fixture;
        await trV2.registerZeroed(mockZeroed3.target);
        await trV2.finalizeRegistration();
        await mockZeroed3.mockSetAdminList([rebalance_manager.address]);
        await mockZeroed3.mockSetRequirement(1);
        await trV2.approve(mockZeroed3.target);
        await mockZeroed3.mockSetAdminList([rebalance_manager.address, zeroedAdmins[0].address]);
        await mockZeroed3.mockSetRequirement(2);
        await expect(trV2.finalizeApproval()).to.be.revertedWith("min required admins should approve");
      });

      it("Should revert if EOA did not approve", async function () {
        const { trV2, eoaZeroed } = fixture;
        await trV2.registerZeroed(eoaZeroed.address);
        await trV2.finalizeRegistration();
        await expect(trV2.finalizeApproval()).to.be.revertedWith("EOA should approve");
        await trV2.connect(eoaZeroed).approve(eoaZeroed.address);
        await trV2.finalizeApproval();
      });
    });

    // TreasuryRebalance - below test should not pass
    // TreasuryRebalanceV2 - below test should pass
    it("Should set status to Approved when treasury amount exceeds balance of zeroeds", async function () {
      const { trV2, zeroed1, allocated1, allocated2, zeroedAdmins } = fixture;

      const amount = parseEther("50");
      await trV2.registerZeroed(zeroed1.target);
      await trV2.registerAllocated(allocated1.address, value);
      await trV2.registerAllocated(allocated2.address, amount);
      await trV2.finalizeRegistration();
      await trV2.connect(zeroedAdmins[0]).approve(zeroed1.target);
      await trV2.connect(zeroedAdmins[1]).approve(zeroed1.target);
      await trV2.finalizeApproval();
      expect(await trV2.status()).to.equal(2);
    });

    it("Should revert if owner tries to set Approved before Registered", async function () {
      const { trV2 } = fixture;
      await expect(trV2.finalizeApproval()).to.be.revertedWith("Not in the designated status");
    });
  });

  describe("reset", function () {
    it("should reset all storage values except rebalance blocknumber to 0 at Initialize state", async function () {
      const { trV2 } = fixture;
      await trV2.reset();
      expect(await trV2.getZeroedCount()).to.equal(0);
      expect(await trV2.getAllocatedCount()).to.equal(0);
      expect(await trV2.getTreasuryAmount()).to.equal(0);
      expect(await trV2.memo()).to.equal("");
      expect(await trV2.status()).to.equal(0);
      expect(await trV2.rebalanceBlockNumber()).to.not.equal(0);
    });

    it("should reset all storage values except rebalance blocknumber to 0 at Registered state", async function () {
      const { trV2, zeroed1, zeroed2, allocated1, allocated2 } = fixture;
      await trV2.registerZeroed(zeroed1.target);
      await trV2.registerZeroed(zeroed2.target);
      await trV2.registerAllocated(allocated1.address, value);
      await trV2.registerAllocated(allocated2.address, value);
      await trV2.finalizeRegistration();
      expect(await trV2.getZeroedCount()).to.equal(2);
      expect(await trV2.getAllocatedCount()).to.equal(2);

      await trV2.reset();
      expect(await trV2.getZeroedCount()).to.equal(0);
      expect(await trV2.getAllocatedCount()).to.equal(0);
      expect(await trV2.getTreasuryAmount()).to.equal(0);
      expect(await trV2.memo()).to.equal("");
      expect(await trV2.status()).to.equal(0);
      expect(await trV2.rebalanceBlockNumber()).to.not.equal(0);
    });

    it("should reset all storage values except rebalance blocknumber to 0 at Approved state", async function () {
      const { trV2, zeroed1, zeroed2, allocated1, allocated2, zeroedAdmins } = fixture;
      await trV2.registerZeroed(zeroed1.target);
      await trV2.registerZeroed(zeroed2.target);
      await trV2.registerAllocated(allocated1.address, value);
      await trV2.registerAllocated(allocated2.address, value);
      await trV2.finalizeRegistration();
      await trV2.connect(zeroedAdmins[0]).approve(zeroed1.target);
      await trV2.connect(zeroedAdmins[1]).approve(zeroed1.target);
      await trV2.connect(zeroedAdmins[2]).approve(zeroed2.target);
      await trV2.connect(zeroedAdmins[3]).approve(zeroed2.target);
      await trV2.finalizeApproval();

      expect(await trV2.getZeroedCount()).to.equal(2);
      expect(await trV2.getAllocatedCount()).to.equal(2);

      await trV2.reset();
      expect(await trV2.getZeroedCount()).to.equal(0);
      expect(await trV2.getAllocatedCount()).to.equal(0);
      expect(await trV2.getTreasuryAmount()).to.equal(0);
      expect(await trV2.memo()).to.equal("");
      expect(await trV2.status()).to.equal(0);
      expect(await trV2.rebalanceBlockNumber()).to.not.equal(0);
    });

    it("Should not allow non-owner to reset", async function () {
      const { trV2, zeroedAdmins } = fixture;
      await expect(trV2.connect(zeroedAdmins[0]).reset()).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("updateRebalanceBlocknumber", async function () {
    it("should revert if current block is larger than rebalanceBlockNumber", async function () {
      const { trV2 } = fixture;
      await expect(trV2.updateRebalanceBlocknumber(await ethers.provider.getBlockNumber())).to.be.revertedWith(
        "rebalance blockNumber should be greater than current block",
      );
    });
    it("should set rebalance blocknumber if current block is smaller than rebalanceBlockNumber", async function () {
      const { trV2 } = fixture;
      await trV2.updateRebalanceBlocknumber(executionBlock + 10);
      expect(await trV2.rebalanceBlockNumber()).to.equal(executionBlock + 10);
      await trV2.updateRebalanceBlocknumber(executionBlock);
      expect(await trV2.rebalanceBlockNumber()).to.equal(executionBlock);
    });
  });

  describe("finalizeContract", function () {
    this.beforeEach(async function () {
      const { trV2, zeroed1, zeroed2, allocated1, allocated2, zeroedAdmins } = fixture;

      await trV2.registerZeroed(zeroed1.target);
      await trV2.registerZeroed(zeroed2.target);
      await trV2.registerAllocated(allocated1.address, value);
      await trV2.registerAllocated(allocated2.address, value);
      await trV2.finalizeRegistration();
      await trV2.connect(zeroedAdmins[0]).approve(zeroed1.target);
      await trV2.connect(zeroedAdmins[1]).approve(zeroed1.target);
      await trV2.connect(zeroedAdmins[2]).approve(zeroed2.target);
      await trV2.connect(zeroedAdmins[3]).approve(zeroed2.target);
      await trV2.finalizeApproval();
    });
    it("should revert finalizeContract before rebalanceBlockNumber", async () => {
      const { trV2 } = fixture;
      await expect(trV2.finalizeContract()).to.be.revertedWith(
        "Contract can only finalize after executing rebalancing",
      );
    });
    it("should revert finalizeContract when pendingMemo is never initialized", async function () {
      const { trV2 } = fixture;
      await hre.network.provider.send("hardhat_mine", ["0xC8"]);
      await expect(trV2.finalizeContract()).to.be.revertedWith("no pending memo, cannot finalize without memo");
    });
    it("should set pendingMemo repeatedly before finalizeContract", async function () {
      const { trV2 } = fixture;
      await trV2.setPendingMemo("testMemo");
      expect(await trV2.pendingMemo()).to.equal("testMemo");
      await trV2.setPendingMemo(memo);
      expect(await trV2.pendingMemo()).to.equal(memo);
      await trV2.setPendingMemo("");
      expect(await trV2.pendingMemo()).to.equal("");
    });
    it("should revert finalizeContract when pendingMemo has no memo", async function () {
      const { trV2 } = fixture;
      await hre.network.provider.send("hardhat_mine", ["0xC8"]);
      await expect(trV2.finalizeContract()).to.be.revertedWith("no pending memo, cannot finalize without memo");
    });
    it("should set pendingMemo after executing rebalance", async function () {
      const { trV2 } = fixture;
      await trV2.setPendingMemo(memo);
      expect(await trV2.pendingMemo()).to.equal(memo);
    });
    it("should set status to Finalized and emit Finalize event", async function () {
      const { trV2 } = fixture;
      await trV2.setPendingMemo(memo);
      await hre.network.provider.send("hardhat_mine", ["0xC8"]);
      await expect(trV2.finalizeContract()).to.emit(trV2, "Finalized").withArgs(memo, 3);
      expect(await trV2.memo()).to.equal(memo);
    });
  });
});
