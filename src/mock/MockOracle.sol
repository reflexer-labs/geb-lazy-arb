// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "forge-std/console.sol";

interface IOracleRelayer {
    function redemptionPrice() external returns (uint256);

    function collateralTypes(
        bytes32
    ) external view returns (address, uint256, uint256);
}

contract MockOracle {
    uint256 public redemptionRate;
    IOracleRelayer public oracleRelayer;

    constructor(address _oracleRelayer) {
        oracleRelayer = IOracleRelayer(_oracleRelayer);
    }

    function redemptionPrice() external returns (uint256) {
        return oracleRelayer.redemptionPrice();
    }

    function setRedemptionRate(uint256 _redemptionRate) external {
        redemptionRate = _redemptionRate;
    }

    function collateralTypes(
        bytes32 collateralType
    ) public view virtual returns (address, uint256, uint256) {
        return oracleRelayer.collateralTypes(collateralType);
    }
}
