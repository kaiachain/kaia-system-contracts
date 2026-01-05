import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const name = "Delegator";

export const delegatorConstructorArgs: {
  delegateeNames: string;
  delegateeAddrs: string;
  delegatorAddrs: string;
  publicDelegations: string;
}[] = [
  /* Mainnet: 2024/8/28 
  {
    delegateeNames: "LineXenesis",
    delegateeAddrs: "0x10f4d6396b4c7becab24a05dfeb879eee7234831",
    delegatorAddrs: "0x84319c6bCB1FACa221B65333B3F52fd609dd55FE",
    publicDelegations: "0x6BdafAd8d3cA9CA7Dc314d1276702Ec2eCfB1e23",
  },
  {
    delegateeNames: "GGL",
    delegateeAddrs: "0xAD1e3DA214c66F2cD22fc2dBAF61A95CAd1FB24C",
    delegatorAddrs: "0xE5ACD7ca94b97704e919013cAEE7311f15d7d687",
    publicDelegations: "0xEee451713F21826912C76577E68315819A97468C",
  },
  {
    delegateeNames: "Certik",
    delegateeAddrs: "0x20C6a112F3B47a804857e5F042FE43112515f74E",
    delegatorAddrs: "0x80096a703c55FEbff603D7581FB1CAfd1Ce5f2b7",
    publicDelegations: "0xc1890DCBF4Cd63f11324bB4733936b2EE339b19A",
  },
  {
    delegateeNames: "Delight",
    delegateeAddrs: "0xF4D53E033512847BaDa43a0001182d779876878b",
    delegatorAddrs: "0x7C1E4cb51861De98BE08178b17447E9Af02f1699",
    publicDelegations: "0xe5e6c55801760E3D51Cd18Cd648DCf1B062837Cb",
  },
  {
    delegateeNames: "Cosmostation",
    delegateeAddrs: "0x3d3A6e1Dd59b727eB56F1B6b7f710B84EBEa1CB4",
    delegatorAddrs: "0xc1018af236A5a15a1DF53FFf7386c82028FBaE8D",
    publicDelegations: "0x5089015830BdB2dD3bE51Cfaf20e7dBC659D4C05",
  },
  {
    delegateeNames: "Bughole",
    delegateeAddrs: "0x4f7d49803cA80C438CBB94cBD2C1bF2abAc74B4E",
    delegatorAddrs: "0x1532c3fB331B03ea24bdD09e74e76F5861f25EFb",
    publicDelegations: "0xb38772304a72dC0492D2B509042E8FeF4BABFe34",
  },
  {
    delegateeNames: "Sega",
    delegateeAddrs: "0xE0D2f12d9fCb510c09572dB0bdEcB83ea2f1F93c",
    delegatorAddrs: "0x7F5c7bDC87b190985D43532426b272907C1a2b57",
    publicDelegations: "0xCA5005b16F669E0D22498d8058f7384Ca0911594",
  },
  */
  // {
  //   delegateeNames: "StableLab",
  //   delegateeAddrs: "0xb19fF9334715A96fC4b01Ccd6e1393B6B1cA8c7A",
  //   delegatorAddrs: "0x8a82a51E6FB741Aac1e0f0f6f6BcF86A3388BE11",
  //   publicDelegations: "0xa21D46316afd769194b94b48004DB4AE72b37887",
  // },
  /* Mainnet: 2024/12/23 */
  // {
  //   delegateeNames: "Bisonai",
  //   delegateeAddrs: "0x8e95ad27CDDC7F259a9fF029d7731DAb8072b915",
  //   delegatorAddrs: "0xa12A875D4B3e8AeE2362c810BaE1715dbc0a8130",
  //   publicDelegations: "0x26295D173d146c3E7cdbdC770D955c44Abac8C04",
  // },
  // {
  //   delegateeNames: "Verichains",
  //   delegateeAddrs: "0x0c41cce8dDAeA235F97745A13207421DCa7340FA",
  //   delegatorAddrs: "0x301DA03AddD36549e4050391CD8b5fFb345fE7e8",
  //   publicDelegations: "0xE4259eDF8EB53a13c2214426cA3Bb67594B43cE0",
  // },
  /* Mainnet: 2025/2/14 */
  // {
  //   delegateeNames: "X2eAll",
  //   delegateeAddrs: "0xF69Bc8C64Ee6385a0B332cF6732161F4403025c8",
  //   delegatorAddrs: "0x7a0e347bc85310684D2a23e8147eBF3bc384c6ea",
  //   publicDelegations: "0x9a1251cdda04CA663d436115EB6DF56AA4B5F7D2",
  // },
  /* Mainnet: 2025/6/23 */
  {
    delegateeNames: "Xangle",
    delegateeAddrs: "0x7784e21c4db59f77591023764cfd4517e3dc0655",
    delegatorAddrs: "0x227cDAd001F0D6AC5296eFE9A563DBeBBa9e464F",
    publicDelegations: "0x4d5878b56B35b6F406F35884d5dD4B107693b560",
  },
];

const func: DeployFunction = async ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) => {
  const { deployer } = await getNamedAccounts();

  for (let i = 0; i < delegatorConstructorArgs.length; i++) {
    const res = await deployments.deploy(`${name}#${delegatorConstructorArgs[i].delegateeNames}`, {
      contract: name,
      from: deployer,
      args: [
        delegatorConstructorArgs[i].delegatorAddrs,
        delegatorConstructorArgs[i].delegateeAddrs,
        delegatorConstructorArgs[i].publicDelegations,
      ],
      log: true,
    });
    console.log(`${name}#${delegatorConstructorArgs[i].delegateeNames} deployed at ${res.address}\n`);
  }
};

func.tags = [name];
export default func;
