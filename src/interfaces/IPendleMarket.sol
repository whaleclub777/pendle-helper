// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

interface IPendleMarket is IERC20 {
  function redeemRewards(address user) external returns (uint256[] memory);
  function getRewardTokens() external view returns (address[] memory);
}
