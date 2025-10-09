// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPendleMarket} from "../../src/interfaces/IPendleMarket.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice Mock Pendle market that actually distributes reward tokens each harvest call.
/// For simplicity, it transfers a fixed per-call amount of each reward token to the provided
/// user address (the wrapper) and returns the same amounts array.
contract RewardingMockPendleMarket is MockERC20, IPendleMarket {
    // ---------------- Basic config (public for test inspection) ----------------
    address[] public rewardTokens;

    // ---------------- Time-based emission model (Pendle-style approximation) ---
    uint256[] public emissionRatePerSec; // tokens emitted per second for each reward token
    uint256 public lastUpdate; // last timestamp emission accounting executed
    uint256[] public unclaimedAccrued; // accrued but not yet transferred (may exceed contract balance)

    // Mirror Pendle's gauge/market RedeemRewards event
    event RedeemRewards(address indexed user, uint256[] rewardsOut);
    /// @notice Emitted when a one-time emission is scheduled (credited to accrued rewards)
    event EmissionScheduled(uint256[] rewardsAdded);

    constructor(address[] memory rts) MockERC20("RewardingMarket", "RMKT") {
        _setRewardTokens(rts);
    }

    // ---------------- Reward token helpers ----------------
    /// @notice Set reward token list; resets emission arrays.
    function _setRewardTokens(address[] memory rts) internal {
        rewardTokens = rts;
        emissionRatePerSec = new uint256[](rts.length);
        unclaimedAccrued = new uint256[](rts.length);
        lastUpdate = block.timestamp;
    }

    // ---------------- Time Emission Configuration ----------------
    /// @notice Configure time-based emissions. Replaces previous reward token list.
    /// @dev rates are per-second emission amounts.
    function setEmissionRates(uint256[] memory ratesPerSec) external {
        require(rewardTokens.length == ratesPerSec.length, "len mismatch");
        emissionRatePerSec = ratesPerSec;
        unclaimedAccrued = new uint256[](rewardTokens.length);
        lastUpdate = block.timestamp;
    }

    /// @notice Update emission rates without resetting accrued amounts.
    function updateEmissionRates(uint256[] memory ratesPerSec) external {
        require(rewardTokens.length == ratesPerSec.length, "len mismatch");
        _accrue();
        emissionRatePerSec = ratesPerSec;
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    // ---------------- Core logic ----------------
    function redeemRewards(address user) external returns (uint256[] memory amounts) {
        // purely time-based redeem. If no time-emission configured, return zeros.
        _accrue();
        amounts = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            uint256 claimable = unclaimedAccrued[i];
            if (claimable == 0) continue;
            uint256 bal = MockERC20(rewardTokens[i]).balanceOf(address(this));
            if (bal < claimable) {
                // mint the shortfall to ensure full claimable can be paid
                uint256 shortfall = claimable - bal;
                MockERC20(rewardTokens[i]).mint(address(this), shortfall);
            }
            if (claimable > 0) {
                // deduct the full claimable amount (we minted if necessary)
                unclaimedAccrued[i] -= claimable;
                MockERC20(rewardTokens[i]).transfer(user, claimable);
                amounts[i] = claimable;
            }
        }
        emit RedeemRewards(user, amounts);
    }

    /// @notice Perform a one-time emission: immediately transfer specified amounts for each reward token to `user`.
    /// @dev `amounts` must be the same length as `rewardTokens`. This is a manual emission helper useful for tests.
    /// @notice Schedule a one-time emission by crediting `unclaimedAccrued` for each reward token.
    /// @dev Amounts are added to `unclaimedAccrued` and will be transferred on next `redeemRewards` call.
    function oneTimeEmission(uint256[] memory amounts) external returns (uint256[] memory) {
        require(amounts.length == rewardTokens.length, "len mismatch");
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            uint256 amt = amounts[i];
            if (amt == 0) continue;
            unclaimedAccrued[i] += amt;
        }
        emit EmissionScheduled(amounts);
        return amounts;
    }

    function _accrue() internal {
        uint256 dt = block.timestamp - lastUpdate;
        if (dt == 0) return;
        for (uint256 i = 0; i < emissionRatePerSec.length; ++i) {
            uint256 rate = emissionRatePerSec[i];
            if (rate > 0) {
                unclaimedAccrued[i] += rate * dt;
            }
        }
        lastUpdate = block.timestamp;
    }
}
