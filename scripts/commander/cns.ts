import { AddressBookViewer } from "../utils/abook";
import { AbiCoder } from "ethers";
import { getCnStaking } from "../utils/cns";
import { provider } from "../utils/config";

export async function cnsShowTracker() {
  const ab = await AddressBookViewer.init(provider);
  for (const gc of ab.gcs) {
    const tracker = [];
    for (const cnsAddr of gc.cnsAddrs) {
      const cns = await getCnStaking(cnsAddr, provider);
      const version = await cns.VERSION();
      if (version < 2n) {
        continue;
      }
      tracker.push(await cns.stakingTracker());
    }

    if (gc.name == undefined) {
      gc.name = gc.rewardAddr;
    }
    if (tracker.length == 0) {
      console.log(`${gc.name} has no CnStakingV2 or later`);
      continue;
    }
    console.log(`${gc.name} has trackers ${tracker}`);
  }
}

export function cnsV3PDEncode(owner: string, commissionTo: string, commissionRate: string, gcName: string) {
  const pdParam = new AbiCoder().encode(
    ["tuple(address, address,  uint256, string)"],
    [[owner, commissionTo, Number(commissionRate), gcName]],
  );

  console.log(`Encoded PD Param: ${pdParam}`);
}
