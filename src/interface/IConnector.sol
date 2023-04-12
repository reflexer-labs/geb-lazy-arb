// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

abstract contract IConnector {
    address public underlying;
    address public lpToken;

    function deposit(uint256 amount) external virtual;

    function withdraw(uint256 underlyingAmount) external virtual;

    function redeem(uint256 lpTokenAmount) external virtual;

    function withdrawAll() external virtual;
}
