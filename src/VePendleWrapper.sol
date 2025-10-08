// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";

import "pendle/interfaces/IPVeToken.sol";
import "./interfaces/IPVotingController.sol";
import "./interfaces/IPVotingEscrow.sol";
import "./interfaces/IPendleMarket.sol";

// ...interfaces moved to `src/interfaces/` to keep this file minimal


/**
 * @notice Single-market boosted vault extension: users deposit a specific Pendle Market LP token here so that
 * this contract's vePENDLE position boosts everyone proportionally. Rewards are periodically harvested from
 * the market (by any mutating action: deposit / withdraw / claim) and distributed using a simple
 * accRewardPerShare accounting model (1e12 precision).
 *
 * Limitations / assumptions:
 * - Only ONE market (LP token) is supported per deployment (immutable `MARKET`).
 * - The set of reward tokens for the market is assumed static after deployment (snapshot taken in constructor).
 * - No compounding / auto-selling of rewards; users claim raw tokens.
 * - If rewards accrue while total LP supply is zero, they are stored as `unallocatedRewards` and distributed
 *   on the next harvest when supply > 0.
 */
contract VePendleWrapper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable PENDLE;
    IPVotingEscrow public immutable VE;
    IPVotingController public immutable VOTING_CONTROLLER;

    // === Boosted LP Market (single) ===
    IPendleMarket public immutable MARKET; // Pendle market (LP token)

    // User LP balances & total (these represent shares in the boosted LP vault ONLY, unrelated to ve)
    mapping(address => uint256) public lpBalance;
    uint256 public totalLpBalance;

    // Reward tokens snapshot + accounting
    address[] public rewardTokens; // immutable set after construction
    uint256 private constant ACC_PRECISION = 1e12;
    mapping(address => uint256) public accRewardPerShare; // rewardToken => accumulated per 1 LP (scaled)
    mapping(address => mapping(address => uint256)) public rewardDebt; // user => rewardToken => debt
    mapping(address => uint256) public unallocatedRewards; // rewards accrued while totalLpBalance == 0

    // Events
    event LpDeposited(address indexed user, uint256 amount);
    event LpWithdrawn(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, address indexed rewardToken, uint256 amount);
    event Harvest(uint256[] amounts);
    event HarvestFailed(bytes reason);

    event Deposited(address indexed from, uint256 amount, uint128 newVeBalance, uint128 newExpiry); // PENDLE -> ve
    event WithdrawnExpired(address indexed to, uint256 amount);

    constructor(
        IERC20 _pendle,
        IPVotingEscrow _ve,
        IPVotingController _votingController,
        IPendleMarket _market
    ) Ownable(msg.sender) {
        PENDLE = _pendle;
        VE = _ve;
        VOTING_CONTROLLER = _votingController;
        MARKET = _market;

        // Approve ve contract to pull PENDLE from this wrapper when we call increaseLockPosition
        // Safe to set max in constructor because it's a one-time setup.
        // OpenZeppelin v5's SafeERC20 exposes `forceApprove` (and not `safeApprove`). Use that here.
        _pendle.forceApprove(address(_ve), type(uint256).max);

        // Snapshot reward tokens from market (assumed stable)
        try _market.getRewardTokens() returns (address[] memory rts) {
            rewardTokens = rts;
        } catch {
            // If call fails, leave empty; contract will still function but no reward distribution
        }
    }

    /**
     * @notice Returns the stored ve balance of this wrapper (view).
     * Note: may be stale if slope changes haven't been applied. For an up-to-date
     * balance call `getVeBalanceCurrent` which invokes the non-view helper on the ve contract.
     */
    function getVeBalanceStored() external view returns (uint128) {
        return IPVeToken(address(VE)).balanceOf(address(this));
    }

    /**
     * @notice Returns the current ve balance for this wrapper by calling the ve contract's
     * `totalSupplyAndBalanceCurrent`. This is a non-view call on the target contract but
     * can be invoked as an eth_call from off-chain code to simulate the result.
     */
    function getVeBalanceCurrent() external returns (uint128) {
        (, uint128 balance) = IPVeToken(address(VE)).totalSupplyAndBalanceCurrent(address(this));
        return balance;
    }

    /**
     * @notice Owner-only: call the voting controller's `vote` as this wrapper contract.
     * This will have `msg.sender == address(this)` in the voting controller, so the
     * controller will treat the wrapper as the ve-holder (allowed when the wrapper
     * has ve balance).
     */
    function ownerVote(address[] calldata pools, uint64[] calldata weights) external onlyOwner {
        VOTING_CONTROLLER.vote(pools, weights);
    }

    /**
     * @notice Owner-only: broadcast voting results for a chain via the voting controller.
     */
    function broadcastResults(uint64 chainId) external payable {
        VOTING_CONTROLLER.broadcastResults{value: msg.value}(chainId);
    }

    /**
     * @notice Owner-only: broadcast this wrapper's ve position to other chains.
     */
    function broadcastPosition(uint256[] calldata chainIds) external payable {
        VE.broadcastUserPosition{value: msg.value}(address(this), chainIds);
    }

    /**
     * @notice Deposit PENDLE into this wrapper and increase the wrapper's lock position.
     * @dev Caller must approve this contract to spend `amount` PENDLE prior to calling.
     * @param amount amount of PENDLE to deposit (in PENDLE's decimals)
     * @param newExpiry new expiry (must satisfy the ve contract's rules)
     * @return newVeBalance the wrapper's ve balance returned by the ve contract after the call
     */
    function depositAndLock(uint128 amount, uint128 newExpiry) external returns (uint128 newVeBalance) {
        require(amount > 0, "Zero amount");

        // pull PENDLE from sender
        PENDLE.safeTransferFrom(msg.sender, address(this), amount);

        // Call increaseLockPosition as this contract (so ve position belongs to this wrapper)
        newVeBalance = VE.increaseLockPosition(amount, newExpiry);

        // No shares are minted; all vePENDLE belongs to the wrapper and is managed by the owner.
        emit Deposited(msg.sender, amount, newVeBalance, newExpiry);
    }

    /**
     * @notice Convenience function to deposit PENDLE, increase lock and then broadcast the wrapper's
     * position to other chains in one call. Any msg.value will be forwarded to the `broadcastUserPosition` call.
     * @param amount amount of PENDLE to deposit
     * @param newExpiry expiry timestamp
     * @param chainIds destination chains for the broadcast
     */
    function depositLockAndBroadcast(uint128 amount, uint128 newExpiry, uint256[] calldata chainIds)
        external
        payable
        returns (uint128 newVeBalance)
    {
        require(amount > 0, "Zero amount");

        PENDLE.safeTransferFrom(msg.sender, address(this), amount);

        newVeBalance = VE.increaseLockPosition(amount, newExpiry);

        // No shares are minted; all vePENDLE belongs to the wrapper and is managed by the owner.

        // forward the ETH to the broadcast call
        VE.broadcastUserPosition{value: msg.value}(address(this), chainIds);
        emit Deposited(msg.sender, amount, newVeBalance, newExpiry);
    }

    /**
     * @notice Owner-only helper: if the wrapper's ve position expired, withdraw underlying PENDLE
     * from the ve contract and send it to `to`.
     * @dev Only the owner can call this to avoid accidental distribution logic in this minimal wrapper.
     */
    function withdrawExpiredTo(address to) external onlyOwner returns (uint128 amount) {
        require(to != address(0), "Zero address");
        amount = VE.withdraw(); // ve will transfer unlocked PENDLE to this wrapper
        PENDLE.safeTransfer(to, amount);
        emit WithdrawnExpired(to, amount);
    }

    /**
     * @notice Emergency: transfer raw PENDLE balance held by this wrapper to `to`.
     * @dev Only owner can call.
     */
    function emergencyPullPendle(address to) external onlyOwner {
        require(to != address(0), "Zero address");
        uint256 bal = PENDLE.balanceOf(address(this));
        if (bal > 0) PENDLE.safeTransfer(to, bal);
    }

    /*//////////////////////////////////////////////////////////////
                              LP VAULT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit Pendle Market LP tokens to be boosted by this contract's ve position.
     * Caller must approve `amount` LP to this contract first.
     */
    function depositLp(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");
        _harvest();
        _settleUser(msg.sender); // settle rewards before balance change

        MARKET.transferFrom(msg.sender, address(this), amount);
        lpBalance[msg.sender] += amount;
        totalLpBalance += amount;

        _updateRewardDebt(msg.sender);
        emit LpDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw LP tokens.
     */
    function withdrawLp(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");
        uint256 bal = lpBalance[msg.sender];
        require(bal >= amount, "Insufficient");

        _harvest();
        _settleUser(msg.sender);

        lpBalance[msg.sender] = bal - amount;
        totalLpBalance -= amount;
        _updateRewardDebt(msg.sender);

        MARKET.transfer(msg.sender, amount);
        emit LpWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Claim all accrued rewards for caller.
     */
    function claimRewards() external nonReentrant {
        _harvest();
        _settleUser(msg.sender);
        _updateRewardDebt(msg.sender);
    }

    /**
     * @notice View function returning pending rewards (without harvesting new ones from market).
     * This ignores yet-to-be-harvested rewards currently sitting in the market.
     */
    function pendingRewards(address user) external view returns (uint256[] memory amounts) {
        address[] memory rts = rewardTokens;
        amounts = new uint256[](rts.length);
        uint256 userBal = lpBalance[user];
        if (userBal == 0) return amounts;
        for (uint256 i = 0; i < rts.length; ++i) {
            uint256 acc = accRewardPerShare[rts[i]];
            uint256 debt = rewardDebt[user][rts[i]];
            uint256 gross = (userBal * acc) / ACC_PRECISION;
            if (gross > debt) amounts[i] = gross - debt;
        }
    }

    function getRewardTokens() external view returns (address[] memory) { return rewardTokens; }
    function rewardTokensLength() external view returns (uint256) { return rewardTokens.length; }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    function _harvest() internal {
        if (rewardTokens.length == 0) return; // nothing to distribute

        // Record balances before
        uint256[] memory beforeBal = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            beforeBal[i] = IERC20(rewardTokens[i]).balanceOf(address(this));
        }

        // Pull rewards from market (accrues for THIS contract address only)
        try MARKET.redeemRewards(address(this)) returns (uint256[] memory amounts) {
            emit Harvest(amounts); // informational
        } catch (bytes memory reason) {
            emit HarvestFailed(reason); // skip distribution this time
            return;
        }

        // Compute deltas & update accounting
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            address rt = rewardTokens[i];
            uint256 afterBal = IERC20(rt).balanceOf(address(this));
            uint256 delta = afterBal - beforeBal[i];
            if (delta == 0) continue;

            if (totalLpBalance == 0) {
                // store until someone supplies LP
                unallocatedRewards[rt] += delta;
            } else {
                uint256 distribute = delta + unallocatedRewards[rt];
                if (unallocatedRewards[rt] > 0) unallocatedRewards[rt] = 0;
                accRewardPerShare[rt] += (distribute * ACC_PRECISION) / totalLpBalance;
            }
        }
    }

    function _settleUser(address user) internal {
        uint256 userBal = lpBalance[user];
        if (userBal == 0) return;
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            address rt = rewardTokens[i];
            uint256 acc = accRewardPerShare[rt];
            uint256 debt = rewardDebt[user][rt];
            uint256 gross = (userBal * acc) / ACC_PRECISION;
            if (gross <= debt) continue;
            uint256 pending = gross - debt;
            rewardDebt[user][rt] = gross; // optimistic update before transfer
            IERC20(rt).safeTransfer(user, pending);
            emit RewardsClaimed(user, rt, pending);
        }
    }

    function _updateRewardDebt(address user) internal {
        uint256 userBal = lpBalance[user];
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            address rt = rewardTokens[i];
            rewardDebt[user][rt] = (userBal * accRewardPerShare[rt]) / ACC_PRECISION;
        }
    }
}
