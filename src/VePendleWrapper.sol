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
 * @notice Multi-market boosted vault: users deposit Pendle Market LP tokens for any registered market so that
 * this contract's vePENDLE position boosts everyone proportionally on a per-market basis. Each market keeps
 * isolated accounting (total LP, accRewardPerShare per reward token, unallocated rewards, user balances & debts).
 * Rewards are harvested lazily (any mutating action on a market triggers its harvest) and distributed using an
 * accRewardPerShare model (1e12 precision).
 *
 * Assumptions / design choices:
 * - Reward token set for a market is snapshotted when added and treated as immutable afterward.
 * - Rewards accruing while a market has zero total LP are stored as unallocated and released on next harvest.
 * - No automatic compounding or reward token conversions; users claim raw tokens.
 */
contract VePendleWrapper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable PENDLE;
    IPVotingEscrow public immutable VE;
    IPVotingController public immutable VOTING_CONTROLLER;
    // Fee applied on PENDLE reward claims (in basis points, 10000 = 100%). Can be initialized once.
    uint16 public immutable FEE_RATE_BPS;
    // Owner's accumulated claimable fees in PENDLE
    uint256 public pendleFees;

    // Precision constant (shared across markets)
    uint256 private constant ACC_PRECISION = 1e12;

    // === Multi-Market Support ===
    address[] public allMarkets; // enumeration helper

    struct MarketInfo {
        bool exists; // marker
        uint256 totalLp; // total LP deposited in this wrapper for the market
        // we need to make sure the rewardTokens for a market is immutable after addMarket
        address[] rewardTokens; // snapshot of reward tokens (immutable after add)
        mapping(address => uint256) accRewardPerShare; // rewardToken => acc per share
        mapping(address => uint256) unallocatedRewards; // rewardToken => amount (when totalLp == 0)
        mapping(address => uint256) lpBalance; // user => LP balance in this market
        mapping(address => mapping(address => uint256)) rewardDebt; // user => rewardToken => debt
    }

    mapping(address => MarketInfo) private marketInfo; // market => MarketInfo

    // Events
    event MarketAdded(address indexed market, address[] rewardTokens);
    event LpDeposited(address indexed market, address indexed user, uint256 amount);
    event LpWithdrawn(address indexed market, address indexed user, uint256 amount);
    event RewardsClaimed(address indexed market, address indexed user, address indexed rewardToken, uint256 amount);
    event Harvest(address indexed market, uint256[] amounts);
    event HarvestFailed(address indexed market, bytes reason);

    event Deposited(address indexed from, uint256 amount, uint128 newVeBalance, uint128 newExpiry); // PENDLE -> ve
    event WithdrawnExpired(address indexed to, uint256 amount);

    event OwnerFeesAccrued(address indexed token, uint256 amount);

    constructor(IERC20 _pendle, IPVotingEscrow _ve, IPVotingController _votingController, uint256 _feeRateBps)
        Ownable(msg.sender)
    {
        PENDLE = _pendle;
        VE = _ve;
        VOTING_CONTROLLER = _votingController;

        // Approve ve contract to pull PENDLE from this wrapper when we call increaseLockPosition
        // Safe to set max in constructor because it's a one-time setup.
        // OpenZeppelin v5's SafeERC20 exposes `forceApprove` (and not `safeApprove`). Use that here.
        _pendle.forceApprove(address(_ve), type(uint256).max);

        require(_feeRateBps <= 10000, "bps>10000");
        FEE_RATE_BPS = uint16(_feeRateBps);
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
                       MULTI-MARKET LP VAULT
    //////////////////////////////////////////////////////////////*/

    // ---------------------- Owner Admin ---------------------- //

    function addMarket(IPendleMarket newMarket) external {
        address m = address(newMarket);
        MarketInfo storage miCheck = marketInfo[m];
        require(!miCheck.exists, "Market exists");
        _addMarket(newMarket);
    }

    // Return the storage pointer so callers can use the MarketInfo directly
    function _addMarket(IPendleMarket newMarket) internal returns (MarketInfo storage mi) {
        address m = address(newMarket);
        mi = marketInfo[m];
        if (mi.exists) {
            return mi;
        }
        // mark as existing
        mi.exists = true;
        // Snapshot reward tokens
        try newMarket.getRewardTokens() returns (address[] memory rts) {
            mi.rewardTokens = rts;
        } catch {
            // leave empty if call fails
        }
        allMarkets.push(m);
        emit MarketAdded(m, mi.rewardTokens);
        return mi;
    }

    // ---------------------- User Actions ---------------------- //

    function depositLp(address market, uint256 amount) external nonReentrant {
        MarketInfo storage mi = _addMarket(IPendleMarket(market));
        require(mi.exists, "Market !exist");
        _depositLp(market, msg.sender, amount, mi);
    }

    function withdrawLp(address market, uint256 amount) external nonReentrant {
        MarketInfo storage mi = marketInfo[market];
        require(mi.exists, "Market !exist");
        _withdrawLp(market, msg.sender, amount, mi);
    }

    function claimRewards(address market) external nonReentrant {
        MarketInfo storage mi = marketInfo[market];
        require(mi.exists, "Market !exist");
        _harvest(market, mi);
        _settleUser(market, msg.sender, mi);
        _updateRewardDebt(market, msg.sender, mi);
    }

    function pendingRewards(address market, address user) external view returns (uint256[] memory amounts) {
        MarketInfo storage mi = marketInfo[market];
        require(mi.exists, "Market !exist");
        address[] storage rts = mi.rewardTokens;
        amounts = new uint256[](rts.length);
        uint256 userBal = mi.lpBalance[user];
        if (userBal == 0) return amounts;
        for (uint256 i = 0; i < rts.length; ++i) {
            address rt = rts[i];
            uint256 acc = mi.accRewardPerShare[rt];
            uint256 debt = mi.rewardDebt[user][rt];
            uint256 gross = (userBal * acc) / ACC_PRECISION;
            if (gross > debt) amounts[i] = gross - debt;
        }
    }

    // ---------------------- Views ---------------------- //
    function getRewardTokens(address market) external view returns (address[] memory) {
        return marketInfo[market].rewardTokens;
    }

    function marketsLength() external view returns (uint256) {
        return allMarkets.length;
    }

    function getAllMarkets() external view returns (address[] memory) {
        return allMarkets;
    }

    function lpBalanceOf(address market, address user) external view returns (uint256) {
        return marketInfo[market].lpBalance[user];
    }

    function totalLpOf(address market) external view returns (uint256) {
        return marketInfo[market].totalLp;
    }

    // ---------------------- Internal Core ---------------------- //
    function _depositLp(address market, address user, uint256 amount, MarketInfo storage mi) internal {
        require(amount > 0, "Zero amount");
        _harvest(market, mi);
        _settleUser(market, user, mi);

        IPendleMarket(market).transferFrom(user, address(this), amount);
        mi.lpBalance[user] += amount;
        mi.totalLp += amount;

        _updateRewardDebt(market, user, mi);
        emit LpDeposited(market, user, amount);
    }

    function _withdrawLp(address market, address user, uint256 amount, MarketInfo storage mi) internal {
        require(amount > 0, "Zero amount");
        uint256 bal = mi.lpBalance[user];
        require(bal >= amount, "Insufficient");

        _harvest(market, mi);
        _settleUser(market, user, mi);

        mi.lpBalance[user] = bal - amount;
        mi.totalLp -= amount;
        _updateRewardDebt(market, user, mi);

        IPendleMarket(market).transfer(user, amount);
        emit LpWithdrawn(market, user, amount);
    }

    function _harvest(address market, MarketInfo storage mi) internal {
        address[] storage rts = mi.rewardTokens;
        if (rts.length == 0) return; // nothing to distribute

        // Record balances before
        uint256[] memory beforeBal = new uint256[](rts.length);
        for (uint256 i = 0; i < rts.length; ++i) {
            beforeBal[i] = IERC20(rts[i]).balanceOf(address(this));
        }

        // Pull rewards from the given market
        // TODO: why try-catch? some markets may not implement redeemRewards?
        try IPendleMarket(market).redeemRewards(address(this)) returns (uint256[] memory amounts) {
            emit Harvest(market, amounts);
        } catch (bytes memory reason) {
            emit HarvestFailed(market, reason);
            return;
        }

        for (uint256 i = 0; i < rts.length; ++i) {
            address rt = rts[i];
            uint256 afterBal = IERC20(rt).balanceOf(address(this));
            uint256 delta = afterBal - beforeBal[i];
            if (delta == 0) continue;

            if (mi.totalLp == 0) {
                mi.unallocatedRewards[rt] += delta;
            } else {
                uint256 distribute = delta + mi.unallocatedRewards[rt];
                if (mi.unallocatedRewards[rt] > 0) mi.unallocatedRewards[rt] = 0;
                // TODO: math mulDiv
                mi.accRewardPerShare[rt] += (distribute * ACC_PRECISION) / mi.totalLp;
            }
        }
    }

    function _settleUser(address market, address user, MarketInfo storage mi) internal {
        uint256 userBal = mi.lpBalance[user];
        if (userBal == 0) return;
        address[] storage rts = mi.rewardTokens;
        for (uint256 i = 0; i < rts.length; ++i) {
            address rt = rts[i];
            uint256 acc = mi.accRewardPerShare[rt];
            uint256 debt = mi.rewardDebt[user][rt];
            uint256 gross = (userBal * acc) / ACC_PRECISION;
            if (gross <= debt) continue;
            uint256 pending = gross - debt;
            mi.rewardDebt[user][rt] = gross; // optimistic update before transfer
            // If reward token is PENDLE and fee rate is set, deduct fee and send to owner
            if (rt == address(PENDLE) && FEE_RATE_BPS > 0) {
                uint256 fee = (pending * FEE_RATE_BPS) / 10000;
                uint256 net = pending - fee;
                if (fee > 0) {
                    pendleFees += fee;
                    emit OwnerFeesAccrued(address(PENDLE), fee);
                }
                if (net > 0) IERC20(rt).safeTransfer(user, net);
                emit RewardsClaimed(market, user, rt, net);
            } else {
                // TODO: we could transfer to a new address
                IERC20(rt).safeTransfer(user, pending);
                emit RewardsClaimed(market, user, rt, pending);
            }
        }
    }

    /**
     * @notice Owner redeems accumulated fees for a specific token
     */
    function ownerRedeem() external onlyOwner {
        uint256 amt = pendleFees;
        require(amt > 0, "No fees");
        pendleFees = 0;
        PENDLE.safeTransfer(owner(), amt);
    }

    function _updateRewardDebt(address market, address user, MarketInfo storage mi) internal {
        uint256 userBal = mi.lpBalance[user];
        address[] storage rts = mi.rewardTokens;
        for (uint256 i = 0; i < rts.length; ++i) {
            address rt = rts[i];
            mi.rewardDebt[user][rt] = (userBal * mi.accRewardPerShare[rt]) / ACC_PRECISION;
        }
    }
}
