// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../interface/IConnector.sol";
import "../interface/curve/ICurveDeposit_2token.sol";

contract CurveConnector is IConnector {
    address public depositToken;
    address public pool;

    constructor(address _depositToken, address _pool) {
        depositToken = _depositToken;
        pool = _pool;
    }

    function depositAll() external {}

    function deposit(uint256 amount) external {}

    function withdrawAll() external {}

    function withdraw(uint256 amount) external {}
}
