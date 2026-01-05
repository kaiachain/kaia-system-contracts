import { getRegistry } from "../utils";
import { provider } from "../utils";

export async function regInfo() {
  const reg = getRegistry();
  const names = await reg.getAllNames();
  console.log(`* owner: ${await reg.owner()}`);
  console.log(`* names: ${names}`);
  console.log(`* all records:`);
  const now = await provider.getBlockNumber();
  for (const name of names) {
    console.log(`  * ${name} records:`);
    const records = await reg.getAllRecords(name);
    for (const [i, record] of records.entries()) {
      let type = "Deprecated";
      if (i == records.length - 1) {
        // last: either activation or future
        if (record.activation > now) {
          type = "Future";
        } else {
          type = "Active";
        }
      } else if (i == records.length - 2) {
        // second last: either activation or deprecated
        if (records[i + 1].activation > now) {
          type = "Active";
        }
      }
      console.log(`    * ${record[1]}, ${record[0]}, ${type}`);
    }
  }
}

export async function regRegister(name: string, addr: string, activation: number) {
  const reg = getRegistry();
  const tx = await reg.register(name, addr, activation);
  await tx.wait();
  console.log(`Registered: ${name}, ${addr}, ${activation}`);
}
