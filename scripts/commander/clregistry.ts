import { getCLRegistry } from "../utils/clRegistry";

export async function clRegInfo() {
  const clreg = await getCLRegistry();

  const allCLInfo = [];
  const allCLs = await clreg.getAllCLs();
  for (let i = 0; i < allCLs[0].length; i++) {
    allCLInfo.push(
      JSON.stringify({
        nodeId: allCLs[0][i],
        gcId: allCLs[1][i].toString(),
        clPool: allCLs[2][i],
      }),
    );
  }

  const gcIDs = await clreg.getAllGCIds();

  console.log(`
  All CL Info: [${allCLInfo}]
  All GC ID: [${gcIDs}]
    `);
}

export async function clRegAddPair(nodeId: string, gcId: number, clPool: string) {
  const clreg = await getCLRegistry();
  const tx = await clreg.addCLPair([{ nodeId, gcId, clPool }]);
  await tx.wait();
  console.log(`CL pair added:
    nodeId = ${nodeId}
    gcId = ${gcId}
    clPool = ${clPool} `);
}

export async function clRegRemovePair(gcId: number) {
  const clreg = await getCLRegistry();
  const clInfo = await clreg.clPoolList(gcId);
  console.log(clInfo);
  const tx = await clreg.removeCLPair(gcId);
  await tx.wait();
  console.log(`CL pair removed:
    nodeId = ${clInfo.nodeId}
    gcId = ${clInfo.gcId}
    clPool = ${clInfo.clPool}`);
}
