import { Contract, getAddress, Interface, JsonRpcProvider } from "ethers";
import * as fs from "fs";
import { getCnVersion } from "./cns";
import { provider } from "./config";

export const ABook_ABI = new Interface([
  "function CONTRACT_TYPE() external view returns (string)",
  "function submitUnregisterCnStakingContract(address _cnNodeId) external",
  "function getState() external view returns (address[], uint256)",
  "function isActivated() external view returns (bool)",
  "function isConstructed() external view returns (bool)",
  "function getAllAddressInfo() external view returns (address[], address[], address[], address, address)",
  "function pocContractAddress() external view returns (address)",
  "function kirContractAddress() external view returns (address)",
  "function spareContractAddress() external view returns (address)",
]);
export const ADDRESS_BOOK_ADDRESS = "0x0000000000000000000000000000000000000400";

export function getAddressBook(): Contract {
  return new Contract(ADDRESS_BOOK_ADDRESS, ABook_ABI, provider);
}

export type GC = {
  validatorAddr: string;
  cnNodeAddrs: string[];
  cnsAddrs: string[];
  cnsStakes?: bigint[];
  totalStake?: bigint; // in KLAY
  rewardAddr: string;
  name: string;
  version: number[];
};

export type AddressBookStatus = {
  type: string;
  admins: string[];
  requirement: number;
  isActivated: boolean;
  isConstructed: boolean;
  poc: string;
  kir: string;
  spare: string;
};

export class AddressBookViewer {
  readonly provider: JsonRpcProvider;
  readonly gcs: GC[] = [];
  readonly status: AddressBookStatus;
  readonly abook;

  constructor(provider: JsonRpcProvider) {
    this.provider = provider as JsonRpcProvider;
    this.abook = getAddressBook();
    this.status = {
      type: "",
      admins: [],
      requirement: 0,
      isActivated: false,
      isConstructed: false,
      poc: "",
      kir: "",
      spare: "",
    };
  }

  public static async init(provider: JsonRpcProvider) {
    const ret = new AddressBookViewer(provider);
    await ret.loadGC();
    await ret.loadGcTotalStake();
    return ret;
  }

  static async status(provider: JsonRpcProvider): Promise<AddressBookStatus> {
    const abook = getAddressBook();
    const [adminList] = await abook.getState();
    return {
      type: await abook.CONTRACT_TYPE(),
      admins: adminList,
      requirement: Number(await abook.requirement()),
      isActivated: await abook.isActivated(),
      isConstructed: await abook.isConstructed(),
      poc: await abook.pocContractAddress(),
      kir: await abook.kirContractAddress(),
      spare: await abook.spareContractAddress(),
    };
  }

  async loadGC() {
    if (!(await this.abook.isConstructed())) {
      return;
    }

    let council = [];
    try {
      council = await this.provider.send("kaia_getCouncil", []);
      council = council.map((x: string) => getAddress(x)); // checksumed address
    } catch {
      // empty
    }

    const [cnNodeAddrs, cnsAddrs, rewardAddrs] = await this.abook.getAllAddressInfo();
    const consolidated = consolidateNodes(cnNodeAddrs, cnsAddrs, rewardAddrs);
    const gcNames = JSON.parse(fs.readFileSync(__dirname + "/../gcnames.json").toString());

    for (let i = 0; i < consolidated.length; i++) {
      const [cnNodeAddrs, cnsAddrs, rewardAddr] = consolidated[i];

      const intersection = (a: string[], b: string[]) => {
        const setA = new Set(a);
        const setB = new Set(b);
        return [...setA].filter((value) => setB.has(value));
      };
      let [validatorAddr] = intersection(cnNodeAddrs, council);
      validatorAddr ??= "Not in council";
      const gcName = gcNames[rewardAddr] ?? `Anonymous-GC-${i}`;
      const version: number[] = [];
      for (let j = 0; j < cnsAddrs.length; j++) {
        version.push(await getCnVersion(cnsAddrs[j], this.provider));
      }

      this.gcs.push({ validatorAddr, cnNodeAddrs, cnsAddrs, rewardAddr, name: gcName, version: version });
    }
  }

  async loadGcTotalStake() {
    for (const gc of this.gcs) {
      let total = 0n;
      for (const cnsAddr of gc.cnsAddrs) {
        const balance = (await this.provider.getBalance(cnsAddr)) / BigInt(1e18);
        if (gc.cnsStakes == null) {
          gc.cnsStakes = [];
        }
        gc.cnsStakes.push(balance);
        total += balance;
      }
      gc.totalStake = total;
    }
  }
}

export function consolidateNodes(cnNodeAddrs: string[], cnsAddrs: string[], rewardAddrs: string[]) {
  const N = cnNodeAddrs.length;
  const rewardMap: { [key: string]: [string[], string[], string] } = {};
  for (let i = 0; i < N; i++) {
    if (rewardAddrs[i] in rewardMap) {
      rewardMap[rewardAddrs[i]][0].push(cnNodeAddrs[i]);
      rewardMap[rewardAddrs[i]][1].push(cnsAddrs[i]);
    } else {
      rewardMap[rewardAddrs[i]] = [[cnNodeAddrs[i]], [cnsAddrs[i]], rewardAddrs[i]];
    }
  }
  return Object.values(rewardMap);
}
