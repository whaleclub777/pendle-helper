// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPendleMarket} from "../../src/interfaces/IPendleMarket.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice Mock Pendle market that actually distributes reward tokens each harvest call.
/// For simplicity, it transfers a fixed per-call amount of each reward token to the provided
/// user address (the wrapper) and returns the same amounts array.
contract RewardingMockPendleMarket is MockERC20, IPendleMarket {
    address[] public rewardTokens;
    uint256[] public perHarvest; // amount of each reward token to send every redeemRewards

    constructor() MockERC20("RewardingMarket", "RMKT") {}

    function setRewards(address[] memory rts, uint256[] memory amounts) external {
        require(rts.length == amounts.length, "len mismatch");
        rewardTokens = rts;
        perHarvest = amounts;
    }

    function addRewardToken(address rt, uint256 amountPerHarvest) external {
        rewardTokens.push(rt);
        perHarvest.push(amountPerHarvest);
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function redeemRewards(address user) external returns (uint256[] memory amounts) {
        amounts = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            uint256 amt = perHarvest[i];
            if (amt > 0) {
                MockERC20(rewardTokens[i]).transfer(user, amt);
                amounts[i] = amt;
            }
        }
    }
}
