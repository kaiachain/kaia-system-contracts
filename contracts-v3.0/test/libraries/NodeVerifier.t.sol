// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NodeVerifier} from "../../src/libraries/NodeVerifier.sol";
import {IRegistry} from "../../src/system/IRegistry.sol";
import {BlsPublicKeyInfo} from "../../src/types/Node.sol";

/// @dev Wrapper to expose NodeVerifier as external calls (needed for vm.expectRevert with external subcalls)
contract NodeVerifierHarness {
    mapping(address => bool) public registry;

    function setRegistry(address addr, bool value) external {
        registry[addr] = value;
    }

    function registerNode(
        address nodeId,
        address stakingContract,
        address rewardAddress,
        BlsPublicKeyInfo memory blsInfo
    ) external {
        NodeVerifier.registerNode(registry, nodeId, stakingContract, rewardAddress, blsInfo);
    }

    function registerNodeGenesis(
        address nodeId,
        address stakingContract,
        address rewardAddress,
        BlsPublicKeyInfo memory blsInfo
    ) external {
        NodeVerifier.registerNodeGenesis(registry, nodeId, stakingContract, rewardAddress, blsInfo);
    }

    function unregisterAddresses(address nodeId, address stakingContract, address rewardAddress) external {
        NodeVerifier.unregisterAddresses(registry, nodeId, stakingContract, rewardAddress);
    }
}

