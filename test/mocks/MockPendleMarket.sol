// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPendleMarket} from "../../src/interfaces/IPendleMarket.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice Minimal mock of a Pendle market used in tests. Implements the small
/// subset the wrapper expects: redeemRewards, getRewardTokens and ERC20 methods.
contract MockPendleMarket is MockERC20, IPendleMarket {
  address[] public rewardTokens;

  constructor() MockERC20("MockMarket", "MMKT") {}

  function addRewardToken(address rt) external {
    rewardTokens.push(rt);
  }

  function getRewardTokens() external view returns (address[] memory) {
    return rewardTokens;
  }

  /// @notice Redeem rewards for a user. For tests we simply return zeros
  /// (no-op) but provide the expected return shape.
  function redeemRewards(address /*user*/ ) external returns (uint256[] memory amounts) {
    amounts = new uint256[](rewardTokens.length);
    for (uint256 i = 0; i < rewardTokens.length; ++i) {
      amounts[i] = 0;
    }
  }
}
