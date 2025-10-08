# MasterPenpie API — Quick reference

This file maps every function in `IMasterPenpie` to a short description, typical caller/permission (as enforced by `MasterPenpie.sol`), return values, and a short example (ethers.js style). Use this for frontend / scripts.

Notes:
- The interface declares calls; concrete permissions are implemented in `rewards/MasterPenpie.sol` (owner, PoolManager, compounder, vlPenpie, etc.).
- Replace `<MASTER_PENPIE_ADDRESS>` and `<ABI>` with actual values in examples.

## Read-only helpers

- poolLength()
  - Signature: `function poolLength() external view returns (uint256)`
  - Permission: public (any caller)
  - Purpose: number of registered pools
  - Example: await masterPenpie.poolLength()

- getPoolInfo(address token)
  - Signature: `function getPoolInfo(address token) external view returns (uint256 emission, uint256 allocpoint, uint256 sizeOfPool, uint256 totalPoint)`
  - Permission: public
  - Purpose: snapshot of per-pool emission, alloc, size, and global totalPoint
  - Example: await masterPenpie.getPoolInfo(stakingToken)

- pendingTokens(address _stakingToken, address _user, address token)
  - Signature: `function pendingTokens(address _stakingToken, address _user, address token) external view returns (uint256 _pendingGMP, address _bonusTokenAddress, string memory _bonusTokenSymbol, uint256 _pendingBonusToken)`
  - Permission: public
  - Purpose: pending PNP for user plus pending amount for a specific bonus token
  - Example: await masterPenpie.pendingTokens(poolAddr, userAddr, bonusTokenAddr)

- allPendingTokens(address _stakingToken, address _user)
  - Signature: `function allPendingTokens(address _stakingToken, address _user) external view returns (uint256 pendingPenpie, address[] memory bonusTokenAddresses, string[] memory bonusTokenSymbols, uint256[] memory pendingBonusRewards)`
  - Permission: public
  - Purpose: returns pending PNP and arrays of all bonus tokens + pending amounts for the user
  - Example: await masterPenpie.allPendingTokens(poolAddr, userAddr)

- allPendingTokensWithBribe(address _stakingToken, address _user, IBribeRewardDistributor.Claim[] calldata _proof)
  - Signature: `function allPendingTokensWithBribe(address _stakingToken, address _user, IBribeRewardDistributor.Claim[] calldata _proof) external view returns (uint256 pendingPenpie, address[] memory bonusTokenAddresses, string[] memory bonusTokenSymbols, uint256[] memory pendingBonusRewards)`
  - Permission: public
  - Purpose: same as `allPendingTokens` but accepts bribe proof to include bribe rewards where applicable
  - Example: await masterPenpie.allPendingTokensWithBribe(poolAddr, userAddr, proof)

- stakingInfo(address _stakingToken, address _user)
  - Signature: `function stakingInfo(address _stakingToken, address _user) external view returns (uint256 depositAmount, uint256 availableAmount)`
  - Permission: public
  - Purpose: user deposit and available amount (useful for lockers)
  - Example: await masterPenpie.stakingInfo(poolAddr, userAddr)

- totalTokenStaked(address _stakingToken)
  - Signature: `function totalTokenStaked(address _stakingToken) external view returns (uint256)`
  - Permission: public
  - Purpose: pool total staked
  - Example: await masterPenpie.totalTokenStaked(poolAddr)

- getRewarder(address _stakingToken)
  - Signature: `function getRewarder(address _stakingToken) external view returns (address rewarder)`
  - Purpose: returns rewarder (bonus token manager) attached to the pool
  - Example: await masterPenpie.getRewarder(poolAddr)

## Update / admin / manager functions

- setPoolManagerStatus(address _address, bool _bool)
  - Signature: `function setPoolManagerStatus(address _address, bool _bool) external`
  - Permission: owner
  - Purpose: grant or revoke pool manager role (can add/set/remove pools)
  - Example: await masterPenpie.setPoolManagerStatus(managerAddr, true)

