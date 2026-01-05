import { loadFixture, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ABOOK_ADDRESS, REGISTRY_ADDRESS, MILLIONS, registerContract } from "../../helpers/utils";
import { stakingTrackerV2TestFixture } from "../materials";
import {
  MockCLPool,
  MockCLPool__factory,
  MockCLRegistry,
  MockCLRegistry__factory,
  MockERC20,
  MockERC20__factory,
  StakingTrackerV2,
} from "../../typechain-types";
import { ZeroAddress } from "ethers";

type UnPromisify<T> = T extends Promise<infer U> ? U : T;

/**
 * @dev This unit & scenario test is for StakingTrackerV2.sol.
 */
describe("StakingTrackerV2.sol", function () {
  async function verifyTrackerState(
    stakingTracker: StakingTrackerV2,
    trackerId: number,
    trackStart: number,
    trackEnd: number,
    gcIds: number[],
    cnStakingBalances: bigint[],
    gcBalances: bigint[],
    votes: number[],
  ) {
    const totalVotes = votes.reduce((a, b) => a + b, 0);
    const lenGCs = gcIds.length;
    const numEligible = cnStakingBalances.filter((x) => x > MILLIONS.FIVE).length;

    const summary = await stakingTracker.getTrackerSummary(trackerId);
    expect(summary).to.deep.equal([trackStart, trackEnd, lenGCs, totalVotes, numEligible]);

    const trackedGCs = await stakingTracker.getAllTrackedGCs(trackerId);
    expect(trackedGCs).to.deep.equal([gcIds, gcBalances, votes]);

    for (let i = 0; i < lenGCs; i++) {
      const gcBalance = await stakingTracker.getTrackedGCBalance(trackerId, gcIds[i]);
      expect(gcBalance).to.deep.equal([cnStakingBalances[i], gcBalances[i]]);
    }
  }

  let fixture: UnPromisify<ReturnType<typeof stakingTrackerV2TestFixture>>;
  let fakeCLRegistry: MockCLRegistry;
  let fakeWKaia: MockERC20;
  let clPoolA: MockCLPool;
  let clPoolB: MockCLPool;
  let clPoolC: MockCLPool;
  beforeEach(async function () {
    fixture = await loadFixture(stakingTrackerV2TestFixture);

    fakeCLRegistry = await new MockCLRegistry__factory(fixture.admin1).deploy();
    fakeWKaia = await new MockERC20__factory(fixture.admin1).deploy();

    await registerContract(fixture.registry, "CLRegistry", await fakeCLRegistry.getAddress());
    await registerContract(fixture.registry, "WrappedKaia", await fakeWKaia.getAddress());

    clPoolA = await new MockCLPool__factory(fixture.admin1).deploy();
    clPoolB = await new MockCLPool__factory(fixture.admin1).deploy();
    clPoolC = await new MockCLPool__factory(fixture.admin1).deploy();

    await clPoolA.mockSetStakingTracker(fixture.stakingTracker.target);
    await clPoolB.mockSetStakingTracker(fixture.stakingTracker.target);
    await clPoolC.mockSetStakingTracker(fixture.stakingTracker.target);

    // Ignore nodeIds.
    await fakeCLRegistry.mockSetCLs([], [699, 700, 701], [clPoolA.target, clPoolB.target, clPoolC.target]);
  });

  describe("StakingTrackerV2 Initialize", function () {
    it("Check staking tracker constants", async function () {
      const { stakingTracker, contractValidator } = fixture;

      expect(await stakingTracker.CONTRACT_TYPE()).to.equal("StakingTracker");
      expect(await stakingTracker.VERSION()).to.equal(1);
      expect(await stakingTracker.ADDRESS_BOOK_ADDRESS()).to.equal(ABOOK_ADDRESS);
      expect(await stakingTracker.REGISTRY_ADDRESS()).to.equal(REGISTRY_ADDRESS);
      expect(await stakingTracker.MIN_STAKE()).to.equal(MILLIONS.FIVE);
      expect(await stakingTracker.owner()).to.equal(contractValidator.address);
    });
  });
  describe("Create a tracker", function () {
    it("#createTracker: no CLRegistry", async function () {
      const { stakingTracker, trackStart, trackEnd } = fixture;
      const { SIX } = MILLIONS;

      await registerContract(fixture.registry, "CLRegistry", ZeroAddress);

      await expect(stakingTracker.createTracker(trackStart, trackEnd))
        .to.emit(stakingTracker, "CreateTracker")
        .withArgs(1, trackStart, trackEnd, [700, 701, 702]);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [SIX, SIX, SIX],
        [SIX, SIX, SIX],
        [1, 1, 1],
      );
    });
    it("#createTracker: no wKaia so do not track wKaia balance", async function () {
      const { stakingTracker, trackStart, trackEnd } = fixture;
      const { SIX, TWO, FIVE } = MILLIONS;

      await registerContract(fixture.registry, "WrappedKaia", ZeroAddress);

      await fakeWKaia.mockSetBalance(clPoolB.target, TWO);
      await fakeWKaia.mockSetBalance(clPoolC.target, FIVE);

      await expect(stakingTracker.createTracker(trackStart, trackEnd))
        .to.emit(stakingTracker, "CreateTracker")
        .withArgs(1, trackStart, trackEnd, [700, 701, 702]);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [SIX, SIX, SIX],
        [SIX, SIX, SIX], // No wKaia balance reflected since wKaia is not active yet.
        [1, 1, 1],
      );
    });
    it("#createTracker: no CLPool", async function () {
      const { stakingTracker, trackStart, trackEnd } = fixture;
      const { SIX } = MILLIONS;

      await expect(stakingTracker.createTracker(trackStart, trackEnd))
        .to.emit(stakingTracker, "CreateTracker")
        .withArgs(1, trackStart, trackEnd, [700, 701, 702]);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [SIX, SIX, SIX],
        [SIX, SIX, SIX],
        [1, 1, 1],
      );
    });
    it("#createTracker: do not track CLPool with invalid StakingTracker address", async function () {
      const { stakingTracker, trackStart, trackEnd } = fixture;
      const { SIX } = MILLIONS;

      await clPoolB.mockSetStakingTracker(ZeroAddress);

      await expect(stakingTracker.createTracker(trackStart, trackEnd))
        .to.emit(stakingTracker, "CreateTracker")
        .withArgs(1, trackStart, trackEnd, [700, 701, 702]);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [SIX, SIX, SIX],
        [SIX, SIX, SIX],
        [1, 1, 1],
      );

      expect(await stakingTracker.isCLPool(1, clPoolB.target)).to.equal(false);
      expect(await stakingTracker.isCLPool(1, clPoolC.target)).to.equal(true);
      expect(await stakingTracker.stakingToGCId(1, clPoolB.target)).to.equal(0);
      expect(await stakingTracker.stakingToGCId(1, clPoolC.target)).to.equal(701);
    });
    it("#createTracker: do not track CLPool with non-existent gcId", async function () {
      const { stakingTracker, trackStart, trackEnd } = fixture;
      const { SIX } = MILLIONS;

      // clPoolB is assigned gcId 800, which is not a valid gcId
      await fakeCLRegistry.mockSetCLs([], [699, 800, 701], [clPoolA.target, clPoolB.target, clPoolC.target]);

      await expect(stakingTracker.createTracker(trackStart, trackEnd))
        .to.emit(stakingTracker, "CreateTracker")
        .withArgs(1, trackStart, trackEnd, [700, 701, 702]);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [SIX, SIX, SIX],
        [SIX, SIX, SIX],
        [1, 1, 1],
      );

      expect(await stakingTracker.isCLPool(1, clPoolB.target)).to.equal(false);
      expect(await stakingTracker.isCLPool(1, clPoolC.target)).to.equal(true);
      expect(await stakingTracker.stakingToGCId(1, clPoolB.target)).to.equal(0);
      expect(await stakingTracker.stakingToGCId(1, clPoolC.target)).to.equal(701);
    });
    it("#createTracker: two CLPools", async function () {
      const { stakingTracker, cnStakingV2B, cnStakingV2C, cnStakingV2D, trackStart, trackEnd } = fixture;
      const { TWO, FIVE, SIX, EIGHT, ELEVEN } = MILLIONS;

      await fakeWKaia.mockSetBalance(clPoolA.target, TWO);
      await fakeWKaia.mockSetBalance(clPoolB.target, TWO);
      await fakeWKaia.mockSetBalance(clPoolC.target, FIVE);

      await expect(stakingTracker.createTracker(trackStart, trackEnd))
        .to.emit(stakingTracker, "CreateTracker")
        .withArgs(1, trackStart, trackEnd, [700, 701, 702]);

      const gcBalances = await stakingTracker.getTrackedGCBalance(1, 699);
      // 699 is not tracked
      expect(gcBalances).to.deep.equal([0, 0]);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [SIX, SIX, SIX],
        [EIGHT, ELEVEN, SIX],
        [1, 2, 1],
      );

      expect(await stakingTracker.isCLPool(1, clPoolA.target)).to.equal(false);
      expect(await stakingTracker.isCLPool(1, clPoolB.target)).to.equal(true);
      expect(await stakingTracker.isCLPool(1, clPoolC.target)).to.equal(true);
      expect(await stakingTracker.isCLPool(1, cnStakingV2B.target)).to.equal(false);
      expect(await stakingTracker.isCLPool(1, cnStakingV2C.target)).to.equal(false);
      expect(await stakingTracker.isCLPool(1, cnStakingV2D.target)).to.equal(false);
      expect(await stakingTracker.stakingToGCId(1, cnStakingV2B.target)).to.equal(700);
      expect(await stakingTracker.stakingToGCId(1, cnStakingV2C.target)).to.equal(701);
      expect(await stakingTracker.stakingToGCId(1, cnStakingV2D.target)).to.equal(702);
      expect(await stakingTracker.stakingToGCId(1, clPoolB.target)).to.equal(700);
      expect(await stakingTracker.stakingToGCId(1, clPoolC.target)).to.equal(701);
    });
    it("#createTracker: CnStaking has less than 5M", async function () {
      const { stakingTracker, cnStakingV2C, trackStart, trackEnd } = fixture;
      const { TWO, SIX, FOUR, FIVE, EIGHT, NINE, TEN } = MILLIONS;

      await fakeWKaia.mockSetBalance(clPoolB.target, TWO);
      await fakeWKaia.mockSetBalance(clPoolC.target, FIVE);

      // Force set the balance of CnStakingV2C to 4M
      await setBalance(await cnStakingV2C.getAddress(), FOUR);

      await expect(stakingTracker.createTracker(trackStart, trackEnd))
        .to.emit(stakingTracker, "CreateTracker")
        .withArgs(1, trackStart, trackEnd, [700, 701, 702]);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [SIX, FOUR, SIX],
        [EIGHT, NINE, SIX],
        [1, 0, 1], // CnStakingV2C is not eligible since its CnStaking balance is less than 5M
      );

      // The addition of CLPoolC's balance should not affect the votes of CnStakingV2C
      await fakeWKaia.mockSetBalance(clPoolC.target, TEN);
      await expect(stakingTracker.refreshStake(clPoolC.target))
        .to.emit(stakingTracker, "RefreshStake")
        .withArgs(1, 701, clPoolC.target, TEN, TEN + FOUR, 0, 2);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [SIX, FOUR, SIX],
        [EIGHT, TEN + FOUR, SIX],
        [1, 0, 1],
      );
    });
  });
  describe("Refresh stake", function () {
    beforeEach(async function () {
      const { stakingTracker, trackStart, trackEnd } = fixture;
      const { TWO, FIVE } = MILLIONS;

      await fakeWKaia.mockSetBalance(clPoolB.target, TWO);
      await fakeWKaia.mockSetBalance(clPoolC.target, FIVE);

      // We have 1, 2, 1 votes for B, C, D respectively
      await stakingTracker.createTracker(trackStart, trackEnd);
    });
    it("#refreshStake: From CnStaking, eligible -> eligible", async function () {
      const { stakingTracker, cnStakingV2B, trackStart, trackEnd } = fixture;
      const { SIX, EIGHT, TEN, ELEVEN } = MILLIONS;

      await setBalance(await cnStakingV2B.getAddress(), EIGHT); // 6M -> 8M, votes: 1 -> 2

      await expect(stakingTracker.refreshStake(cnStakingV2B.target))
        .to.emit(stakingTracker, "RefreshStake")
        .withArgs(1, 700, cnStakingV2B.target, EIGHT, TEN, 2, 5);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [EIGHT, SIX, SIX],
        [TEN, ELEVEN, SIX],
        [2, 2, 1],
      );
    });
    it("#refreshStake: From CnStaking, eligible -> ineligible", async function () {
      const { stakingTracker, cnStakingV2B, trackStart, trackEnd } = fixture;
      const { FOUR, SIX, ELEVEN } = MILLIONS;
      await setBalance(await cnStakingV2B.getAddress(), FOUR); // 6M -> 4M, votes: 1 -> 0

      await expect(stakingTracker.refreshStake(cnStakingV2B.target))
        .to.emit(stakingTracker, "RefreshStake")
        .withArgs(1, 700, cnStakingV2B.target, FOUR, SIX, 0, 2);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [FOUR, SIX, SIX],
        [SIX, ELEVEN, SIX],
        [0, 1, 1], // the votes of CnStakingV2C are also capped by 1
      );
    });
    it("#refreshStake: From CnStaking, ineligible -> eligible", async function () {
      const { stakingTracker, cnStakingV2B, trackStart, trackEnd } = fixture;
      const { FOUR, SIX, EIGHT, TEN, ELEVEN } = MILLIONS;

      await setBalance(await cnStakingV2B.getAddress(), FOUR); // 6M -> 4M, votes: 1 -> 0
      await expect(stakingTracker.refreshStake(cnStakingV2B.target))
        .to.emit(stakingTracker, "RefreshStake")
        .withArgs(1, 700, cnStakingV2B.target, FOUR, SIX, 0, 2);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [FOUR, SIX, SIX],
        [SIX, ELEVEN, SIX],
        [0, 1, 1],
      );

      await setBalance(await cnStakingV2B.getAddress(), EIGHT); // 4M -> 8M, votes: 0 -> 2
      await expect(stakingTracker.refreshStake(cnStakingV2B.target))
        .to.emit(stakingTracker, "RefreshStake")
        .withArgs(1, 700, cnStakingV2B.target, EIGHT, TEN, 2, 5);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [EIGHT, SIX, SIX],
        [TEN, ELEVEN, SIX],
        [2, 2, 1],
      );
    });
    it("#refreshStake: From CnStaking, ineligible -> ineligible", async function () {
      const { stakingTracker, cnStakingV2B, trackStart, trackEnd } = fixture;
      const { TWO, FOUR, SIX, ELEVEN } = MILLIONS;
      await setBalance(await cnStakingV2B.getAddress(), FOUR); // 6M -> 4M, votes: 1 -> 0

      await expect(stakingTracker.refreshStake(cnStakingV2B.target))
        .to.emit(stakingTracker, "RefreshStake")
        .withArgs(1, 700, cnStakingV2B.target, FOUR, SIX, 0, 2);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [FOUR, SIX, SIX],
        [SIX, ELEVEN, SIX],
        [0, 1, 1],
      );

      await setBalance(await cnStakingV2B.getAddress(), TWO); // 4M -> 2M, votes: 0 -> 0
      await expect(stakingTracker.refreshStake(cnStakingV2B.target))
        .to.emit(stakingTracker, "RefreshStake")
        .withArgs(1, 700, cnStakingV2B.target, TWO, FOUR, 0, 2);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [TWO, SIX, SIX],
        [FOUR, ELEVEN, SIX],
        [0, 1, 1],
      );
    });
    it("#refreshStake: From CLPool, votes unchanged", async function () {
      const { stakingTracker, trackStart, trackEnd } = fixture;
      const { THREE, SIX, NINE, ELEVEN } = MILLIONS;

      await fakeWKaia.mockSetBalance(clPoolB.target, THREE); // 2M -> 3M, votes: 1 -> 1
      await expect(stakingTracker.refreshStake(clPoolB.target))
        .to.emit(stakingTracker, "RefreshStake")
        .withArgs(1, 700, clPoolB.target, THREE, NINE, 1, 4);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [SIX, SIX, SIX],
        [NINE, ELEVEN, SIX],
        [1, 2, 1],
      );
    });
    it("#refreshStake: From CLPool, votes increased", async function () {
      const { stakingTracker, trackStart, trackEnd } = fixture;
      const { FOUR, SIX, TEN, ELEVEN } = MILLIONS;

      await fakeWKaia.mockSetBalance(clPoolB.target, FOUR); // 2M -> 4M, votes: 1 -> 2
      await expect(stakingTracker.refreshStake(clPoolB.target))
        .to.emit(stakingTracker, "RefreshStake")
        .withArgs(1, 700, clPoolB.target, FOUR, TEN, 2, 5);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [SIX, SIX, SIX],
        [TEN, ELEVEN, SIX],
        [2, 2, 1],
      );
    });
    it("#refreshStake: From CLPool, votes decreased", async function () {
      const { stakingTracker, trackStart, trackEnd } = fixture;
      const { TWO, FOUR, SIX, EIGHT, TEN, ELEVEN } = MILLIONS;

      await fakeWKaia.mockSetBalance(clPoolB.target, FOUR); // 2M -> 4M, votes: 1 -> 2
      await expect(stakingTracker.refreshStake(clPoolB.target))
        .to.emit(stakingTracker, "RefreshStake")
        .withArgs(1, 700, clPoolB.target, FOUR, TEN, 2, 5);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [SIX, SIX, SIX],
        [TEN, ELEVEN, SIX],
        [2, 2, 1],
      );

      await fakeWKaia.mockSetBalance(clPoolB.target, TWO); // 4M -> 2M, votes: 2 -> 1
      await expect(stakingTracker.refreshStake(clPoolB.target))
        .to.emit(stakingTracker, "RefreshStake")
        .withArgs(1, 700, clPoolB.target, TWO, EIGHT, 1, 4);

      await verifyTrackerState(
        stakingTracker,
        1,
        trackStart,
        trackEnd,
        [700, 701, 702],
        [SIX, SIX, SIX],
        [EIGHT, ELEVEN, SIX],
        [1, 2, 1],
      );
    });
  });
});
