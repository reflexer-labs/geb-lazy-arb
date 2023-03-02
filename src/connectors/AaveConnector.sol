// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IConnector.sol";
import "../interface/aave/ILendingPool.sol";

contract AaveConnector is IConnector {
    address public underlying;
    address public aToken;
    ILendingPool public pool;

    constructor(address _underlying, address _pool) {
        underlying = _underlying;
        pool = ILendingPool(_pool);
        aToken = pool.getReserveData(_underlying).aTokenAddress;
    }

    function depositAll() external {
        _deposit(IERC20(underlying).balanceOf(address(this)));
    }

    function deposit(uint256 amount) external {
        _deposit(amount);
    }

    function withdrawAll() external {
        _withdraw(IERC20(aToken).balanceOf(address(this)));
    }

    function withdraw(uint256 amount) external {
        _withdraw(amount);
    }

    function _deposit(uint256 amount) internal {
        pool.deposit(underlying, amount, address(this), 0);
    }

    function _withdraw(uint256 amount) internal {
        pool.withdraw(underlying, amount, address(this));
    }
}
