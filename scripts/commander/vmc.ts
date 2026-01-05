import fs from "fs";
import { getAddressBook } from "../utils/abook";
import { getVMC } from "../utils/vmc";
import { provider } from "../utils/config";
import { getSBR } from "../utils/sbr";

export async function getVMCDataPath() {
  return `./scripts/data/vmc/${Number((await provider.getNetwork()).chainId)}`;
}

async function getKaiaCouncil() {
  const council: string[] = await provider.send("kaia_getCouncil", ["latest"]);
  return council;
}

async function getNodeInfo() {
  const council: string[] = await getKaiaCouncil();
  const ab = getAddressBook();
  const [cnNodeIdList, , cnRewardAddressList, ,] = await ab.getAllAddressInfo();
  const vmcManagerJson = JSON.parse(fs.readFileSync(`${await getVMCDataPath()}/vmc_manager.json`, "utf8"));

  const rewardToNodeIds: Record<string, string[]> = {};
  for (let i = 0; i < cnNodeIdList.length; i++) {
    const rewardAddress = cnRewardAddressList[i];
    if (!rewardToNodeIds[rewardAddress]) {
      rewardToNodeIds[rewardAddress] = [];
    }
    rewardToNodeIds[rewardAddress].push(cnNodeIdList[i]);
  }

  const nodeInfos: { manager: string; consensusNodeId: string; nodeIds: string[] }[] = [];
  for (const [, nodeIds] of Object.entries(rewardToNodeIds)) {
    let includeInCouncil = false;
    let consenusNodeId = "";
    for (const nodeId of nodeIds) {
      if (council.includes(nodeId.toLowerCase())) {
        includeInCouncil = true;
        consenusNodeId = nodeId;
        break;
      }
    }
    if (includeInCouncil) {
      const manager = vmcManagerJson[consenusNodeId];
      if (!manager) {
        throw new Error(`Manager of consensus node id ${consenusNodeId} is not found in vmc_manager.json`);
      }
      nodeInfos.push({
        manager: manager,
        consensusNodeId: consenusNodeId,
        nodeIds: nodeIds.filter((nodeId) => nodeId.toLowerCase() !== consenusNodeId.toLowerCase()),
      });
    }
  }

  return nodeInfos;
}

async function verifyNodeInfos(nodeInfos: { manager: string; consensusNodeId: string; nodeIds: string[] }[]) {
  const council: string[] = await getKaiaCouncil();
  const [cnNodeIdList, , , ,] = await getAddressBook().getAllAddressInfo();
  let totalNumOfNodeIds = 0;

  for (const nodeInfo of nodeInfos) {
    if (!council.includes(nodeInfo.consensusNodeId.toLowerCase())) {
      throw new Error(`Consensus node id ${nodeInfo.consensusNodeId} is not in the council`);
    }
    for (const nodeId of nodeInfo.nodeIds) {
      if (!cnNodeIdList.includes(nodeId)) {
        throw new Error(`Node id ${nodeId} is not in the AddressBook`);
      }
    }
    totalNumOfNodeIds += nodeInfo.nodeIds.length + 1;
  }

  if (totalNumOfNodeIds !== cnNodeIdList.length) {
    throw new Error("Total number of node ids is not equal to the number of node ids in the AddressBook");
  }
}

export async function prepareConstructParams() {
  const nodeInfos = await getNodeInfo();
  await verifyNodeInfos(nodeInfos);

  fs.writeFileSync(`${await getVMCDataPath()}/vmc_data.json`, JSON.stringify(nodeInfos, null, 2));
  console.log("Construct params are prepared");
}

export async function getDeprecatedInfo() {
  const council: string[] = await getKaiaCouncil();
  const ab = getAddressBook();
  const sbr = await getSBR();

  const [cnNodeIdList, , cnRewardAddressList, ,] = await ab.getAllAddressInfo();

  const rewardToNodeIds: Record<string, string[]> = {};
  for (let i = 0; i < cnNodeIdList.length; i++) {
    const rewardAddress = cnRewardAddressList[i];
    if (!rewardToNodeIds[rewardAddress]) {
      rewardToNodeIds[rewardAddress] = [];
    }
    rewardToNodeIds[rewardAddress].push(cnNodeIdList[i]);
  }

  const shouldRemoveFromABook: string[] = [];
  for (const [, nodeIds] of Object.entries(rewardToNodeIds)) {
    let includeInCouncil = false;
    for (const nodeId of nodeIds) {
      if (council.includes(nodeId.toLowerCase())) {
        includeInCouncil = true;
        break;
      }
    }
    if (!includeInCouncil) {
      shouldRemoveFromABook.push(...nodeIds);
    }
  }

  const allBlsInfo = await sbr.getAllBlsInfo();
  const shouldRemoveFromSBR: string[] = [];
  for (const nodeId of allBlsInfo.nodeIdList) {
    if (!council.includes(nodeId.toLowerCase())) {
      shouldRemoveFromSBR.push(nodeId);
    }
  }

  fs.writeFileSync(
    `${await getVMCDataPath()}/deprecated_info.json`,
    JSON.stringify({ shouldRemoveFromABook, shouldRemoveFromSBR }, null, 2),
  );
  console.log("Deprecated info is prepared");
}

export async function validateVMCDeployment() {
  const council: string[] = await getKaiaCouncil();
  const vmcManager = getVMC();
  const nodeInfos = JSON.parse(fs.readFileSync(`${await getVMCDataPath()}/vmc_data.json`, "utf8"));

  const uniqueConsensusNodeIds = new Set<string>();
  for (const nodeInfo of nodeInfos) {
    const consensusNodeId = nodeInfo.consensusNodeId.toLowerCase();
    if (uniqueConsensusNodeIds.has(consensusNodeId)) {
      throw new Error(`Consensus node id ${consensusNodeId} is duplicated in vmc_data.json`);
    }
    uniqueConsensusNodeIds.add(consensusNodeId);

    const registeredNodeInfo = await vmcManager.getNodeInfo(consensusNodeId);
    if (registeredNodeInfo.manager !== nodeInfo.manager) {
      throw new Error(`Manager of consensus node id ${consensusNodeId} is not correct`);
    }
    if (registeredNodeInfo.nodeIds.length !== nodeInfo.nodeIds.length) {
      throw new Error(
        `Number of node ids of consensus node id ${consensusNodeId} is not correct: ${registeredNodeInfo.nodeIds.length} !== ${nodeInfo.nodeIds.length}`,
      );
    }
    if (!council.includes(consensusNodeId)) {
      throw new Error(`Consensus node id ${consensusNodeId} is not in the council`);
    }
    for (const nodeId of registeredNodeInfo.nodeIds) {
      if (!nodeInfo.nodeIds.includes(nodeId)) {
        throw new Error(`Node id ${nodeId} is not in the node ids of consensus node id ${consensusNodeId}`);
      }
    }
  }
  console.log("VMC deployment is valid");
}
