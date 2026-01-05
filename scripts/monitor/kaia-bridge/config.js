// TODO: Update with actual addresses on mainnet

module.exports = {
  rpc: {
    primary: "https://public-en-kairos.node.kaia.io",
    secondary: "https://public-en-kairos.node.kaia.io",
  },

  // Contract Addresses
  contracts: {
    bridge: "0xF02C6c29611e7eC05e4429ce440E1fF40c9b730a",
    holderVerifier: "0x6dc8f41BFfD51C20437df7B0eD5E17716802E4EF",
    multicall3: "0xcA11bde05977b3631167028862bE2a173976CA11", // Standard MultiCall3 address
  },

  // Expected Authority Addresses
  authorities: {
    owner: "0x5c593E0A64F0cfaA9b0236535C12182092EA9c15",
    operator: "0xEf89564F617E496c3065a4b5D118262918b609fa",
    guardian: "0xee64ECAEAd6e61883857347637b927474e16a29E",
    judge: "0x113c372092fDa283ad71014D8b942B5f4fE475a6",
  },

  // Monitoring Settings
  monitoring: {
    cronSchedule: "* * * * *", // Every 1 minute
    port: 8080,
  },
};
