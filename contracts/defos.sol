// SPDX-License-Identifier: DeFOS

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

// import "github.com/OpenZeppelin/zeppelin-solidity/contracts/token/ERC20/ERC20Burnable.sol";

/**
 * @author  DeFOS.Team
 *
 * @dev     Contract for DeFOS token with burn support
 */

// DeFOS Erc20 Token Contract.
contract DeFOS is ERC20Burnable {
    // init supply for defos erc20 token is 91,600,000
    uint256 private constant initSupply = 91600000 * 1e18;

    constructor() public ERC20("Decentralized Financial Operating System", "DeFOS") {
        _mint(msg.sender, initSupply);
    }
}

