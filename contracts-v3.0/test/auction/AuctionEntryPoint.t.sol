// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Test, Vm} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {AuctionEntryPoint} from "../../src/Auction/AuctionEntryPoint.sol";
import {IAuctionEntryPoint} from "../../src/Auction/interfaces/IAuctionEntryPoint.sol";
import {AuctionError} from "../../src/Auction/AuctionError.sol";
import {MockAuctionDepositVault} from "./mocks/MockAuctionDepositVault.sol";

/// @title AuctionEntryPoint diff tests
/// @notice Targets ONLY the v3.0 change: tx.gasprice <= auctionTx.maxGasPrice upper-bound check
///         in _verifyInputIntegrity. The rest of the bid flow (signature, nonce, takeBid/takeGas)
///         is exercised once on the happy path to confirm wiring; deeper coverage lives in
///         contracts-v2.1's auctionEntryPoint.test.ts and is not duplicated here.
contract AuctionEntryPointTest is Test {
    AuctionEntryPoint internal entryPoint;
    MockAuctionDepositVault internal vault;

    Vm.Wallet internal searcher;
    Vm.Wallet internal auctioneer;
    address internal owner = address(0xA11CE);
    address internal proposer = address(0xC01CB);
    address internal target = address(0xDEAD);

    bytes32 internal constant _AUCTIONTX_TYPEHASH =
        keccak256(
            "AuctionTx(bytes32 targetTxHash,uint256 blockNumber,address sender,address to,uint256 nonce,uint256 bid,uint256 maxGasPrice,uint256 callGasLimit,bytes data)"
        );
    bytes32 internal constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function setUp() public {
        searcher = vm.createWallet("searcher");
        auctioneer = vm.createWallet("auctioneer");

        vault = new MockAuctionDepositVault();
        entryPoint = new AuctionEntryPoint(owner, address(vault), auctioneer.addr);

        // Give searcher plenty of deposit so the bid check passes deterministically.
        vault.setBalance(searcher.addr, 1_000 ether);

        // Proposer == block.coinbase is required by onlyProposer.
        vm.coinbase(proposer);
    }

    /* ========== HELPERS ========== */

    function _domainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _EIP712_DOMAIN_TYPEHASH,
                    keccak256(bytes(entryPoint.AUCTION_NAME())),
                    keccak256(bytes(entryPoint.AUCTION_VERSION())),
                    block.chainid,
                    address(entryPoint)
                )
            );
    }

    function _structHash(IAuctionEntryPoint.AuctionTx memory a) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _AUCTIONTX_TYPEHASH,
                    a.targetTxHash,
                    a.blockNumber,
                    a.sender,
                    a.to,
                    a.nonce,
                    a.bid,
                    a.maxGasPrice,
                    a.callGasLimit,
                    keccak256(a.data)
                )
            );
    }

    /// @dev Builds and signs an AuctionTx that passes every check when submitted with
    ///      tx.gasprice <= maxGasPrice. Caller may then mutate one field to test a specific path.
    function _buildSignedTx(uint256 maxGasPrice) internal view returns (IAuctionEntryPoint.AuctionTx memory a) {
        a = IAuctionEntryPoint.AuctionTx({
            targetTxHash: bytes32(uint256(0x1234)),
            blockNumber: block.number,
            sender: searcher.addr,
            to: target,
            nonce: entryPoint.nonces(searcher.addr),
            bid: 1 ether,
            maxGasPrice: maxGasPrice,
            callGasLimit: 100_000,
            data: hex"",
            searcherSig: bytes(""),
            auctioneerSig: bytes("")
        });

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), _structHash(a)));
        (uint8 vS, bytes32 rS, bytes32 sS) = vm.sign(searcher.privateKey, digest);
        a.searcherSig = abi.encodePacked(rS, sS, vS);

        bytes32 ethDigest = MessageHashUtils.toEthSignedMessageHash(a.searcherSig);
        (uint8 vA, bytes32 rA, bytes32 sA) = vm.sign(auctioneer.privateKey, ethDigest);
        a.auctioneerSig = abi.encodePacked(rA, sA, vA);
    }

    /* ========== TESTS: gasprice upper-bound check (the diff) ========== */

    function test_gasprice_equal_to_ceiling_succeeds() public {
        uint256 g = 25 gwei;
        IAuctionEntryPoint.AuctionTx memory a = _buildSignedTx(g);

        vm.txGasPrice(g);
        vm.prank(proposer);
        entryPoint.call(a);

        // Nonce was used → bid+gas flow ran end-to-end.
        assertEq(entryPoint.nonces(searcher.addr), 1, "nonce not consumed");
        assertEq(vault.takeBidCallCount(), 1, "takeBid not invoked");
        assertEq(vault.takeGasCallCount(), 1, "takeGas not invoked");
        assertEq(vault.lastTakeBidAmount(), a.bid, "wrong bid amount taken");
    }

    function test_gasprice_above_ceiling_reverts() public {
        uint256 ceiling = 25 gwei;
        IAuctionEntryPoint.AuctionTx memory a = _buildSignedTx(ceiling);

        vm.txGasPrice(ceiling + 1);
        vm.prank(proposer);
        vm.expectRevert();
        entryPoint.call(a);

        assertEq(entryPoint.nonces(searcher.addr), 0, "nonce should not advance on reject");
        assertEq(vault.takeBidCallCount(), 0, "takeBid must not be invoked on reject");
    }

    /// @dev With ceiling semantics, a lower-than-signed effective gas price is harmless to the
    ///      searcher (they get charged less for gas), so the bundle MUST land successfully.
    function test_gasprice_below_ceiling_succeeds() public {
        uint256 ceiling = 25 gwei;
        IAuctionEntryPoint.AuctionTx memory a = _buildSignedTx(ceiling);

        vm.txGasPrice(ceiling - 1);
        vm.prank(proposer);
        entryPoint.call(a);

        assertEq(entryPoint.nonces(searcher.addr), 1, "nonce not consumed");
        assertEq(vault.takeBidCallCount(), 1, "takeBid not invoked");
        assertEq(vault.takeGasCallCount(), 1, "takeGas not invoked");
    }

    function test_gasprice_zero_ceiling_rejects_any_positive_tx_gasprice() public {
        // Edge: searcher signs maxGasPrice=0. Any positive tx.gasprice exceeds the ceiling.
        IAuctionEntryPoint.AuctionTx memory a = _buildSignedTx(0);

        vm.txGasPrice(1);
        vm.prank(proposer);
        vm.expectRevert();
        entryPoint.call(a);

        // Re-attempt with zero tx.gasprice should pass the ceiling check (0 <= 0).
        vm.txGasPrice(0);
        vm.prank(proposer);
        entryPoint.call(a);
        assertEq(entryPoint.nonces(searcher.addr), 1);
    }

    /// @dev Sanity: the signed `maxGasPrice` is part of the EIP-712 payload, so tampering with it
    ///      after signing must invalidate the searcher signature (defense in depth — the ceiling
    ///      check alone would let an attacker raise the field, but signature recovery catches it).
    function test_gasprice_tampered_after_signing_fails_signature_check() public {
        uint256 signedCeiling = 25 gwei;
        IAuctionEntryPoint.AuctionTx memory a = _buildSignedTx(signedCeiling);

        // Tamper: raise the maxGasPrice field but keep the signature. Submit with tx.gasprice
        // equal to the tampered ceiling so the upper-bound check passes — the failure must
        // come from the searcher-signature recovery instead.
        a.maxGasPrice = signedCeiling + 1;
        vm.txGasPrice(signedCeiling + 1);

        vm.prank(proposer);
        vm.expectRevert();
        entryPoint.call(a);

        assertEq(entryPoint.nonces(searcher.addr), 0);
    }

    /* ========== TESTS: pre-existing reverts still work ========== */

    function test_non_proposer_reverts() public {
        IAuctionEntryPoint.AuctionTx memory a = _buildSignedTx(1 gwei);
        vm.txGasPrice(1 gwei);
        vm.expectRevert(AuctionError.OnlyProposer.selector);
        entryPoint.call(a); // msg.sender = test contract, not block.coinbase
    }
}
