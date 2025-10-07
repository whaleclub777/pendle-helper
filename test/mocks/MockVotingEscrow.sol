// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../mocks/MockERC20.sol";

/// @notice Minimal mock of the VotingEscrow used by VePendleWrapper tests.
contract MockVotingEscrow {
    MockERC20 public pendle;

    // simple bookkeeping: locked amount and expiry
    uint128 public lockedAmount;
    uint128 public lockedExpiry;

    constructor(address _pendle) {
        pendle = MockERC20(_pendle);
    }

    // Simulate increasing the lock position: transfer PENDLE from caller to this contract
    // and set lockedAmount/expiry. Return the ve balance (we'll just return lockedAmount)
    function increaseLockPosition(uint128 amount, uint128 newExpiry) external returns (uint128) {
        // transfer PENDLE from caller
        require(pendle.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
        lockedAmount += amount;
        lockedExpiry = newExpiry;
        return lockedAmount;
    }

    // withdraw any expired PENDLE back to caller: only allow if block.timestamp >= expiry
    function withdraw() external returns (uint128) {
        require(block.timestamp >= lockedExpiry, "not expired");
        uint128 amt = lockedAmount;
        lockedAmount = 0;
        // transfer pendle back to caller
        require(pendle.transfer(msg.sender, amt), "transfer failed");
        return amt;
    }

    // minimal broadcast helper (payable)
    event BroadcastPosition(address user, uint256[] chainIds, uint256 value);
    function broadcastUserPosition(address user, uint256[] calldata chainIds) external payable {
        emit BroadcastPosition(user, chainIds, msg.value);
    }

    // view helpers used by VePendleWrapper via IPVeToken
    function balanceOf(address /*user*/) external view returns (uint128) {
        return lockedAmount;
    }

    function totalSupplyAndBalanceCurrent(address /*user*/) external view returns (uint128, uint128) {
        return (lockedAmount, lockedAmount);
    }
}
