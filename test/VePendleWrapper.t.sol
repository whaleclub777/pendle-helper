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
import {IPendleMarket} from "../src/interfaces/IPendleMarket.sol";

contract VePendleWrapperTest is Test {
    MockERC20 public pendle;
    MockVotingEscrow public ve;
    MockVotingController public controller;
    MockPendleMarket public market;
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
}
