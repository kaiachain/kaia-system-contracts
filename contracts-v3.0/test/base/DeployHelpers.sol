// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {ABv2DataContract} from "../../src/AddressBookV2/ABv2DataContract.sol";
import {IABv2DataContract} from "../../src/AddressBookV2/interfaces/IABv2DataContract.sol";
import {IRegistry} from "../../src/system/IRegistry.sol";
import {NodeInfo, BlsPublicKeyInfo} from "../../src/types/Node.sol";
import {MockCnStaking} from "../../src/CnStaking/mocks/MockCnStaking.sol";

/// @title DeployHelpers
/// @notice Deployment mechanics for test infrastructure. No test logic or node creation.
contract DeployHelpers is Test {
    /* ========== SYSTEM CONSTANTS ========== */

    address internal constant ABV2_ADDRESS = address(0x400);
    address internal constant REGISTRY_ADDRESS = address(0x401);
    address internal constant MOCK_FACTORY = address(0x501);
    address internal constant SYSTEM_SENDER = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;
    uint256 internal constant EPOCH_BLOCK_INTERVAL = 86_400;

    /// @dev ERC-1967 implementation storage slot
    bytes32 internal constant ERC1967_IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    uint256 internal constant MIN_STAKE = 5_000_000 ether;

    /* ========== DEFAULT CONFIG CONSTANTS ========== */

    uint256 internal constant DEFAULT_PAUSE_TIMEOUT = 8 hours;
    uint256 internal constant DEFAULT_IDLE_TIMEOUT = 7 days;
    uint256 internal constant DEFAULT_PFS_THRESHOLD = 2;
    uint256 internal constant DEFAULT_MAX_NODE_COUNT = 100;
    uint256 internal constant DEFAULT_MAX_READY_CAND_COUNT = 2;

    address internal constant DEFAULT_KEF_ADDRESS = address(0xCE1);
    address internal constant DEFAULT_KIF_ADDRESS = address(0xC12);
    address internal constant DEFAULT_KPF_ADDRESS = address(0xC13);

    /* ========== STATE ========== */

    AddressBookV2 internal abv2;

    /* ========== DEPLOY: ADDRESS BOOK V2 AT 0x400 ========== */

    /// @notice Deploys ABv2 as a UUPS proxy at the hardcoded address 0x400.
    /// @dev Deploys ABv2DataContract with genesis data, mocks Registry at 0x401,
    ///      then deploys and initializes the ABv2 proxy.
    function deployAddressBookV2(
        address owner,
        uint256 pfsThreshold,
        uint256 pauseTimeout,
        uint256 idleTimeout,
        uint256 maxNodeCount,
        uint256 maxReadyCandCount,
        address kefAddress,
        address kifAddress,
        address kpfAddress
    ) internal {
        // Build InitData with empty node arrays (tests add nodes via createNode)
        IABv2DataContract.InitData memory initData = IABv2DataContract.InitData({
            initialOwner: owner,
            initialSuspender: owner,
            initialConfigurator: owner,
            pfsThreshold: pfsThreshold,
            cfsThreshold: 300,
            pauseTimeout: pauseTimeout,
            idleTimeout: idleTimeout,
            maxNodeCount: maxNodeCount,
            maxValActivePausedCount: maxNodeCount,
            maxCandReadyCount: maxReadyCandCount,
            kefAddress: kefAddress,
            kifAddress: kifAddress,
            kpfAddress: kpfAddress,
            nodeIds: new address[](0),
            infos: new NodeInfo[](0)
        });

        _deployWithDataContract(initData);
    }

    /// @notice Deploys ABv2 with pre-populated genesis validators via ABv2DataContract.
    function deployAddressBookV2WithValidators(IABv2DataContract.InitData memory initData) internal {
        _deployWithDataContract(initData);
    }

    /// @dev Core deployment: data contract → mock registry → proxy at 0x400 → initialize
    function _deployWithDataContract(IABv2DataContract.InitData memory initData) private {
        // 1. Mock CnStakingFactory in registry → approve any staking contract
        //    Must be set before ABv2DataContract deployment (constructor calls NodeVerifier.registerNode)
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("CnStakingFactory")),
            abi.encode(MOCK_FACTORY)
        );
        vm.mockCall(MOCK_FACTORY, abi.encodeWithSignature("isDeployedCnStaking(address)"), abi.encode(true));
        // Default getDeployer mock — returns address(0).
        // Tests that call createNode must override this per staking contract.
        vm.mockCall(MOCK_FACTORY, abi.encodeWithSignature("getDeployer(address)"), abi.encode(address(0)));

        // 1b. Mock StakingTracker in registry → return address(0) by default
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("StakingTracker")),
            abi.encode(address(0))
        );

        // 2. Deploy implementation
        AddressBookV2 impl = new AddressBookV2(EPOCH_BLOCK_INTERVAL);

        // 3. Deploy ABv2DataContract with genesis data (includes impl address)
        ABv2DataContract dataContract = new ABv2DataContract(address(impl), initData);

        // 4. Mock the Registry at 0x401 to return our data contract
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("ABv2DataContract")),
            abi.encode(address(dataContract))
        );

        // 5. Deploy a temporary proxy to capture ERC1967Proxy runtime bytecode.
        //    OZ v5.2 mandates init data, so we pass initialize().
        //    The temp proxy's storage is discarded — only its runtime code is copied.
        bytes memory initCall = abi.encodeCall(AddressBookV2.initialize, ());
        ERC1967Proxy tempProxy = new ERC1967Proxy(address(impl), initCall);

        // 6. Copy proxy runtime code to 0x400
        vm.etch(ABV2_ADDRESS, address(tempProxy).code);

        // 7. Set the implementation slot to point at our ABv2 impl
        vm.store(ABV2_ADDRESS, ERC1967_IMPL_SLOT, bytes32(uint256(uint160(address(impl)))));

        // 8. Initialize the proxy at 0x400
        abv2 = AddressBookV2(ABV2_ADDRESS);
        abv2.initialize();
    }

    /* ========== MOCK HELPERS ========== */

    /// @notice Mock getDeployer for a staking contract → deployer address
    function _mockDeployer(address stakingContract, address deployer) internal {
        vm.mockCall(
            MOCK_FACTORY,
            abi.encodeWithSignature("getDeployer(address)", stakingContract),
            abi.encode(deployer)
        );
    }

    /* ========== DEPLOY: MOCK CN STAKING ========== */

    /// @notice Deploys a MockCnStaking with preset staking and unstaking values
    function deployMockCnStaking(uint256 staking, uint256 unstaking) internal returns (MockCnStaking) {
        MockCnStaking cnStaking = new MockCnStaking();
        cnStaking.mockSetStaking(staking);
        cnStaking.mockSetUnstaking(unstaking);
        return cnStaking;
    }

    /* ========== BLS HELPERS ========== */

    /// @notice Returns a dummy BLS public key info (48-byte key, 96-byte pop)
    function _makeBlsInfo() internal pure returns (BlsPublicKeyInfo memory) {
        bytes memory pk = new bytes(48);
        pk[0] = 0x01;
        bytes memory pop = new bytes(96);
        pop[0] = 0x01;
        return BlsPublicKeyInfo({publicKey: pk, pop: pop});
    }

    /* ========== DEPLOY: ALL ========== */

    /// @notice Deploys the full system: ABv2 at 0x400 (single contract)
    function deployAll(
        address owner,
        uint256 pfsThreshold,
        uint256 pauseTimeout,
        uint256 idleTimeout,
        uint256 maxNodeCount,
        uint256 maxReadyCandCount,
        address kefAddress,
        address kifAddress,
        address kpfAddress
    ) internal {
        deployAddressBookV2(
            owner,
            pfsThreshold,
            pauseTimeout,
            idleTimeout,
            maxNodeCount,
            maxReadyCandCount,
            kefAddress,
            kifAddress,
            kpfAddress
        );
    }
}
