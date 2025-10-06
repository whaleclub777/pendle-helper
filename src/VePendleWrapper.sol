// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../vendor/pendle-core-v2-public/contracts/interfaces/IPVotingEscrowMainchain.sol";
import "../vendor/pendle-core-v2-public/contracts/interfaces/IPVeToken.sol";

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

    IERC20 public immutable pendle;
    IPVotingEscrowMainchain public immutable ve;

    // Simple share accounting: 1 share == 1 PENDLE deposited
    mapping(address => uint256) public shares;
    uint256 public totalShares;

    event Deposited(address indexed from, uint256 amount, uint256 sharesMinted, uint128 newVeBalance, uint128 newExpiry);
    event WithdrawnExpired(address indexed to, uint256 amount);

    constructor(IERC20 _pendle, IPVotingEscrowMainchain _ve) {
        pendle = _pendle;
        ve = _ve;

        // Approve ve contract to pull PENDLE from this wrapper when we call increaseLockPosition
        // Safe to set max in constructor because it's a one-time setup.
        _pendle.safeApprove(address(_ve), type(uint256).max);
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
        pendle.safeTransferFrom(msg.sender, address(this), amount);

        // Call increaseLockPosition as this contract (so ve position belongs to this wrapper)
        newVeBalance = ve.increaseLockPosition(amount, newExpiry);

        // Mint 1:1 shares for depositor
        shares[msg.sender] += amount;
        totalShares += amount;

        emit Deposited(msg.sender, amount, amount, newVeBalance, newExpiry);
    }

    /**
     * @notice Convenience function to deposit PENDLE, increase lock and then broadcast the wrapper's
     * position to other chains in one call. Any msg.value will be forwarded to the `broadcastUserPosition` call.
     * @param amount amount of PENDLE to deposit
     * @param newExpiry expiry timestamp
     * @param chainIds destination chains for the broadcast
     */
    function depositLockAndBroadcast(uint128 amount, uint128 newExpiry, uint256[] calldata chainIds) external payable returns (uint128 newVeBalance) {
        require(amount > 0, "Zero amount");

        pendle.safeTransferFrom(msg.sender, address(this), amount);

        newVeBalance = ve.increaseLockPosition(amount, newExpiry);

        // Mint shares
        shares[msg.sender] += amount;
        totalShares += amount;

        // forward the ETH to the broadcast call
        ve.broadcastUserPosition{value: msg.value}(address(this), chainIds);

        emit Deposited(msg.sender, amount, amount, newVeBalance, newExpiry);
    }

    /**
     * @notice Returns the stored ve balance of this wrapper (view).
     * Note: may be stale if slope changes haven't been applied. For an up-to-date
     * balance call `getVeBalanceCurrent` which invokes the non-view helper on the ve contract.
     */
    function getVeBalanceStored() external view returns (uint128) {
        return IPVeToken(address(ve)).balanceOf(address(this));
    }

    /**
     * @notice Returns the current ve balance for this wrapper by calling the ve contract's
     * `totalSupplyAndBalanceCurrent`. This is a non-view call on the target contract but
     * can be invoked as an eth_call from off-chain code to simulate the result.
     */
    function getVeBalanceCurrent() external returns (uint128) {
        (, uint128 balance) = IPVeToken(address(ve)).totalSupplyAndBalanceCurrent(address(this));
        return balance;
    }

    /**
     * @notice Owner-only helper: if the wrapper's ve position expired, withdraw underlying PENDLE
     * from the ve contract and send it to `to`.
     * @dev Only the owner can call this to avoid accidental distribution logic in this minimal wrapper.
     */
    function withdrawExpiredTo(address to) external onlyOwner returns (uint128 amount) {
        require(to != address(0), "Zero address");
        amount = ve.withdraw(); // ve will transfer unlocked PENDLE to this wrapper
        pendle.safeTransfer(to, amount);
        emit WithdrawnExpired(to, amount);
    }

    /**
     * @notice Emergency: transfer raw PENDLE balance held by this wrapper to `to`.
     * @dev Only owner can call.
     */
    function emergencyPullPendle(address to) external onlyOwner {
        require(to != address(0), "Zero address");
        uint256 bal = pendle.balanceOf(address(this));
        if (bal > 0) pendle.safeTransfer(to, bal);
    }
}
