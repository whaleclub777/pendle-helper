// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {VePendleWrapper} from "../src/VePendleWrapper.sol";
import {IPVotingEscrow} from "../src/interfaces/IPVotingEscrow.sol";
import {IPVotingController} from "../src/interfaces/IPVotingController.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockVotingEscrow} from "./mocks/MockVotingEscrow.sol";
import {MockVotingController} from "./mocks/MockVotingController.sol";
import {MockPendleMarket} from "./mocks/MockPendleMarket.sol";
import {RewardingMockPendleMarket} from "./mocks/RewardingMockPendleMarket.sol";
import {IPendleMarket} from "../src/interfaces/IPendleMarket.sol";

contract VePendleWrapperTest is Test {
    MockERC20 public pendle;
    MockVotingEscrow public ve;
    MockVotingController public controller;
    MockPendleMarket public market;
    RewardingMockPendleMarket public rewardingMarket;
    VePendleWrapper public wrapper;

    address public depositor = address(0xBEEF);

    function setUp() public {
        pendle = new MockERC20("Pendle", "PENDLE");
        ve = new MockVotingEscrow(address(pendle));
        controller = new MockVotingController();

        wrapper = new VePendleWrapper(pendle, IPVotingEscrow(address(ve)), IPVotingController(address(controller)));

        // mint some PENDLE to depositor
        pendle.mint(depositor, 1_000 ether);

        // depositor approves wrapper
        vm.prank(depositor);
        pendle.approve(address(wrapper), type(uint256).max);

        // setup markets
        market = new MockPendleMarket();
        rewardingMarket = new RewardingMockPendleMarket();
    }

    function test_depositAndLock_increasesVeBalance() public {
        uint128 amount = 100 ether;
        uint128 newExpiry = uint128(block.timestamp + 1 days);

        vm.prank(depositor);
        uint128 newVeBalance = wrapper.depositAndLock(amount, newExpiry);

        // wrapper should now have ve balance equal to amount in mock
        assertEq(newVeBalance, amount);
        // and the ve contract recorded the locked amount
        assertEq(ve.lockedAmount(), amount);
        assertEq(ve.lockedExpiry(), newExpiry);
    }

    function test_withdrawExpiredTo_ownerCanWithdrawAfterExpiry() public {
        uint128 amount = 50 ether;
        uint128 newExpiry = uint128(block.timestamp + 1 days);

        // deposit
        vm.prank(depositor);
        wrapper.depositAndLock(amount, newExpiry);

        // cannot withdraw before expiry
        vm.expectRevert();
        wrapper.withdrawExpiredTo(address(this));

        // forward time past expiry
        vm.warp(block.timestamp + 2 days);

        // owner withdraws expired to owner address
        uint128 withdrawn = wrapper.withdrawExpiredTo(address(this));

        assertEq(withdrawn, amount);
        // owner should receive pendle (owner is set to deployer in Ownable(msg.sender) constructor)
        // wrapper contract's owner is the test contract's address? In constructor Ownable(msg.sender) used, so owner == address(this)
        // ensure the test contract has the pendle balance
        assertEq(pendle.balanceOf(address(this)), amount);
    }

    function test_owner_vote_and_broadcast_calls() public {
        // only owner can call; owner is address(this) because VePendleWrapper called Ownable(msg.sender) in constructor
        address[] memory pools = new address[](1);
        pools[0] = address(0x1234);
        uint64[] memory weights = new uint64[](1);
        weights[0] = 100;

        // should not revert
        wrapper.ownerVote(pools, weights);
        wrapper.broadcastResults(1);
        wrapper.broadcastPosition(new uint256[](0));
    }

    // ----------------- Multi-Market / Rewards Tests -----------------

    function _addRewardingMarket(address rewardToken, uint256 perHarvest) internal {
        // configure rewarding market
        rewardingMarket.addRewardToken(rewardToken, perHarvest);
        // owner adds market to wrapper
        wrapper.addMarket(IPendleMarket(address(rewardingMarket)));
    }

    function test_addMarket_snapshotsRewardTokens() public {
        MockERC20 reward = new MockERC20("Reward", "RWD");
        rewardingMarket.addRewardToken(address(reward), 0);
        wrapper.addMarket(IPendleMarket(address(rewardingMarket)));
        address[] memory rts = wrapper.getRewardTokens(address(rewardingMarket));
        assertEq(rts.length, 1);
        assertEq(rts[0], address(reward));
    }

    function test_depositLp_and_withdraw_flow() public {
        // Set reward token and add market
        MockERC20 reward = new MockERC20("Reward", "RWD");
        _addRewardingMarket(address(reward), 0);

        // Mint LP to depositor and approve
        rewardingMarket.mint(depositor, 500 ether);
        vm.prank(depositor);
        rewardingMarket.approve(address(wrapper), type(uint256).max);

        // deposit
        vm.prank(depositor);
        wrapper.depositLp(address(rewardingMarket), 100 ether);
        assertEq(wrapper.lpBalanceOf(address(rewardingMarket), depositor), 100 ether);
        assertEq(wrapper.totalLpOf(address(rewardingMarket)), 100 ether);

        // withdraw part
        vm.prank(depositor);
        wrapper.withdrawLp(address(rewardingMarket), 40 ether);
        assertEq(wrapper.lpBalanceOf(address(rewardingMarket), depositor), 60 ether);
        assertEq(wrapper.totalLpOf(address(rewardingMarket)), 60 ether);
    }

    function test_rewards_accrual_and_claim_single_user() public {
        MockERC20 reward = new MockERC20("Reward", "RWD");
        // fund reward token to market contract so it can transfer out on redeem
        reward.mint(address(rewardingMarket), 1_000 ether);
        _addRewardingMarket(address(reward), 10 ether); // 10 ether each harvest

        // Mint LP & approve
        rewardingMarket.mint(depositor, 100 ether);
        vm.prank(depositor);
        rewardingMarket.approve(address(wrapper), type(uint256).max);

        // deposit triggers first harvest and sets debt (user receives rewards immediately via _settleUser?)
        vm.prank(depositor);
        wrapper.depositLp(address(rewardingMarket), 100 ether);
        // On initial deposit, rewards harvested before LP transfer accrue with totalLp==0 so become unallocated, then user deposits and reward debt set. User shouldn't have received tokens yet.
        assertEq(reward.balanceOf(depositor), 0);

        // First claim triggers second harvest and pays out both first (unallocated) + second harvest = 20 ether
        vm.prank(depositor);
        wrapper.claimRewards(address(rewardingMarket));
        assertEq(reward.balanceOf(depositor), 20 ether);

        // Another claim triggers third harvest (10 ether) and pays it out
        vm.prank(depositor);
        wrapper.claimRewards(address(rewardingMarket));
        assertEq(reward.balanceOf(depositor), 30 ether);
    }

    function test_pendingRewards_view() public {
        MockERC20 reward = new MockERC20("Reward", "RWD");
        reward.mint(address(rewardingMarket), 1_000 ether);
        _addRewardingMarket(address(reward), 10 ether);
        rewardingMarket.mint(depositor, 100 ether);
        vm.prank(depositor);
        rewardingMarket.approve(address(wrapper), type(uint256).max);
        vm.prank(depositor);
        wrapper.depositLp(address(rewardingMarket), 100 ether);

        // simulate a harvest to update accRewardPerShare by calling claimRewards once
        vm.prank(depositor);
        wrapper.claimRewards(address(rewardingMarket));
        // Another harvest will happen on pending view if we simulate off-chain? pendingRewards does NOT harvest, so we
        // expect zero pending right after claim
        uint256[] memory pending = wrapper.pendingRewards(address(rewardingMarket), depositor);
        assertEq(pending.length, 1);
        assertEq(pending[0], 0);
    }

    function test_emergencyPullPendle() public {
        // deposit some PENDLE into wrapper without locking (transfer directly)
        pendle.mint(address(wrapper), 123 ether);
        uint256 before = pendle.balanceOf(address(this));
        wrapper.emergencyPullPendle(address(this));
        assertEq(pendle.balanceOf(address(this)), before + 123 ether);
    }

    function test_depositLockAndBroadcast() public {
        uint128 amount = 25 ether;
        uint128 newExpiry = uint128(block.timestamp + 3 days);
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = 1;
        chainIds[1] = 137;

        vm.prank(depositor);
        wrapper.depositLockAndBroadcast{value: 0}(amount, newExpiry, chainIds);
        assertEq(ve.lockedAmount(), amount);
    }
}
