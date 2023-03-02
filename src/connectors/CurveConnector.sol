// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IConnector.sol";
import "../interface/curve/ICurveDeposit_2token.sol";

contract CurveConnector is IConnector {
    address public underlying;
    ICurveDeposit_2token public pool;
    uint256 private _tokenIndex;

    constructor(address _underlying, address _pool) {
        underlying = _underlying;
        pool = ICurveDeposit_2token(_pool);

        if (pool.coins(0) == _underlying) {
            _tokenIndex = 0;
        } else if (pool.coins(1) == _underlying) {
            _tokenIndex = 1;
        } else {
            revert("invalid pool");
        }
    }

    function depositAll() external {
        _deposit(IERC20(underlying).balanceOf(address(this)));
    }

    function deposit(uint256 amount) external {
        _deposit(amount);
    }

    function withdrawAll() external {
        uint256 lpBalance = IERC20(pool.lp_token()).balanceOf(address(this));
        pool.remove_liquidity_one_coin(
            lpBalance,
            int128(uint128(_tokenIndex)),
            0
        );
    }

    function withdraw(uint256 amount) external {
        uint256 lpBalance = IERC20(pool.lp_token()).balanceOf(address(this));
        uint256[2] memory amounts;
        amounts[_tokenIndex] = amount;
        pool.remove_liquidity_imbalance(amounts, lpBalance);
    }

    function _deposit(uint256 amount) internal {
        uint256[2] memory amounts;
        amounts[_tokenIndex] = amount;
        pool.add_liquidity(amounts, 0);
    }
}
