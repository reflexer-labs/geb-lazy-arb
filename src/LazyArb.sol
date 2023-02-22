pragma solidity 0.8.17;

import "./interfaces/LazyArbLike.sol";

contract LazyArb is LazyArbLike {
    function initialize(
        address oracleRelayer_,
        address safeManager_
    ) external initializer {
        require(oracleRelayer_ != address(0), "LazyArb/null-oracle-relayer");
        require(safeManager_ != address(0), "LazyArb/null-safe-manager");

        oracleRelayer = OracleRelayerLike(oracleRelayer_);
        safeManager   = GebSafeManagerLike(safeManager_);

        oracleRelayer.redemptionPrice();
    }

    function redemptionRate() external view returns (uint256) {
        return oracleRelayer.redemptionRate();
    }

    function depositETH() external payable returns (bool success) {
        return true;
    }
}
