// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

/// @notice Minimal ERC20-like mock used for tests. Not a full ERC20 implementation,
/// just enough for the wrapper to work: mint, approve, transfer, transferFrom, balanceOf.
contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    /// @notice Mint tokens to an address. For testing only.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
