// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

contract MockVotingController {
    event Voted(address[] pools, uint64[] weights);
    event BroadcastResults(uint64 chainId, uint256 value);

    function vote(address[] calldata pools, uint64[] calldata weights) external {
        emit Voted(pools, weights);
    }

    function broadcastResults(uint64 chainId) external payable {
        emit BroadcastResults(chainId, msg.value);
    }
}
