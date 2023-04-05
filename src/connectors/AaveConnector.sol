// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interface/IConnector.sol";
import "../interface/aave/ILendingPool.sol";

contract AaveConnector is IConnector {
    using SafeERC20 for IERC20;

    ILendingPool public pool;

    constructor(address _underlying, address _pool) {
        underlying = _underlying;
        pool = ILendingPool(_pool);
        lpToken = pool.getReserveData(_underlying).aTokenAddress;
    }

    function deposit(uint256 amount) external override {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(underlying).safeApprove(address(pool), 0);
        IERC20(underlying).safeApprove(address(pool), amount);

        pool.deposit(underlying, amount, msg.sender, 0);
    }

    function withdraw(uint256 lpTokenAmount) external override {
        _withdraw(lpTokenAmount);
    }

    function withdrawAll() external override {
        _withdraw(IERC20(lpToken).balanceOf(msg.sender));
    }

    function _withdraw(uint256 lpTokenAmount) internal {
        IERC20(lpToken).safeTransferFrom(
            msg.sender,
            address(this),
            lpTokenAmount
        );
        pool.withdraw(underlying, type(uint256).max, msg.sender);
        IERC20(underlying).safeTransfer(
            msg.sender,
            IERC20(underlying).balanceOf(address(this))
        );
    }
}
