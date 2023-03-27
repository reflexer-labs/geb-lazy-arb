// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interface/IConnector.sol";
import "../interface/curve/ICurveDeposit_3token.sol";

contract CurveConnector is IConnector {
    using SafeERC20 for IERC20;

    ICurveDeposit_3token public pool;
    uint256 private _tokenIndex;

    constructor(address _underlying, address _pool, address _lpToken) {
        underlying = _underlying;
        pool = ICurveDeposit_3token(_pool);

        if (pool.coins(0) == _underlying) {
            _tokenIndex = 0;
        } else if (pool.coins(1) == _underlying) {
            _tokenIndex = 1;
        } else if (pool.coins(2) == _underlying) {
            _tokenIndex = 2;
        } else {
            revert("invalid pool");
        }

        lpToken = _lpToken;
    }

    function deposit(uint256 amount) external override {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(underlying).safeApprove(address(pool), 0);
        IERC20(underlying).safeApprove(address(pool), amount);

        uint256[3] memory amounts;
        amounts[_tokenIndex] = amount;
        pool.add_liquidity(amounts, 0);

        IERC20(lpToken).safeTransfer(
            msg.sender,
            IERC20(lpToken).balanceOf(address(this))
        );
    }

    function withdraw(uint256 lpTokenAmount) external override {
        IERC20(lpToken).safeTransferFrom(
            msg.sender,
            address(this),
            lpTokenAmount
        );
        pool.remove_liquidity_one_coin(
            lpTokenAmount,
            int128(uint128(_tokenIndex)),
            0
        );
    }
}
