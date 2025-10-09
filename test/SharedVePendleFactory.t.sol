// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {SharedVePendleFactory} from "../src/SharedVePendleFactory.sol";
import {SharedVePendle} from "../src/SharedVePendle.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockVotingEscrow} from "./mocks/MockVotingEscrow.sol";
import {MockVotingController} from "./mocks/MockVotingController.sol";
import {IPVotingEscrow} from "../src/interfaces/IPVotingEscrow.sol";
import {IPVotingController} from "../src/interfaces/IPVotingController.sol";

contract SharedVePendleFactoryTest is Test {
  function test_createSharedVePendle_recordsInstanceAndTransfersOwnership() public {
    // set up mocks required for constructor
    MockERC20 pendle = new MockERC20("Pendle", "PENDLE");
    MockVotingEscrow ve = new MockVotingEscrow(address(pendle));
    MockVotingController controller = new MockVotingController();

    SharedVePendleFactory factory =
      new SharedVePendleFactory(pendle, IPVotingEscrow(address(ve)), IPVotingController(address(controller)));

    // create SharedVePendle via factory; caller (this test) should become owner
    address instance = factory.createSharedVePendle(500);

    // basic sanity
    assertTrue(instance != address(0));

    // instance should be recorded
    assertEq(factory.count(), 1);
    assertEq(factory.instances(0), instance);
    assertTrue(factory.isInstance(instance));

    // ownership should have been transferred to the caller (this contract)
    SharedVePendle wrapper = SharedVePendle(instance);
    assertEq(wrapper.owner(), address(this));
  }
}
