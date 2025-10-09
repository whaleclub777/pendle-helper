// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./SharedVePendle.sol";

/**
 * @notice Minimal factory for SharedVePendle.
 *
 * Deploys a new SharedVePendle and transfers ownership of the deployed
 * instance to the caller. This is necessary because SharedVePendle's
 * constructor sets the owner to the contract that deployed it (via
 * Ownable(msg.sender)). The factory therefore becomes owner at
 * construction time and immediately transfers ownership to the user.
 */
contract SharedVePendleFactory {
  event Deployed(address indexed deployer, address indexed instance);

  // List of deployed SharedVePendle instances
  address[] public instances;
  // Fast lookup to check if an address was deployed by this factory
  mapping(address => bool) public isInstance;

  /// @notice Deploys SharedVePendle and transfers ownership to msg.sender
  function createSharedVePendle(
    IERC20 _pendle,
    IPVotingEscrow _ve,
    IPVotingController _votingController,
    uint256 _feeRateBps
  ) external returns (address instance) {
    SharedVePendle s = new SharedVePendle(_pendle, _ve, _votingController, _feeRateBps);
    // s.owner() is the factory (this contract). Transfer ownership to caller.
    s.transferOwnership(msg.sender);
    instance = address(s);
    // record instance
    instances.push(instance);
    isInstance[instance] = true;
    emit Deployed(msg.sender, instance);
  }

  /// @notice Number of SharedVePendle instances deployed by this factory
  function count() external view returns (uint256) {
    return instances.length;
  }
}
