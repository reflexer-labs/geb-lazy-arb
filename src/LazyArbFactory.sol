// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

interface ILazyArb {
    function transferOwnership(address owner_) external;
}

contract LazyArbFactory {
    address public immutable beacon;
    address public immutable safeManager;
    address public immutable taxCollector;
    address public immutable ethJoin;
    address public immutable coinJoin;
    address public immutable dai_manager;
    address public immutable dai_jug;
    address public immutable dai_ethJoin;
    address public immutable dai_daiJoin;
    address public immutable oracleRelayer;
    address public immutable connector;

    constructor(
        address beacon_,
        address safeManager_,
        address taxCollector_,
        address ethJoin_,
        address coinJoin_,
        address dai_manager_,
        address dai_jug_,
        address dai_ethJoin_,
        address dai_daiJoin_,
        address oracleRelayer_,
        address connector_
    ) {
        require(beacon_ != address(0), "LazyArbFactory/null-beacon");
        require(safeManager_ != address(0), "LazyArbFactory/null-safe-manager");
        require(
            taxCollector_ != address(0),
            "LazyArbFactory/null-tax-collector"
        );
        require(ethJoin_ != address(0), "LazyArbFactory/null-eth-join");
        require(coinJoin_ != address(0), "LazyArbFactory/null-coin-join");
        require(dai_manager_ != address(0), "LazyArbFactory/null-dai-manager");
        require(dai_jug_ != address(0), "LazyArbFactory/null-dai-jug");
        require(dai_ethJoin_ != address(0), "LazyArbFactory/null-dai-eth-join");
        require(dai_daiJoin_ != address(0), "LazyArbFactory/null-dai-dai-join");
        require(
            oracleRelayer_ != address(0),
            "LazyArbFactory/null-oracle-relayer"
        );
        require(connector_ != address(0), "LazyArbFactory/null-connector");

        beacon = beacon_;
        safeManager = safeManager_;
        taxCollector = taxCollector_;
        ethJoin = ethJoin_;
        coinJoin = coinJoin_;
        dai_manager = dai_manager_;
        dai_jug = dai_jug_;
        dai_ethJoin = dai_ethJoin_;
        dai_daiJoin = dai_daiJoin_;
        oracleRelayer = oracleRelayer_;
        connector = connector_;
    }

    function createLazyArb(
        uint256 minCRatio_,
        uint256 maxCRatio_
    ) external returns (address lazyArb) {
        lazyArb = address(
            new BeaconProxy(
                beacon,
                abi.encodeWithSignature(
                    "initialize(uint256,uint256,address,address,address,address,address,address,address,address,address,address)",
                    minCRatio_,
                    maxCRatio_,
                    safeManager,
                    taxCollector,
                    ethJoin,
                    coinJoin,
                    dai_manager,
                    dai_jug,
                    dai_ethJoin,
                    dai_daiJoin,
                    oracleRelayer,
                    connector
                )
            )
        );

        ILazyArb(lazyArb).transferOwnership(msg.sender);
    }
}