- add(uint256 _allocPoint, address _stakingTokenToken, address _receiptToken, address _rewarder)
  - Signature: `function add(uint256 _allocPoint, address _stakingTokenToken, address _receiptToken, address _rewarder) external`
  - Permission: PoolManager
  - Purpose: register a new pool with the staking token, its receipt token and optional rewarder
  - Example: await masterPenpie.add(100, stakingToken, receiptToken, rewarderAddr)
  - Notes: staking/receipt must be contracts; receipt token must not already be used.

- set(address _stakingToken, uint256 _allocPoint, address _rewarder, bool _isActive)
  - Signature: `function set(address _stakingToken, uint256 _allocPoint, address _rewarder, bool _isActive) external`
  - Permission: PoolManager
  - Purpose: change pool allocation points, rewarder and active flag
  - Example: await masterPenpie.set(poolAddr, 50, newRewarder, true)

- removePool(address _stakingToken)
  - Signature: `function removePool(address _stakingToken) external`
  - Permission: PoolManager
  - Purpose: delete a pool (reduces totalAllocPoint, removes registry entry)
  - Example: await masterPenpie.removePool(poolAddr)

- createRewarder(address _stakingTokenToken, address mainRewardToken) returns (address)
  - Signature: `function createRewarder(address _stakingTokenToken, address mainRewardToken) external returns (address)`
  - Permission: PoolManager
  - Purpose: factory helper to deploy a `BaseRewardPoolV2` rewarder for a receipt token
  - Example: const rewarder = await masterPenpie.createRewarder(receiptToken, bonusToken)

- updatePoolsAlloc(address[] calldata _stakingTokens, uint256[] calldata _allocPoints) *(note: present in implementation as `updatePoolsAlloc` rather than in interface)*
  - Permission: whitelisted AllocationManagers / PoolManagers / owner
  - Purpose: bulk update allocations (implementation-level: check `MasterPenpie.sol`)

- updateEmissionRate(uint256 _gmpPerSec)
  - Signature: `function updateEmissionRate(uint256 _gmpPerSec) external`
  - Permission: owner
  - Purpose: change `penpiePerSec` after calling `massUpdatePools()` to avoid accounting drift
  - Example: await masterPenpie.updateEmissionRate(newRate)

## Pool updates & gas-heavy ops

- massUpdatePools()
  - Signature: `function massUpdatePools() external`
  - Permission: any (but usually owner or manager)
  - Purpose: call `updatePool` for every registered pool (gas heavy)
  - Example: await masterPenpie.massUpdatePools()

- updatePool(address _stakingToken)
  - Signature: `function updatePool(address _stakingToken) external`
  - Permission: public
  - Purpose: sync pool accrual to the current block timestamp and update `accPenpiePerShare`
  - Example: await masterPenpie.updatePool(poolAddr)

## Staking / withdrawing (user flows)

- deposit(address _stakingToken, uint256 _amount)
  - Signature: `function deposit(address _stakingToken, uint256 _amount) external`
  - Permission: any user (caller must have approved `stakingToken` transfer)
  - Purpose: stake `stakingToken`; implementation mints receipt token to caller and transfers tokens into MasterPenpie
  - Example: await masterPenpie.deposit(poolAddr, amount)

- depositFor(address _stakingToken, address _for, uint256 _amount)
  - Signature: `function depositFor(address _stakingToken, address _for, uint256 _amount) external`
  - Permission: any (caller transfers tokens), used when depositing on behalf of another user
  - Purpose: mint receipt tokens to `_for` and credit their `userInfo`
  - Example: await masterPenpie.depositFor(poolAddr, beneficiaryAddr, amount)

- withdraw(address _stakingToken, uint256 _amount)
  - Signature: `function withdraw(address _stakingToken, uint256 _amount) external`
  - Permission: any user who holds receipt tokens
  - Purpose: burn receipt tokens and withdraw underlying `stakingToken` to caller
  - Example: await masterPenpie.withdraw(poolAddr, amount)

- emergencyWithdraw(address _stakingToken, address sender)
  - Signature: `function emergencyWithdraw(address _stakingToken, address sender) external`
  - Permission: implementation-specific (check MasterPenpie.sol)
  - Purpose: emergency path to recover tokens in extreme cases; semantics depend on implementation

## Receipt-token hooks (must be called by receipt tokens)

