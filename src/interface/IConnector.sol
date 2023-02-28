// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IConnector {
    function depositAll() external;

    function deposit(uint256 amount) external;

    function withdrawAll() external;

    function withdraw(uint256 amount) external;
}
