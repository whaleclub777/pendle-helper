// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/access/Ownable.sol";

import "pendle/interfaces/IPVeToken.sol";
import "./interfaces/IPVotingController.sol";
import "./interfaces/IPVotingEscrow.sol";

// ...interfaces moved to `src/interfaces/` to keep this file minimal

/**
 * @notice Simple wrapper that holds vePENDLE positions in the name of this contract.
 * Users can deposit PENDLE into this contract and the contract will call
 * `increaseLockPosition` on `VotingEscrowPendleMainchain` so the wrapper becomes
 * the ve-holder. The wrapper tracks simple 1:1 "shares" (1 share = 1 PENDLE deposited)
 * to represent a user's claim on the wrapper's underlying assets.
 *
 * Notes / limitations:
 * - This is intentionally minimal: it does NOT try to split ve balances across
 *   users on-chain (gauges read ve balances from the ve contract). Instead the
 *   wrapper aggregates locks to its own address and issues internal shares.
 * - Withdrawals of locked PENDLE are only possible once the wrapper's ve position
 *   expires; the owner can call `withdrawExpiredTo(...)` to pull the unlocked
 *   PENDLE back to an address for later distribution.
 */
contract VePendleWrapper is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable PENDLE;
    IPVotingEscrow public immutable VE;
    IPVotingController public immutable VOTING_CONTROLLER;

    // No per-user share accounting: all vPENDLE held by this wrapper is managed by the owner.

    event Deposited(address indexed from, uint256 amount, uint128 newVeBalance, uint128 newExpiry);
    event WithdrawnExpired(address indexed to, uint256 amount);

    constructor(IERC20 _pendle, IPVotingEscrow _ve, IPVotingController _votingController) Ownable(msg.sender) {
        PENDLE = _pendle;
        VE = _ve;
        VOTING_CONTROLLER = _votingController;

        // Approve ve contract to pull PENDLE from this wrapper when we call increaseLockPosition
        // Safe to set max in constructor because it's a one-time setup.
        // OpenZeppelin v5's SafeERC20 exposes `forceApprove` (and not `safeApprove`). Use that here.
        _pendle.forceApprove(address(_ve), type(uint256).max);
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
    function ownerBroadcastResults(uint64 chainId) external payable onlyOwner {
        VOTING_CONTROLLER.broadcastResults{value: msg.value}(chainId);
    }

    /**
     * @notice Owner-only: broadcast this wrapper's ve position to other chains.
     */
    function ownerBroadcastPosition(uint256[] calldata chainIds) external payable onlyOwner {
        VE.broadcastUserPosition{value: msg.value}(address(this), chainIds);
    }

    /**
     * @notice Owner-only convenience to withdraw expired locked PENDLE directly to the owner.
     */
    function withdrawExpiredToOwner() external onlyOwner returns (uint128 amount) {
        amount = VE.withdraw(); // ve will transfer unlocked PENDLE to this wrapper
        PENDLE.safeTransfer(owner(), amount);
        emit WithdrawnExpired(owner(), amount);
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
}