- beforeReceiptTokenTransfer(address _from, address _to, uint256 _amount)
  - Signature: `function beforeReceiptTokenTransfer(address _from, address _to, uint256 _amount) external`
  - Permission: only the pool's registered `receiptToken` (implementation enforces `_onlyReceiptToken`)
  - Purpose: called by receipt token before any transfer/mint/burn to update pool and harvest rewards for `_from` and `_to` as needed
  - Example (receipt token): IMasterPenpie(masterPenpie).beforeReceiptTokenTransfer(from, to, amount)

- afterReceiptTokenTransfer(address _from, address _to, uint256 _amount)
  - Signature: `function afterReceiptTokenTransfer(address _from, address _to, uint256 _amount) external`
  - Permission: only the receiptToken
  - Purpose: called after transfer to update `userInfo` balances, `rewardDebt`, and `pool.totalStaked`

## Special locker entry points (only callable by locker contracts)

- depositVlPenpieFor(uint256 _amount, address sender)
  - Signature: `function depositVlPenpieFor(uint256 _amount, address sender) external`
  - Permission: only the `vlPenpie` contract (see implementation's `_onlyVlPenpie` modifier)
  - Purpose: allow vlPenpie to credit user balances in MasterPenpie when users lock PNP
  - Example: vlPenpieContract calls masterPenpie.depositVlPenpieFor(amount, user)

- withdrawVlPenpieFor(uint256 _amount, address sender)
  - Signature: `function withdrawVlPenpieFor(uint256 _amount, address sender) external`
  - Permission: only `vlPenpie`
  - Purpose: reverse of depositVlPenpieFor

- depositMPendleSVFor(uint256 _amount, address sender)
  - Signature: `function depositMPendleSVFor(uint256 _amount, address sender) external`
  - Permission: only `mPendleSV` contract
  - Purpose: allow mPendleSV to credit user balances

- withdrawMPendleSVFor(uint256 _amount, address sender)
  - Signature: `function withdrawMPendleSVFor(uint256 _amount, address sender) external`
  - Permission: only `mPendleSV`
  - Purpose: reverse of depositMPendleSVFor

## Claiming

- multiclaim(address[] calldata _stakingTokens)
  - Signature: `function multiclaim(address[] calldata _stakingTokens) external`
  - Permission: any user (claims for msg.sender)
  - Purpose: claim PNP and default bonus tokens across provided pools for caller
  - Example: await masterPenpie.multiclaim([poolA, poolB])

- multiclaimFor(address[] calldata _stakingTokens, address[][] calldata _rewardTokens, address user_address)
  - Signature: `function multiclaimFor(address[] calldata _stakingTokens, address[][] calldata _rewardTokens, address user_address) external`
  - Permission: any (claims for `user_address`), often used by off-chain services or contract-based helpers
  - Purpose: claim PNP and explicitly selected bonus tokens for `user_address`
  - Example: await masterPenpie.multiclaimFor([poolA], [[bonusToken1]], userAddr)

- multiclaimOnBehalf(address[] memory _stakingTokens, address[][] calldata _rewardTokens, address user_address, bool _isClaimPNP)
  - Signature: `function multiclaimOnBehalf(address[] memory _stakingTokens, address[][] calldata _rewardTokens, address user_address, bool _isClaimPNP) external`
  - Permission: only `compounder` in implementation (`_onlyCompounder`)
  - Purpose: allow a compounder contract to claim on behalf of users; `_isClaimPNP` controls whether PNP is sent or only accounted

## Quick examples (ethers.js)

// instantiate
// const masterPenpie = new ethers.Contract(MASTER_PENPIE_ADDRESS, ABI, signerOrProvider)

// get pool length
// await masterPenpie.poolLength()

// deposit (user)
// await stakingTokenContract.connect(user).approve(masterPenpie.address, amount)
// await masterPenpie.connect(user).deposit(stakingTokenAddress, amount)

// check pending
// await masterPenpie.pendingTokens(stakingTokenAddress, userAddress, bonusTokenAddress)

// claim
// await masterPenpie.connect(user).multiclaim([stakingTokenAddress])

---

If you'd like I can also generate `docs/masterpenpie_api.json` (small ABI only with the interface functions) so frontends can import it directly. Want that next?