contract NodeVerifierTest is Test {
    address internal constant REGISTRY_ADDRESS = address(0x401);
    address internal constant MOCK_FACTORY = address(0x501);
    address internal constant DEPLOYER = address(0xDE);

    NodeVerifierHarness internal harness;

    function setUp() public {
        harness = new NodeVerifierHarness();
        harness.setRegistry(address(0x1), true);
        harness.setRegistry(address(0x2), true);
        harness.setRegistry(address(0x3), true);

        // Mock CnStakingFactory in registry
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("CnStakingFactory")),
            abi.encode(MOCK_FACTORY)
        );
        // Default: getDeployer returns DEPLOYER for staking(0x5)
        vm.mockCall(MOCK_FACTORY, abi.encodeWithSignature("getDeployer(address)", address(0x5)), abi.encode(DEPLOYER));
        // Default: isDeployedCnStaking returns true
        vm.mockCall(MOCK_FACTORY, abi.encodeWithSignature("isDeployedCnStaking(address)"), abi.encode(true));
        // Default: staking(0x5) has no publicDelegation
        vm.mockCall(address(0x5), abi.encodeWithSignature("publicDelegation()"), abi.encode(address(0)));
    }

    function _validBls() internal pure returns (BlsPublicKeyInfo memory) {
        bytes memory pk = new bytes(48);
        pk[0] = 0x01;
        bytes memory pop = new bytes(96);
        pop[0] = 0x01;
        return BlsPublicKeyInfo({publicKey: pk, pop: pop});
    }

    /* ========== registerNode (deployer check) ========== */

    function test_registerNode_success() public {
        // msg.sender must match getDeployer result (DEPLOYER)
        vm.prank(DEPLOYER);
        harness.registerNode(address(0x4), address(0x5), address(0x6), _validBls());
        assertTrue(harness.registry(address(0x4)));
        assertTrue(harness.registry(address(0x5)));
        assertTrue(harness.registry(address(0x6)));
    }

    function test_registerNode_revert_zeroNodeId() public {
        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        vm.prank(DEPLOYER);
        harness.registerNode(address(0), address(0x5), address(0x6), _validBls());
    }

    function test_registerNode_revert_zeroStaking() public {
        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        vm.prank(DEPLOYER);
        harness.registerNode(address(0x4), address(0), address(0x6), _validBls());
    }

    function test_registerNode_revert_zeroReward() public {
        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        vm.prank(DEPLOYER);
        harness.registerNode(address(0x4), address(0x5), address(0), _validBls());
    }

    function test_registerNode_revert_duplicateAddresses() public {
        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        vm.prank(DEPLOYER);
        harness.registerNode(address(0x4), address(0x4), address(0x6), _validBls());
    }

    function test_registerNode_revert_blsPublicKeyWrongSize() public {
        BlsPublicKeyInfo memory bls = BlsPublicKeyInfo({publicKey: new bytes(32), pop: new bytes(96)});
        bls.pop[0] = 0x01;
        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        vm.prank(DEPLOYER);
        harness.registerNode(address(0x4), address(0x5), address(0x6), bls);
    }

    function test_registerNode_revert_blsPopWrongSize() public {
        BlsPublicKeyInfo memory bls = BlsPublicKeyInfo({publicKey: new bytes(48), pop: new bytes(48)});
        bls.publicKey[0] = 0x01;
        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        vm.prank(DEPLOYER);
        harness.registerNode(address(0x4), address(0x5), address(0x6), bls);
    }

    function test_registerNode_revert_blsPublicKeyZero() public {
        BlsPublicKeyInfo memory bls = BlsPublicKeyInfo({publicKey: new bytes(48), pop: new bytes(96)});
        bls.pop[0] = 0x01;
        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        vm.prank(DEPLOYER);
        harness.registerNode(address(0x4), address(0x5), address(0x6), bls);
    }

    function test_registerNode_revert_blsPopZero() public {
        BlsPublicKeyInfo memory bls = BlsPublicKeyInfo({publicKey: new bytes(48), pop: new bytes(96)});
        bls.publicKey[0] = 0x01;
        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        vm.prank(DEPLOYER);
        harness.registerNode(address(0x4), address(0x5), address(0x6), bls);
    }

    function test_registerNode_revert_addressAlreadyRegistered() public {
        vm.expectRevert(NodeVerifier.AddressAlreadyRegistered.selector);
        vm.prank(DEPLOYER);
        harness.registerNode(address(0x1), address(0x5), address(0x6), _validBls());
    }

    function test_registerNode_revert_factoryNotFound() public {
        // Factory not registered (returns address(0))
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("CnStakingFactory")),
            abi.encode(address(0))
        );
        vm.expectRevert(NodeVerifier.FactoryNotFound.selector);
        vm.prank(DEPLOYER);
        harness.registerNode(address(0x4), address(0x5), address(0x6), _validBls());
    }

    function test_registerNode_revert_deployerMismatch() public {
        // msg.sender is not the deployer
        address notDeployer = address(0xBAD);
        vm.prank(notDeployer);
        vm.expectRevert(NodeVerifier.StakingDeployerMismatch.selector);
        harness.registerNode(address(0x4), address(0x5), address(0x6), _validBls());
    }

    function test_registerNode_revert_notFactoryDeployed() public {
        // getDeployer returns address(0) → not deployed by factory
        vm.mockCall(
            MOCK_FACTORY,
            abi.encodeWithSignature("getDeployer(address)", address(0x5)),
            abi.encode(address(0))
        );
        vm.prank(DEPLOYER);
        vm.expectRevert(NodeVerifier.StakingDeployerMismatch.selector);
        harness.registerNode(address(0x4), address(0x5), address(0x6), _validBls());
    }

    function test_registerNode_success_withPD() public {
        // PD is set → rewardAddress must equal PD
        address pd = address(0x6);
        vm.mockCall(address(0x5), abi.encodeWithSignature("publicDelegation()"), abi.encode(pd));
        vm.prank(DEPLOYER);
        harness.registerNode(address(0x4), address(0x5), pd, _validBls());
        assertTrue(harness.registry(address(0x4)));
        assertTrue(harness.registry(address(0x5)));
        assertTrue(harness.registry(pd));
    }

    function test_registerNode_revert_pdMismatch() public {
        // PD is set but rewardAddress != PD
        vm.mockCall(address(0x5), abi.encodeWithSignature("publicDelegation()"), abi.encode(address(0x99)));
        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        vm.prank(DEPLOYER);
        harness.registerNode(address(0x4), address(0x5), address(0x6), _validBls());
    }

    /* ========== registerNodeGenesis (factory-only check) ========== */

    function test_registerNodeGenesis_success() public {
        harness.registerNodeGenesis(address(0x4), address(0x5), address(0x6), _validBls());
        assertTrue(harness.registry(address(0x4)));
        assertTrue(harness.registry(address(0x5)));
        assertTrue(harness.registry(address(0x6)));
    }

    function test_registerNodeGenesis_revert_invalidInput() public {
        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        harness.registerNodeGenesis(address(0), address(0x5), address(0x6), _validBls());
    }

    function test_registerNodeGenesis_revert_addressAlreadyRegistered() public {
        vm.expectRevert(NodeVerifier.AddressAlreadyRegistered.selector);
        harness.registerNodeGenesis(address(0x1), address(0x5), address(0x6), _validBls());
    }

    function test_registerNodeGenesis_success_withPD() public {
        address pd = address(0x6);
        vm.mockCall(address(0x5), abi.encodeWithSignature("publicDelegation()"), abi.encode(pd));
        harness.registerNodeGenesis(address(0x4), address(0x5), pd, _validBls());
        assertTrue(harness.registry(pd));
    }

    function test_registerNodeGenesis_revert_pdMismatch() public {
        vm.mockCall(address(0x5), abi.encodeWithSignature("publicDelegation()"), abi.encode(address(0x99)));
        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        harness.registerNodeGenesis(address(0x4), address(0x5), address(0x6), _validBls());
    }

    /* ========== unregisterAddresses ========== */

    function test_unregisterAddresses() public {
        harness.unregisterAddresses(address(0x1), address(0x2), address(0x3));
        assertFalse(harness.registry(address(0x1)));
        assertFalse(harness.registry(address(0x2)));
        assertFalse(harness.registry(address(0x3)));
    }

    function test_unregisterAddresses_not_all() public {
        harness.unregisterAddresses(address(0x1), address(0x2), address(0x4));
        assertFalse(harness.registry(address(0x1)));
        assertFalse(harness.registry(address(0x2)));
        assertTrue(harness.registry(address(0x3)));
    }
}
