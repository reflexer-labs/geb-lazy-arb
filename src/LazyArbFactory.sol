// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

interface ILazyArb {
    function transferOwnership(address owner_) external;
}

/// @notice LazyArb Factory
contract LazyArbFactory {
    address public immutable beacon;
    address public immutable safeManager;
    address public immutable taxCollector;
    address public immutable ethJoin;
    address public immutable coinJoin;
    address public immutable daiManager;
    address public immutable daiJug;
    address public immutable daiEthJoin;
    address public immutable daiDaiJoin;
    address public immutable oracleRelayer;
    address public immutable daiConnector;
    address public immutable raiConnector;

    constructor(
        address beacon_,
        address safeManager_,
        address taxCollector_,
        address ethJoin_,
        address coinJoin_,
        address daiManager_,
        address daiJug_,
        address daiEthJoin_,
        address daiDaiJoin_,
        address oracleRelayer_,
        address daiConnector_,
        address raiConnector_
    ) {
        require(beacon_ != address(0), "LazyArbFactory/null-beacon");
        require(safeManager_ != address(0), "LazyArbFactory/null-safe-manager");
        require(
            taxCollector_ != address(0),
            "LazyArbFactory/null-tax-collector"
        );
        require(ethJoin_ != address(0), "LazyArbFactory/null-eth-join");
        require(coinJoin_ != address(0), "LazyArbFactory/null-coin-join");
        require(daiManager_ != address(0), "LazyArbFactory/null-dai-manager");
        require(daiJug_ != address(0), "LazyArbFactory/null-dai-jug");
        require(daiEthJoin_ != address(0), "LazyArbFactory/null-dai-eth-join");
        require(daiDaiJoin_ != address(0), "LazyArbFactory/null-dai-dai-join");
        require(
            oracleRelayer_ != address(0),
            "LazyArbFactory/null-oracle-relayer"
        );
        require(
            daiConnector_ != address(0),
            "LazyArbFactory/null-dai-connector"
        );
        require(
            raiConnector_ != address(0),
            "LazyArbFactory/null-rai-connector"
        );

        beacon = beacon_;
        safeManager = safeManager_;
        taxCollector = taxCollector_;
        ethJoin = ethJoin_;
        coinJoin = coinJoin_;
        daiManager = daiManager_;
        daiJug = daiJug_;
        daiEthJoin = daiEthJoin_;
        daiDaiJoin = daiDaiJoin_;
        oracleRelayer = oracleRelayer_;
        daiConnector = daiConnector_;
        raiConnector = raiConnector_;
    }

    /// @notice Deploy new LazyArb instance
    /// @param minCRatio_ Minimum cRatio value
    /// @param maxCRatio_ Maximum cRatio value
    function createLazyArb(
        uint256 minCRatio_,
        uint256 maxCRatio_
    ) external returns (address lazyArb) {
        address[2] memory connectors;
        connectors[0] = daiConnector;
        connectors[1] = raiConnector;
        lazyArb = address(
            new BeaconProxy(
                beacon,
                abi.encodeWithSignature(
                    "initialize(uint256,uint256,address,address,address,address,address,address,address,address,address,address[2])",
                    minCRatio_,
                    maxCRatio_,
                    safeManager,
                    taxCollector,
                    ethJoin,
                    coinJoin,
                    daiManager,
                    daiJug,
                    daiEthJoin,
                    daiDaiJoin,
                    oracleRelayer,
                    connectors
                )
            )
        );

        ILazyArb(lazyArb).transferOwnership(msg.sender);
    }
}
