// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {RewardingMockPendleMarket} from "./mocks/RewardingMockPendleMarket.sol";

contract RewardingMockPendleMarketTest is Test {
    MockERC20 public rewardA;
    MockERC20 public rewardB;
    RewardingMockPendleMarket public market;

    address public user = address(0xBEEF);

    function setUp() public {
        rewardA = new MockERC20("RewardA", "RWA");
        rewardB = new MockERC20("RewardB", "RWB");

        address[] memory rts = new address[](2);
        rts[0] = address(rewardA);
        rts[1] = address(rewardB);

        market = new RewardingMockPendleMarket(rts);
    }

    function test_timeBasedAccrual_and_redeem() public {
        // set emission rates: 1 ether/sec for A, 2 ether/sec for B
        uint256[] memory rates = new uint256[](2);
        rates[0] = 1 ether;
        rates[1] = 2 ether;
        market.setEmissionRates(rates);

        // fund the market so it can actually pay out
        rewardA.mint(address(market), 10 ether);
        rewardB.mint(address(market), 10 ether);

        // warp forward 5 seconds
        vm.warp(block.timestamp + 5);

        // redeem rewards to user
        vm.prank(address(this));
        uint256[] memory out = market.redeemRewards(user);

        // expected: A = 5 ether, B = 10 ether
        assertEq(out.length, 2);
        assertEq(out[0], 5 ether);
        assertEq(out[1], 10 ether);

        // user balance should reflect transfers
        assertEq(rewardA.balanceOf(user), 5 ether);
        assertEq(rewardB.balanceOf(user), 10 ether);
    }

    function test_oneTimeEmission_respects_balance() public {
        // fund only reward tokens in the market
        rewardA.mint(address(market), 3 ether);
        rewardB.mint(address(market), 1 ether);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5 ether; // schedule more than balance
        amounts[1] = 1 ether; // schedule equal to balance

        // schedule emission (credits unclaimedAccrued)
        uint256[] memory scheduled = market.oneTimeEmission(amounts);
        assertEq(scheduled[0], 5 ether);
        assertEq(scheduled[1], 1 ether);

        // now redeem: redeemRewards will transfer min(accrued, balance)
        uint256[] memory out = market.redeemRewards(user);
        // redeemRewards mints any shortfall, so full scheduled amounts are paid
        assertEq(out[0], 5 ether);
        assertEq(out[1], 1 ether);

        assertEq(rewardA.balanceOf(user), 5 ether);
        assertEq(rewardB.balanceOf(user), 1 ether);
    }
}
