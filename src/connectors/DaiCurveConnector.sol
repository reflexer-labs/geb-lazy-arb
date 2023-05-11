// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interface/IConnector.sol";
import "../interface/curve/ICurveDeposit_3token.sol";

contract DaiCurveConnector is IConnector {
    using SafeERC20 for IERC20;

    ICurveDeposit_3token public pool;
    uint256 private _tokenIndex;

    constructor() {
        underlying = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        pool = ICurveDeposit_3token(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7); // 3pool

        if (pool.coins(0) == underlying) {
            _tokenIndex = 0;
        } else if (pool.coins(1) == underlying) {
            _tokenIndex = 1;
        } else if (pool.coins(2) == underlying) {
            _tokenIndex = 2;
        } else {
            revert("invalid pool");
        }

        lpToken = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; // 3Crv
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

    function withdraw(uint256 underlyingAmount) external override {
        uint256 amount = pool.calc_withdraw_one_coin(
            1 ether,
            int128(uint128(_tokenIndex))
        );
        _withdraw((1 ether * underlyingAmount) / amount);
    }

    function redeem(uint256 lpTokenAmount) external override {
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
        pool.remove_liquidity_one_coin(
            lpTokenAmount,
            int128(uint128(_tokenIndex)),
            0
        );
        IERC20(underlying).safeTransfer(
            msg.sender,
            IERC20(underlying).balanceOf(address(this))
        );
    }
}
