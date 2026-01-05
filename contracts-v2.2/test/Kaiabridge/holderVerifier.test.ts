import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { HolderVerifier, KAIABridge, Operator, Guardian, Judge } from "../../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("HolderVerifier", function () {
  let holderVerifier: HolderVerifier;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let nonOwner: SignerWithAddress;
  let bridge: KAIABridge;
  let operator: Operator;
  let guardian: Guardian;
  let judge: Judge;

  const CONV_RATE = 148079656000000n;
  const fnsaAddr1 = "link1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz";
  const fnsaAddr2 = "link1def456ghi789jkl012mno345pqr678stu901vwx234yzabc123";
  const fnsaAddr3 = "link1ghi789jkl012mno345pqr678stu901vwx234yzabc123def456";
  const valoperAddr1 = "linkvaloper1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz";
  const conyBalance1 = ethers.parseUnits("1000", 6);
  const conyBalance2 = ethers.parseUnits("2000", 6);
  const conyBalance3 = ethers.parseUnits("3000", 6);

  const mockPublicKey = "0x" + "04" + "11".repeat(64);
  const mockSignature = "0x" + "11".repeat(65);
  const mockMessageHash = ethers.keccak256(ethers.toUtf8Bytes("message"));
  const kaiabridgeMessageFor = (address: string) => "kaiabridge" + address.toLowerCase();
  const signKlaytnPrefixedMessage = (wallet: any, address: string) => {
    const message = kaiabridgeMessageFor(address);
    const prefix = "\x19Klaytn Signed Message:\n52";
    const hash = ethers.keccak256(ethers.concat([ethers.toUtf8Bytes(prefix), ethers.toUtf8Bytes(message)]));
    const sig = wallet.signingKey.sign(hash).serialized;
    return sig;
  };

  beforeEach(async function () {
    [owner, user1, nonOwner] = await ethers.getSigners();

    const guardianFactory = await ethers.getContractFactory("Guardian", owner);
    guardian = (await upgrades.deployProxy(guardianFactory, [[owner.address], 1])) as unknown as Guardian;
    await guardian.waitForDeployment();

    const operatorFactory = await ethers.getContractFactory("Operator", owner);
    operator = (await upgrades.deployProxy(operatorFactory, [
      [owner.address],
      await guardian.getAddress(),
      1,
    ])) as unknown as Operator;
    await operator.waitForDeployment();

    const judgeFactory = await ethers.getContractFactory("Judge", owner);
    judge = (await upgrades.deployProxy(judgeFactory, [
      [owner.address],
      await guardian.getAddress(),
      1,
    ])) as unknown as Judge;
    await judge.waitForDeployment();

    const bridgeFactory = await ethers.getContractFactory("KAIABridge", owner);
    bridge = (await upgrades.deployProxy(bridgeFactory, [
      await operator.getAddress(),
      await guardian.getAddress(),
      await judge.getAddress(),
      3,
    ])) as unknown as KAIABridge;
    await bridge.waitForDeployment();

    const bridgeAddr = await bridge.getAddress();
    const rawTxData = (await operator.changeBridge.populateTransaction(bridgeAddr)).data;
    await guardian.submitTransaction(await operator.getAddress(), rawTxData!, 0);

    const timelockData = (await bridge.changeTransferTimeLock.populateTransaction(0)).data;
    await guardian.submitTransaction(bridgeAddr, timelockData!, 0);

    const holderVerifierFactory = await ethers.getContractFactory("HolderVerifier", owner);
    holderVerifier = (await holderVerifierFactory.deploy(await operator.getAddress())) as unknown as HolderVerifier;
    await holderVerifier.waitForDeployment();

    const holderVerifierAddr = await holderVerifier.getAddress();
    const addOperatorData = (await operator.addOperator.populateTransaction(holderVerifierAddr)).data;
    await guardian.submitTransaction(await operator.getAddress(), addOperatorData!, 0);

    await owner.sendTransaction({ to: bridgeAddr, value: ethers.parseEther("1000") });
  });

  describe("Deployment", function () {
    it("sets the right owner", async function () {
      expect(await holderVerifier.owner()).to.equal(owner.address);
    });

    it("initializes statistics to zero", async function () {
      expect(await holderVerifier.allConyBalances()).to.equal(0);
      expect(await holderVerifier.provisionedConyBalances()).to.equal(0);
      expect(await holderVerifier.provisionedAccounts()).to.equal(0);
      expect(await holderVerifier.getRecordCount()).to.equal(0);
    });

    it("has correct conversion rate", async function () {
      expect(await holderVerifier.CONV_RATE()).to.equal(CONV_RATE);
    });

    it("has correct operator address", async function () {
      expect(await holderVerifier.operator()).to.equal(await operator.getAddress());
    });
  });

  describe("Record Management", function () {
    describe("addRecord", function () {
      it("adds a record for new address", async function () {
        await expect(holderVerifier.addRecord(fnsaAddr1, conyBalance1))
          .to.emit(holderVerifier, "RecordAdded")
          .withArgs(fnsaAddr1, conyBalance1);

        expect(await holderVerifier.conyBalances(fnsaAddr1)).to.equal(conyBalance1);
        expect(await holderVerifier.provisionSeq(fnsaAddr1)).to.equal(0n);
        expect(await holderVerifier.allConyBalances()).to.equal(conyBalance1);
        expect(await holderVerifier.provisionedConyBalances()).to.equal(0);
        expect(await holderVerifier.provisionedAccounts()).to.equal(0);
      });

      it("updates an existing record", async function () {
        await holderVerifier.addRecord(fnsaAddr1, conyBalance1);
        const newBalance = ethers.parseUnits("1500", 6);
        await holderVerifier.addRecord(fnsaAddr1, newBalance);

        expect(await holderVerifier.conyBalances(fnsaAddr1)).to.equal(newBalance);
        expect(await holderVerifier.allConyBalances()).to.equal(newBalance);
        expect(await holderVerifier.provisionedConyBalances()).to.equal(0);
        expect(await holderVerifier.provisionedAccounts()).to.equal(0);
      });

      it("reverts when called by non-owner", async function () {
        await expect(holderVerifier.connect(nonOwner).addRecord(fnsaAddr1, conyBalance1)).to.be.revertedWithCustomError(
          holderVerifier,
          "OwnableUnauthorizedAccount",
        );
      });

      it("reverts on empty address", async function () {
        await expect(holderVerifier.addRecord("", conyBalance1)).to.be.revertedWith("HolderVerifier: empty fnsaAddr");
      });

      it("reverts on zero balance", async function () {
        await expect(holderVerifier.addRecord(fnsaAddr1, 0)).to.be.revertedWith("HolderVerifier: zero conyBalance");
      });

      it("accepts valoper addresses", async function () {
        await holderVerifier.addRecord(valoperAddr1, conyBalance1);

        expect(await holderVerifier.conyBalances(valoperAddr1)).to.equal(conyBalance1);
        expect(await holderVerifier.provisionedAccounts()).to.equal(0);
      });
    });

    describe("addRecords", function () {
      it("adds multiple records", async function () {
        await expect(
          holderVerifier.addRecords([fnsaAddr1, fnsaAddr2, fnsaAddr3], [conyBalance1, conyBalance2, conyBalance3]),
        )
          .to.emit(holderVerifier, "RecordsAdded")
          .withArgs(3);

        expect(await holderVerifier.allConyBalances()).to.equal(conyBalance1 + conyBalance2 + conyBalance3);
        expect(await holderVerifier.provisionedConyBalances()).to.equal(0);
        expect(await holderVerifier.provisionedAccounts()).to.equal(0);
      });

      it("reverts on mismatched array length", async function () {
        await expect(holderVerifier.addRecords([fnsaAddr1, fnsaAddr2], [conyBalance1])).to.be.revertedWith(
          "HolderVerifier: array length mismatch",
        );
      });

      it("reverts on empty arrays", async function () {
        await expect(holderVerifier.addRecords([], [])).to.be.revertedWith("HolderVerifier: empty arrays");
      });
    });
  });

  describe("Configuration", function () {
    it("allows owner to change operator", async function () {
      const newOperatorFactory = await ethers.getContractFactory("Operator", owner);
      const newOperator = (await upgrades.deployProxy(newOperatorFactory, [
        [owner.address],
        await guardian.getAddress(),
        1,
      ])) as unknown as Operator;
      await newOperator.waitForDeployment();

      const currentOperatorAddress = await operator.getAddress();
      const newOperatorAddress = await newOperator.getAddress();

      await expect(holderVerifier.changeOperator(newOperatorAddress))
        .to.emit(holderVerifier, "OperatorChanged")
        .withArgs(currentOperatorAddress, newOperatorAddress);

      expect(await holderVerifier.operator()).to.equal(newOperatorAddress);
    });

    it("prevents non-owner from changing operator", async function () {
      await expect(
        holderVerifier.connect(nonOwner).changeOperator(await operator.getAddress()),
      ).to.be.revertedWithCustomError(holderVerifier, "OwnableUnauthorizedAccount");
    });

    it("prevents changing operator to zero address", async function () {
      await expect(holderVerifier.changeOperator("0x0000000000000000000000000000000000000000")).to.be.revertedWith(
        "HolderVerifier: operator zero address",
      );
    });
  });

  describe("Statistics", function () {
    beforeEach(async function () {
      await holderVerifier.addRecords([fnsaAddr1, fnsaAddr2, fnsaAddr3], [conyBalance1, conyBalance2, conyBalance3]);
    });

    it("tracks totals correctly", async function () {
      expect(await holderVerifier.allConyBalances()).to.equal(conyBalance1 + conyBalance2 + conyBalance3);
      expect(await holderVerifier.provisionedConyBalances()).to.equal(0);
      expect(await holderVerifier.provisionedAccounts()).to.equal(0);
    });

    it("updates metrics when a record is updated", async function () {
      const updated = ethers.parseUnits("4000", 6);
      await holderVerifier.addRecord(fnsaAddr1, updated);
      expect(await holderVerifier.allConyBalances()).to.equal(updated + conyBalance2 + conyBalance3);
      expect(await holderVerifier.provisionedConyBalances()).to.equal(0);
    });
  });

  describe("View functions", function () {
    beforeEach(async function () {
      await holderVerifier.addRecords([fnsaAddr1, fnsaAddr2, fnsaAddr3], [conyBalance1, conyBalance2, conyBalance3]);
    });

    it("getRecord returns data", async function () {
      const [balance, seq] = await holderVerifier.getRecord(fnsaAddr1);
      expect(balance).to.equal(conyBalance1);
      expect(seq).to.equal(0n);
    });

    it("getRecord returns zero for unknown", async function () {
      const [balance, seq] = await holderVerifier.getRecord("link1unknown");
      expect(balance).to.equal(0);
      expect(seq).to.equal(0n);
    });

    it("getRecords returns paginated data", async function () {
      const [addresses, balances, seqs] = await holderVerifier.getRecords(1, 2);
      expect(addresses).to.deep.equal([fnsaAddr2, fnsaAddr3]);
      expect(balances).to.deep.equal([conyBalance2, conyBalance3]);
      expect(seqs).to.deep.equal([0n, 0n]);
    });

    it("getRecords reverts on startIdx out of bounds", async function () {
      await expect(holderVerifier.getRecords(10, 1)).to.be.revertedWith("HolderVerifier: startIdx out of bounds");
    });

    it("getFnsaAddrsLength returns length", async function () {
      expect(await holderVerifier.getRecordCount()).to.equal(3);
    });
  });

  describe("Access control", function () {
    it("allows owner to transfer ownership", async function () {
      await holderVerifier.transferOwnership(user1.address);
      expect(await holderVerifier.owner()).to.equal(user1.address);
    });
  });

  describe("Error cases", function () {
    beforeEach(async function () {
      await holderVerifier.addRecord(fnsaAddr1, conyBalance1);
    });

    it("reverts with invalid public key length", async function () {
      const invalidPubKey = "0x" + "04" + "11".repeat(32);
      await expect(
        holderVerifier.requestProvision(invalidPubKey, fnsaAddr1, mockMessageHash, mockSignature),
      ).to.be.revertedWith("Invalid public key length");
    });

    it("reverts with invalid signature length", async function () {
      const invalidSig = "0x" + "11".repeat(32);
      await expect(
        holderVerifier.requestProvision(mockPublicKey, fnsaAddr1, mockMessageHash, invalidSig),
      ).to.be.revertedWith("Invalid signature length");
    });

    it("reverts when address empty", async function () {
      await expect(
        holderVerifier.requestProvision(mockPublicKey, "", mockMessageHash, mockSignature),
      ).to.be.revertedWith("HolderVerifier: empty fnsaAddress");
    });

    it("reverts when no balance", async function () {
      await expect(
        holderVerifier.requestProvision(mockPublicKey, fnsaAddr2, mockMessageHash, mockSignature),
      ).to.be.revertedWith("HolderVerifier: no claimable balance");
    });
  });

  describe("Integration", function () {
    it("invokes FnsaVerify", async function () {
      await holderVerifier.addRecord(fnsaAddr1, conyBalance1);
      await expect(
        holderVerifier.requestProvision(mockPublicKey, fnsaAddr1, mockMessageHash, mockSignature),
      ).to.be.revertedWith("Invalid fnsa address");
    });
  });

  describe("Provisioning", function () {
    it("emits ProvisionRequested with correct KAIA amount", async function () {
      const harnessFactory = await ethers.getContractFactory("FnsaVerifyHarness");
      const harness = await harnessFactory.deploy();
      await harness.waitForDeployment();

      const wallet = ethers.Wallet.createRandom();
      const signingKey = wallet.signingKey;
      const publicKey = signingKey.publicKey;
      const fnsaAddr = await harness.computeFnsaAddr(publicKey);
      const expectedHolderAddr = await harness.computeEthAddr(publicKey);

      const conyBalance = ethers.parseUnits("1", 6);
      await holderVerifier.addRecord(fnsaAddr, conyBalance);

      const message = kaiabridgeMessageFor(expectedHolderAddr);
      const messageHash = ethers.hashMessage(message);
      const signature = await wallet.signMessage(message);

      const expectedKaiaAmount = conyBalance * CONV_RATE;
      const expectedSeq = 1n;

      const tx = await holderVerifier.connect(user1).requestProvision(publicKey, fnsaAddr, messageHash, signature);
      await expect(tx)
        .to.emit(holderVerifier, "ProvisionRequested")
        .withArgs(fnsaAddr, expectedHolderAddr, conyBalance, expectedKaiaAmount, expectedSeq);
      await tx.wait();

      const txId = await operator.userIdx2TxID(1n);
      expect(txId).to.equal(1n);

      const submission = await operator.transactions(txId);
      expect(submission.to).to.equal(await bridge.getAddress());

      const provisionData = await operator.provisions(txId);
      expect(provisionData.seq).to.equal(1n);
      expect(provisionData.sender).to.equal(fnsaAddr);
      expect(provisionData.receiver).to.equal(expectedHolderAddr);
      expect(provisionData.amount).to.equal(expectedKaiaAmount);

      expect(await holderVerifier.provisionSeq(fnsaAddr)).to.not.equal(0n);
      expect(await holderVerifier.provisionedConyBalances()).to.equal(conyBalance);
      expect(await holderVerifier.provisionedAccounts()).to.equal(1n);
    });

    it("accepts Klaytn prefix signed message", async function () {
      const harnessFactory = await ethers.getContractFactory("FnsaVerifyHarness");
      const harness = await harnessFactory.deploy();
      await harness.waitForDeployment();

      const wallet = ethers.Wallet.createRandom();
      const publicKey = wallet.signingKey.publicKey;
      const fnsaAddr = await harness.computeFnsaAddr(publicKey);
      const expectedHolderAddr = await harness.computeEthAddr(publicKey);

      const conyBalance = ethers.parseUnits("1", 6);
      await holderVerifier.addRecord(fnsaAddr, conyBalance);

      const message = kaiabridgeMessageFor(expectedHolderAddr);
      const klayPrefix = "\x19Klaytn Signed Message:\n52";
      const klayHash = ethers.keccak256(ethers.concat([ethers.toUtf8Bytes(klayPrefix), ethers.toUtf8Bytes(message)]));
      const signature = signKlaytnPrefixedMessage(wallet, expectedHolderAddr);

      const tx = await holderVerifier.connect(user1).requestProvision(publicKey, fnsaAddr, klayHash, signature);
      await expect(tx)
        .to.emit(holderVerifier, "ProvisionRequested")
        .withArgs(fnsaAddr, expectedHolderAddr, conyBalance, conyBalance * CONV_RATE, 1n);
    });

    it("accumulates statistics across multiple provision requests", async function () {
      const harnessFactory = await ethers.getContractFactory("FnsaVerifyHarness");
      const harness = await harnessFactory.deploy();
      await harness.waitForDeployment();

      const wallet1 = ethers.Wallet.createRandom();
      const wallet2 = ethers.Wallet.createRandom();

      const signingKey1 = wallet1.signingKey;
      const signingKey2 = wallet2.signingKey;

      const publicKey1 = signingKey1.publicKey;
      const publicKey2 = signingKey2.publicKey;

      const fnsaAddr1Dynamic = await harness.computeFnsaAddr(publicKey1);
      const fnsaAddr2Dynamic = await harness.computeFnsaAddr(publicKey2);
      const expectedHolderAddr1 = await harness.computeEthAddr(publicKey1);
      const expectedHolderAddr2 = await harness.computeEthAddr(publicKey2);

      const conyBalanceFirst = ethers.parseUnits("1", 6);
      const conyBalanceSecond = ethers.parseUnits("2", 6);

      await holderVerifier.addRecord(fnsaAddr1Dynamic, conyBalanceFirst);
      await holderVerifier.addRecord(fnsaAddr2Dynamic, conyBalanceSecond);

      const message1 = kaiabridgeMessageFor(expectedHolderAddr1);
      const messageHash1 = ethers.hashMessage(message1);
      const signature1 = await wallet1.signMessage(message1);
      const message2 = kaiabridgeMessageFor(expectedHolderAddr2);
      const messageHash2 = ethers.hashMessage(message2);
      const signature2 = await wallet2.signMessage(message2);

      await expect(
        holderVerifier.connect(user1).requestProvision(publicKey1, fnsaAddr1Dynamic, messageHash1, signature1),
      )
        .to.emit(holderVerifier, "ProvisionRequested")
        .withArgs(fnsaAddr1Dynamic, expectedHolderAddr1, conyBalanceFirst, conyBalanceFirst * CONV_RATE, 1n);

      expect(await holderVerifier.provisionedConyBalances()).to.equal(conyBalanceFirst);
      expect(await holderVerifier.provisionedAccounts()).to.equal(1n);

      await expect(
        holderVerifier.connect(user1).requestProvision(publicKey2, fnsaAddr2Dynamic, messageHash2, signature2),
      )
        .to.emit(holderVerifier, "ProvisionRequested")
        .withArgs(fnsaAddr2Dynamic, expectedHolderAddr2, conyBalanceSecond, conyBalanceSecond * CONV_RATE, 2n);

      const txId = await operator.userIdx2TxID(2n);
      expect(txId).to.equal(2n);

      const submission = await operator.transactions(txId);
      expect(submission.to).to.equal(await bridge.getAddress());

      const provisionData = await operator.provisions(txId);
      expect(provisionData.seq).to.equal(2n);
      expect(provisionData.sender).to.equal(fnsaAddr2Dynamic);
      expect(provisionData.receiver).to.equal(expectedHolderAddr2);
      expect(provisionData.amount).to.equal(conyBalanceSecond * CONV_RATE);

      expect(await holderVerifier.provisionedConyBalances()).to.equal(conyBalanceFirst + conyBalanceSecond);
      expect(await holderVerifier.provisionedAccounts()).to.equal(2n);
    });

    it("sends funds to holder address from public key, not msg.sender", async function () {
      // Security test: Previously, receiver was set to msg.sender, allowing
      // malicious users to redirect funds by calling requestProvision with
      // a valid signature from the actual holder. This test verifies that
      // funds are always sent to the address corresponding to the public key
      // used for signing, regardless of who calls the function.

      const harnessFactory = await ethers.getContractFactory("FnsaVerifyHarness");
      const harness = await harnessFactory.deploy();
      await harness.waitForDeployment();

      const holderWallet = ethers.Wallet.createRandom();
      const signingKey = holderWallet.signingKey;
      const publicKey = signingKey.publicKey;
      const fnsaAddr = await harness.computeFnsaAddr(publicKey);
      const holderAddr = await harness.computeEthAddr(publicKey);

      const callerWallet = user1;

      const conyBalance = ethers.parseUnits("1", 6);
      await holderVerifier.addRecord(fnsaAddr, conyBalance);

      const message = kaiabridgeMessageFor(holderAddr);
      const messageHash = ethers.hashMessage(message);
      const signature = await holderWallet.signMessage(message);

      // Malicious caller attempts to redirect funds to their own address
      // by calling requestProvision with the holder's valid signature
      const tx = await holderVerifier
        .connect(callerWallet)
        .requestProvision(publicKey, fnsaAddr, messageHash, signature);
      await tx.wait();

      const txId = await operator.userIdx2TxID(1n);
      const provisionData = await operator.provisions(txId);

      expect(provisionData.receiver).to.equal(holderAddr);
      expect(provisionData.receiver).to.not.equal(callerWallet.address);

      await expect(tx)
        .to.emit(holderVerifier, "ProvisionRequested")
        .withArgs(fnsaAddr, holderAddr, conyBalance, conyBalance * CONV_RATE, 1n);
    });
  });
});
