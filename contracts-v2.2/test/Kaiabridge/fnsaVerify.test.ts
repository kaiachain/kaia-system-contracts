import { expect } from "chai";
import { bech32 } from "bech32";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";

describe("Fnsa", function () {
  // test wallet
  const mnemonic = "arena click issue slot sleep tag access exotic opera pattern code coral"; // randomly generated test wallet
  const path = "m/44'/438'/0'/0/0"; // 438 is FNSA's coin_type. https://github.com/satoshilabs/slips/blob/master/slip-0044.md?plain=1
  const wallet = ethers.HDNodeWallet.fromMnemonic(ethers.Mnemonic.fromPhrase(mnemonic), path);
  const signingKey = wallet.signingKey;
  const walletPub = signingKey.publicKey; // 65-byte
  const bech32Prefix = "link";
  const expectedFnsaAddr = "link19sl2wemng3ayh3uwuw2xvj6zsypzacz0e6cahc";
  const expectedValoperAddr = "linkvaloper19sl2wemng3ayh3uwuw2xvj6zsypzacz0tw6qet";

  async function deployFnsaFixture() {
    const Fnsa = await ethers.getContractFactory("FnsaVerifyHarness");
    const fnsa = await Fnsa.deploy();
    return { fnsa };
  }

  it("off-chain: publicKey", async function () {
    console.log("pub", walletPub);
  });

  // fnsaAddr = bech32(ripemd160(sha256(compressed_pub)), prefix)
  it("off-chain: pub => fnsaAddr", function () {
    console.log("pub", walletPub);

    // we could have used wallet.signingKey.compressedPublicKey,
    // but we're compressing manually to reproduce the smart contract implementation.
    const pubXY64 = ethers.getBytes(walletPub).slice(1);
    const pubX32 = pubXY64.slice(0, 32);
    const isEven = pubXY64[63] % 2 === 0;
    const compressedPrefix = ethers.getBytes(isEven ? "0x02" : "0x03");
    const compressedPub = ethers.concat([compressedPrefix, pubX32]);
    expect(compressedPub).to.equal(wallet.signingKey.compressedPublicKey);

    const sha256Hash = ethers.sha256(ethers.getBytes(compressedPub));
    console.log("sha256(pub)", sha256Hash);

    const ripemd160Hash = ethers.ripemd160(ethers.getBytes(sha256Hash));
    console.log("ripemd160(sha256(pub))", ripemd160Hash);

    const words = bech32.toWords(ethers.getBytes(ripemd160Hash));
    const fnsaAddr = bech32.encode(bech32Prefix, words);
    console.log("bech32(ripemd160(sha256(pub)))", fnsaAddr);
    expect(fnsaAddr).to.equal(expectedFnsaAddr);
  });

  it("on-chain: pub => fnsaAddr (computeFnsaAddr)", async function () {
    const { fnsa } = await loadFixture(deployFnsaFixture);
    const fnsaAddr = await fnsa.computeFnsaAddr(walletPub);
    expect(fnsaAddr).to.equal(expectedFnsaAddr);
  });

  it("on-chain: pub => ethAddr (computeEthAddr)", async function () {
    const { fnsa } = await loadFixture(deployFnsaFixture);
    const ethAddr = await fnsa.computeEthAddr(walletPub);
    expect(ethAddr).to.equal(wallet.address);
  });

  it("on-chain: pub => valoperAddr (computeValoperAddr)", async function () {
    const { fnsa } = await loadFixture(deployFnsaFixture);
    const valoperAddr = await fnsa.computeValoperAddr(walletPub);
    expect(valoperAddr).to.equal(expectedValoperAddr);
  });

  it("on-chain: sig => ethAddr (recoverEthAddr)", async function () {
    const message = "Hello, world!";
    const messageHash = ethers.hashMessage(message);
    const sig = await wallet.signMessage(message);

    const { fnsa } = await loadFixture(deployFnsaFixture);
    const ethAddr = await fnsa.recoverEthAddr(messageHash, sig);
    expect(ethAddr).to.equal(wallet.address);
  });

  it("on-chain: verify", async function () {
    const message = "kaiabridge" + wallet.address.toLowerCase();
    const ethHash = ethers.hashMessage(message);
    const sig = await wallet.signMessage(message);

    const { fnsa } = await loadFixture(deployFnsaFixture);
    const verifiedAddr = await fnsa.verify(walletPub, expectedFnsaAddr, ethHash, sig);
    expect(verifiedAddr).to.equal(wallet.address);
    const verifiedValoper = await fnsa.verify(walletPub, expectedValoperAddr, ethHash, sig);
    expect(verifiedValoper).to.equal(wallet.address);
    // Detects mismatches
    const otherFnsaAddr = "link1lt90gyw368jj9h547ehe8v9t4cupcsca9g9wc6";
    await expect(fnsa.verify(walletPub, otherFnsaAddr, ethHash, sig)).to.be.revertedWith("Invalid fnsa address");
    const otherValoperAddr = "linkvaloper1lt90gyw368jj9h547ehe8v9t4cupcscm9yywa";
    await expect(fnsa.verify(walletPub, otherValoperAddr, ethHash, sig)).to.be.revertedWith("Invalid fnsa address");

    // Signature mismatch (wrong message)
    const otherMessage = "Goodbye, world!";
    const otherSig = await wallet.signMessage(otherMessage);
    await expect(fnsa.verify(walletPub, expectedFnsaAddr, ethHash, otherSig)).to.be.revertedWith("Invalid signature");

    // Signature mismatch (wrong signer)
    const otherWallet = ethers.Wallet.createRandom();
    const otherSig2 = await otherWallet.signMessage(message);
    await expect(fnsa.verify(walletPub, expectedFnsaAddr, ethHash, otherSig2)).to.be.revertedWith("Invalid signature");
  });

  it("on-chain: verify (Klaytn prefix)", async function () {
    const message = "kaiabridge" + wallet.address.toLowerCase();
    const klayPrefix = "\x19Klaytn Signed Message:\n52";
    const klayHash = ethers.keccak256(ethers.concat([ethers.toUtf8Bytes(klayPrefix), ethers.toUtf8Bytes(message)]));
    const sig = signingKey.sign(klayHash).serialized;

    const { fnsa } = await loadFixture(deployFnsaFixture);
    const verifiedAddr = await fnsa.verify(walletPub, expectedFnsaAddr, klayHash, sig);
    expect(verifiedAddr).to.equal(wallet.address);
    const verifiedValoper = await fnsa.verify(walletPub, expectedValoperAddr, klayHash, sig);
    expect(verifiedValoper).to.equal(wallet.address);
  });

  it("on-chain: verify with messageHash rejects mismatch", async function () {
    const message = "kaiabridge" + wallet.address.toLowerCase();
    const ethHash = ethers.hashMessage(message);
    const sig = await wallet.signMessage(message);
    const wrongHash = ethers.keccak256(ethers.toUtf8Bytes("wrong"));

    const { fnsa } = await loadFixture(deployFnsaFixture);
    await expect(fnsa.verify(walletPub, expectedFnsaAddr, wrongHash, sig)).to.be.revertedWith("messageHash mismatch");

    expect(await fnsa.verify(walletPub, expectedFnsaAddr, ethHash, sig)).to.equal(wallet.address);
  });
});
