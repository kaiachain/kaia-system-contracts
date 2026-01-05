import { AddressBookViewer, GC, provider } from "../utils";

export async function abGCInfo(opts: { idx: string; node: string; cns: string; reward: string; gcid: string }) {
  const abView = await AddressBookViewer.init(provider);
  let gc: GC[];
  if (opts.node != "") {
    gc = abView.gcs.filter((gc) => gc.cnNodeAddrs.some((value) => opts.node == value));
  } else if (opts.cns != "") {
    gc = abView.gcs.filter((gc) => gc.cnsAddrs.some((value) => opts.cns == value));
  } else if (opts.reward != "") {
    gc = abView.gcs.filter((gc) => gc.rewardAddr == opts.reward);
  } else {
    const idx = Number(opts.idx);
    gc = [abView.gcs[idx]];
  }
  console.log(gc);
}

export async function abInfo(opts: { csv: boolean }) {
  const abView = await AddressBookViewer.init(provider);
  if (opts.csv) {
    if (abView.gcs.length == 0) {
      console.log("No gc");
      return;
    }

    console.log("name, validatorAddr, stakedAmount, rewardAddr");
    for (const gc of abView.gcs) {
      console.log(`${gc.name}, ${gc.validatorAddr}, ${gc.cnsStakes}, ${gc.rewardAddr}`);
    }
  } else {
    console.log(abView.gcs);
  }
}

export async function abStatus() {
  console.log(await AddressBookViewer.status(provider));
}
