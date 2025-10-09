// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {SharedVePendle} from "../src/SharedVePendle.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IPVotingEscrow} from "../src/interfaces/IPVotingEscrow.sol";
import {IPVotingController} from "../src/interfaces/IPVotingController.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockVotingEscrow} from "../test/mocks/MockVotingEscrow.sol";
import {MockVotingController} from "../test/mocks/MockVotingController.sol";

/// @notice Simple deploy script for local/testing: deploys Mock PENDLE, Mock VE, Mock VotingController
/// and then deploys SharedVePendle using those mocks. Intended to be run against a local anvil node
/// or with `--fork-url` when required.
contract DeploySharedVePendle is Script {
  function run() external returns (SharedVePendle svp, MockERC20 pendle, MockVotingEscrow ve, MockVotingController vc) {
    // Start broadcasting transactions (use `forge script ... --broadcast` to execute on a real RPC)
    vm.startBroadcast();

    // Deploy test/mock contracts
    pendle = new MockERC20("PENDLE", "PENDLE");
    ve = new MockVotingEscrow(address(pendle));
    vc = new MockVotingController();

    // Fee 5% as an example (500 bps)
    uint256 feeBps = 500;

    // Deploy the SharedVePendle wrapper
    svp = new SharedVePendle(IERC20(address(pendle)), IPVotingEscrow(address(ve)), IPVotingController(address(vc)), feeBps);

    // Done
    vm.stopBroadcast();
  }
}
