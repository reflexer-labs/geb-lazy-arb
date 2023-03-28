// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "forge-std/console.sol";

contract MockOracle {
    uint256 public redemptionRate;

    function redemptionPrice() external view returns (uint256) {
        return redemptionRate;
    }

    function setRedemptionRate(uint256 _redemptionRate) external {
        redemptionRate = _redemptionRate;
    }
}
