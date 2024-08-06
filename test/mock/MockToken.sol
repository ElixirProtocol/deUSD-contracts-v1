// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin/token/ERC20/extensions/ERC20Permit.sol";

contract MockToken is ERC20, ERC20Permit {
    uint8 private __decimals;

    constructor(string memory name, string memory symbol, uint8 _decimals, address owner)
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        __decimals = _decimals;
        require(owner != address(0), "Zero address not valid");

        _mint(owner, 100000000 * (10 ** _decimals));
    }

    function decimals() public view override returns (uint8) {
        return __decimals;
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function mint(uint256 amount, address receiver) external {
        _mint(receiver, amount);
    }

    // Exclude from coverage report
    function test() public {}
}
