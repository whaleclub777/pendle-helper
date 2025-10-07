// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IPVotingController as _IPVotingController} from "pendle/interfaces/IPVotingController.sol";

/// @notice Local minimal interface to call `vote` on the VotingController
interface IPVotingController is _IPVotingController {
    function vote(address[] calldata pools, uint64[] calldata weights) external;
}
