// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IPVotingEscrowMainchain as _IPVotingEscrowMainchain} from "pendle/interfaces/IPVotingEscrowMainchain.sol";

/// @notice Minimal local interface for the ve contract's cross-chain broadcast helper.
/// Exposes the payable broadcastUserPosition function.
interface IPVotingEscrow is _IPVotingEscrowMainchain {
    function broadcastUserPosition(address user, uint256[] calldata chainIds) external payable;
}
