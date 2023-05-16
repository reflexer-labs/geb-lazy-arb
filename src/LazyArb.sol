// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import "./interface/IConnector.sol";

abstract contract CollateralLike {
    function approve(address, uint256) public virtual;

    function transfer(address, uint256) public virtual;

    function transferFrom(address, address, uint256) public virtual;

    function deposit() public payable virtual;

    function withdraw(uint256) public virtual;
}

abstract contract ManagerLike {
    function safeCan(
        address,
        uint256,
        address
    ) public view virtual returns (uint256);

    function collateralTypes(uint256) public view virtual returns (bytes32);

    function ownsSAFE(uint256) public view virtual returns (address);

    function safes(uint256) public view virtual returns (address);

    function safeEngine() public view virtual returns (address);

    function openSAFE(bytes32, address) public virtual returns (uint256);

    function transferSAFEOwnership(uint256, address) public virtual;

    function allowSAFE(uint256, address, uint256) public virtual;

    function allowHandler(address, uint256) public virtual;

    function modifySAFECollateralization(uint256, int, int) public virtual;

    function transferCollateral(uint256, address, uint256) public virtual;

    function transferInternalCoins(uint256, address, uint256) public virtual;

    function quitSystem(uint256, address) public virtual;

    function enterSystem(address, uint256) public virtual;

    function moveSAFE(uint256, uint256) public virtual;

    function protectSAFE(uint256, address, address) public virtual;
}

abstract contract SAFEEngineLike {
    function canModifySAFE(
        address,
        address
    ) public view virtual returns (uint256);

    function collateralTypes(
        bytes32
    )
        public
        view
        virtual
        returns (uint256, uint256, uint256, uint256, uint256, uint256);

    function coinBalance(address) public view virtual returns (uint256);

    function safes(
        bytes32,
        address
    ) public view virtual returns (uint256, uint256);

    function modifySAFECollateralization(
        bytes32,
        address,
        address,
        address,
        int,
        int
    ) public virtual;

    function approveSAFEModification(address) public virtual;

    function transferInternalCoins(address, address, uint256) public virtual;
}

abstract contract CollateralJoinLike {
    function decimals() public virtual returns (uint256);

    function collateral() public virtual returns (CollateralLike);

    function join(address, uint256) public payable virtual;

    function exit(address, uint256) public virtual;
}

abstract contract CoinJoinLike {
    function safeEngine() public virtual returns (SAFEEngineLike);

    function join(address, uint256) public payable virtual;

    function exit(address, uint256) public virtual;

    function systemCoin() public virtual returns (SystemCoinLike);
}

abstract contract SystemCoinLike {
    function balanceOf(address) public view virtual returns (uint256);

    function approve(address, uint256) public virtual returns (uint256);

    function transfer(address, uint256) public virtual returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) public virtual returns (bool);
}

abstract contract OracleRelayerLike {
    function collateralTypes(
        bytes32
    ) public view virtual returns (address, uint256, uint256);

    function liquidationCRatio(bytes32) public view virtual returns (uint256);

    function redemptionPrice() public virtual returns (uint256);

    function redemptionRate() public view virtual returns (uint256);
}

abstract contract PriceFeedLike {
    function priceSource() public view virtual returns (address);

    function read() public view virtual returns (uint256);

    function getResultWithValidity()
        external
        view
        virtual
        returns (uint256, bool);
}

abstract contract TaxCollectorLike {
    function taxSingle(bytes32) public virtual returns (uint256);
}

interface GemLike {
    function approve(address, uint256) external;

    function transfer(address, uint256) external;

    function transferFrom(address, address, uint256) external;

    function deposit() external payable;

    function withdraw(uint256) external;
}

interface DaiManagerLike {
    function cdpCan(address, uint256, address) external view returns (uint256);

    function ilks(uint256) external view returns (bytes32);

    function owns(uint256) external view returns (address);

    function urns(uint256) external view returns (address);

    function vat() external view returns (address);

    function open(bytes32, address) external returns (uint256);

    function give(uint256, address) external;

    function cdpAllow(uint256, address, uint256) external;

    function urnAllow(address, uint256) external;

    function frob(uint256, int, int) external;

    function flux(uint256, address, uint256) external;

    function move(uint256, address, uint256) external;

    function exit(address, uint256, address, uint256) external;

    function quit(uint256, address) external;

    function enter(address, uint256) external;

    function shift(uint256, uint256) external;
}

interface VatLike {
    function can(address, address) external view returns (uint256);

    function ilks(
        bytes32
    ) external view returns (uint256, uint256, uint256, uint256, uint256);

    function dai(address) external view returns (uint256);

    function urns(bytes32, address) external view returns (uint256, uint256);

    function frob(bytes32, address, address, address, int, int) external;

    function hope(address) external;

    function move(address, address, uint256) external;
}

interface GemJoinLike {
    function dec() external returns (uint256);

    function gem() external returns (GemLike);

    function join(address, uint256) external payable;

    function exit(address, uint256) external;
}

interface DaiJoinLike {
    function vat() external returns (VatLike);

    function dai() external returns (GemLike);

    function join(address, uint256) external payable;

    function exit(address, uint256) external;
}

interface JugLike {
    function drip(bytes32) external returns (uint256);
}

interface IOracle {
    function latestAnswer() external view returns (int256);
}

/// @notice Lazy Arb contract
contract LazyArb is ReentrancyGuardUpgradeable {
    enum Status {
        None,
        Short,
        Long
    }

    address public owner;
    uint256 public minCRatio;
    uint256 public maxCRatio;

    uint256 public constant HUNDRED = 100;
    uint256 public constant WAD = 10 ** 18;
    uint256 private constant RAY = 10 ** 27;
    uint256 public constant MAX_CRATIO = 1000;
    ISwapRouter private constant uniswapV3Router =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IQuoter private constant uniswapV3Quoter =
        IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    IERC20Upgradeable private constant DAI =
        IERC20Upgradeable(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    ManagerLike public safeManager;
    SAFEEngineLike public safeEngine;
    TaxCollectorLike public taxCollector;
    CollateralJoinLike public ethJoin;
    CoinJoinLike public coinJoin;
    SystemCoinLike public systemCoin;
    DaiManagerLike public daiManager;
    JugLike public daiJug;
    GemJoinLike public daiEthJoin;
    DaiJoinLike public daiDaiJoin;
    OracleRelayerLike public oracleRelayer;
    IConnector public daiConnector;
    IConnector public raiConnector;
    mapping(address => address) public oracles;

    uint256 public safe;
    uint256 public cdp;
    Status public status;

    modifier onlyOwner() {
        require(msg.sender == owner, "LazyArb/not-owner");
        _;
    }

    /// @notice Initialize LazyArb contract
    /// @param minCRatio_ uint256
    /// @param maxCRatio_ uint256
    /// @param safeManager_ address
    /// @param taxCollector_ address
    /// @param ethJoin_ address
    /// @param coinJoin_ address
    /// @param daiManager_ address
    /// @param daiJug_ address
    /// @param daiEthJoin_ address
    /// @param daiDaiJoin_ address
    /// @param oracleRelayer_ address
    /// @param connectors_ address
    function initialize(
        uint256 minCRatio_,
        uint256 maxCRatio_,
        address safeManager_,
        address taxCollector_,
        address ethJoin_,
        address coinJoin_,
        address daiManager_,
        address daiJug_,
        address daiEthJoin_,
        address daiDaiJoin_,
        address oracleRelayer_,
        address[2] memory connectors_
    ) external initializer {
        require(
            minCRatio_ < maxCRatio_ && maxCRatio_ < MAX_CRATIO,
            "LazyArb/invalid-cRatio"
        );
        require(safeManager_ != address(0), "LazyArb/null-safe-manager");
        require(taxCollector_ != address(0), "LazyArb/null-tax-collector");
        require(ethJoin_ != address(0), "LazyArb/null-eth-join");
        require(coinJoin_ != address(0), "LazyArb/null-coin-join");
        require(daiManager_ != address(0), "LazyArb/null-dai-manager");
        require(daiJug_ != address(0), "LazyArb/null-dai-jug");
        require(daiEthJoin_ != address(0), "LazyArb/null-dai-eth-join");
        require(daiDaiJoin_ != address(0), "LazyArb/null-dai-dai-join");
        require(oracleRelayer_ != address(0), "LazyArb/null-oracle-relayer");
        require(
            connectors_[0] != address(0) && connectors_[1] != address(0),
            "LazyArb/null-connector"
        );

        owner = msg.sender;
        minCRatio = minCRatio_;
        maxCRatio = maxCRatio_;

        safeManager = ManagerLike(safeManager_);
        taxCollector = TaxCollectorLike(taxCollector_);
        ethJoin = CollateralJoinLike(ethJoin_);
        coinJoin = CoinJoinLike(coinJoin_);
        oracleRelayer = OracleRelayerLike(oracleRelayer_);
        daiConnector = IConnector(connectors_[0]);
        raiConnector = IConnector(connectors_[1]);

        safeEngine = SAFEEngineLike(safeManager.safeEngine());
        systemCoin = coinJoin.systemCoin();

        safe = safeManager.openSAFE("ETH-A", address(this));
        safeManager.allowSAFE(safe, msg.sender, 1);

        daiManager = DaiManagerLike(daiManager_);
        daiJug = JugLike(daiJug_);
        daiEthJoin = GemJoinLike(daiEthJoin_);
        daiDaiJoin = DaiJoinLike(daiDaiJoin_);

        cdp = daiManager.open("ETH-A", address(this));

        oracleRelayer.redemptionPrice();

        address WETH = address(ethJoin.collateral());
        oracles[WETH] = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        oracles[address(DAI)] = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
        oracles[
            address(systemCoin)
        ] = 0x483d36F6a1d063d580c7a24F9A42B346f3a69fbb;
    }

    /// @notice Transfer ownership to new owner
    /// @param owner_ New owner address
    function transferOwnership(address owner_) external onlyOwner {
        require(owner_ != address(0), "LazyArb/null-owner");
        owner = owner_;
    }

    /// @notice Sets daiConnector, raiConnector addresses
    /// @param connectors_ New connectors address
    function setConnectors(address[2] memory connectors_) external onlyOwner {
        require(
            connectors_[0] != address(0) && connectors_[1] != address(0),
            "LazyArb/null-connector"
        );
        daiConnector = IConnector(connectors_[0]);
        raiConnector = IConnector(connectors_[1]);
    }

    /// @notice Sets minCRatio, maxCRatio value
    /// @param minCRatio_ New minCRatio value
    /// @param maxCRatio_ New maxCRatio value
    function setCRatio(
        uint256 minCRatio_,
        uint256 maxCRatio_
    ) external onlyOwner {
        require(
            minCRatio_ < maxCRatio_ && maxCRatio_ < MAX_CRATIO,
            "LazyArb/invalid-cRatio"
        );
        minCRatio = minCRatio_;
        maxCRatio = maxCRatio_;
    }

    /// @notice Returns current redemption rate
    function redemptionRate() external view returns (uint256) {
        return oracleRelayer.redemptionRate();
    }

    /// @notice Deposit ETH and generate RAI debt at target cRatio
    function lockETHAndGenerateDebt() external onlyOwner {
        _lockETHAndGenerateDebt();
    }

    /// @notice Modify DAI debt to keep cRatio within target cRatio range
    function rebalanceShort() public {
        require(status == Status.Short, "LazyArb/status-not-short");

        address safeHandler = safeManager.safes(safe);
        bytes32 collateralType = safeManager.collateralTypes(safe);

        uint256 targetDebtAmount;
        uint256 currentDebtAmount;

        {
            uint256 priceFeedValue = _getEthPrice();

            (uint256 depositedCollateralToken, ) = safeEngine.safes(
                collateralType,
                safeHandler
            );
            uint256 totalCollateral = (depositedCollateralToken *
                priceFeedValue) / WAD;

            currentDebtAmount = _getRepaidAllDebt(
                address(this),
                safeHandler,
                collateralType
            );
            uint256 currentCRatio = (((currentDebtAmount *
                oracleRelayer.redemptionPrice()) / RAY) * MAX_CRATIO) /
                totalCollateral;
            require(
                currentCRatio < minCRatio || currentCRatio > maxCRatio,
                "LazyArb/cRatio-in-range"
            );

            uint256 targetCRatio = (minCRatio + maxCRatio) / 2;
            targetDebtAmount =
                (((targetCRatio * totalCollateral) / MAX_CRATIO) * RAY) /
                oracleRelayer.redemptionPrice();
        }

        if (targetDebtAmount > currentDebtAmount) {
            uint256 deltaWad = targetDebtAmount - currentDebtAmount;
            // Generates debt
            modifySAFECollateralization(
                0,
                _getGeneratedDeltaDebt(safeHandler, collateralType, deltaWad)
            );

            exitRaiAndConvertToDai(deltaWad);
            depositDai();
        } else {
            uint256 deltaWad = currentDebtAmount - targetDebtAmount;
            uint256 raiPrice = _getTokenPrice(address(systemCoin));
            uint256 daiPrice = _getTokenPrice(address(DAI));
            uint256 requiredDAIAmount = (deltaWad * raiPrice) / daiPrice;
            requiredDAIAmount = (requiredDAIAmount * 1012) / 1000; // add 1.2% slippage

            IERC20Upgradeable lpToken = IERC20Upgradeable(
                daiConnector.lpToken()
            );
            uint256 lpTokenBalance = lpToken.balanceOf(address(this));
            lpToken.approve(address(daiConnector), lpTokenBalance);
            daiConnector.withdraw(requiredDAIAmount);

            uniswapSwap(
                address(DAI),
                address(systemCoin),
                DAI.balanceOf(address(this)),
                deltaWad
            );

            deltaWad = systemCoin.balanceOf(address(this));
            _coinJoin_join(safeHandler, deltaWad);
            // Paybacks debt to the SAFE and unlocks WETH amount from it
            modifySAFECollateralization(
                0,
                -_getGeneratedDeltaDebt(safeHandler, collateralType, deltaWad)
            );
        }
    }

    /// @notice Repay RAI debt and free ETH
    function repayDebtAndFreeETH() external onlyOwner {
        _repayDebtAndFreeETH();
    }

    /// @notice Deposit ETH and generate DAI debt at target cRatio
    function lockETHAndDraw() external onlyOwner {
        _lockETHAndDraw();
    }

    /// @notice Modify DAI debt to keep cRatio within target cRatio range
    function rebalanceLong() public {
        require(status == Status.Long, "LazyArb/status-not-long");

        address urn = daiManager.urns(cdp);
        address vat = daiManager.vat();
        bytes32 ilk = daiManager.ilks(cdp);
        (uint256 depositedCollateral, ) = VatLike(vat).urns(ilk, urn);

        uint256 targetDebtAmount;
        uint256 currentDebtAmount;

        {
            uint256 priceFeedValue = _getEthPrice();

            uint256 totalCollateral = (depositedCollateral * priceFeedValue) /
                WAD;

            currentDebtAmount = _getWipeAllWad(vat, address(this), urn, ilk);
            {
                uint256 currentCRatio = (currentDebtAmount * MAX_CRATIO) /
                    totalCollateral;
                require(
                    currentCRatio < minCRatio || currentCRatio > maxCRatio,
                    "LazyArb/cRatio-in-range"
                );
            }

            {
                uint256 targetCRatio = (minCRatio + maxCRatio) / 2;
                targetDebtAmount =
                    (targetCRatio * totalCollateral) /
                    MAX_CRATIO;
            }
        }

        if (targetDebtAmount > currentDebtAmount) {
            uint256 wadD = targetDebtAmount - currentDebtAmount;
            // Generates debt
            daiManager.frob(cdp, 0, _getDrawDart(vat, urn, ilk, wadD));

            exitDaiAndConvertToRai(wadD);
            depositRai();
        } else {
            uint256 wadD = currentDebtAmount - targetDebtAmount;
            uint256 requiredRAIAmount;
            {
                uint256 daiPrice = _getTokenPrice(address(DAI));
                uint256 raiPrice = _getTokenPrice(address(systemCoin));
                requiredRAIAmount = (wadD * daiPrice) / raiPrice;
                requiredRAIAmount = (requiredRAIAmount * 1012) / 1000; // add 1.2% slippage
            }

            IERC20Upgradeable lpToken = IERC20Upgradeable(
                raiConnector.lpToken()
            );
            uint256 lpTokenBalance = lpToken.balanceOf(address(this));
            lpToken.approve(address(raiConnector), lpTokenBalance);
            raiConnector.withdraw(requiredRAIAmount);

            uniswapSwap(
                address(systemCoin),
                address(DAI),
                systemCoin.balanceOf(address(this)),
                wadD
            );

            wadD = DAI.balanceOf(address(this));
            _daiJoin_join(urn, wadD);
            // Paybacks debt to the CDP and unlocks WETH amount from it
            daiManager.frob(cdp, 0, -_getDrawDart(vat, urn, ilk, wadD));
        }
    }

    /// @notice Repay DAI debt and free ETH
    function wipeAndFreeETH() external onlyOwner {
        _wipeAndFreeETH();
    }

    /// @notice Flip debt between RAI <-> DAI
    function flip() external {
        if (oracleRelayer.redemptionRate() < RAY) {
            require(status == Status.Long, "LazyArb/status-not-long");

            _wipeAndFreeETH();
            _lockETHAndGenerateDebt();
        } else {
            require(status == Status.Short, "LazyArb/status-not-short");

            _repayDebtAndFreeETH();
            _lockETHAndDraw();
        }
    }

    /// @notice Deposit ETH and generate RAI debt at target cRatio
    function _lockETHAndGenerateDebt() internal {
        require(
            oracleRelayer.redemptionRate() < RAY,
            "LazyArb/redemption-rate-positive"
        );

        require(status != Status.Long, "LazyArb/status-long");
        status = Status.Short;

        address safeHandler = safeManager.safes(safe);

        // Receives ETH amount, converts it to WETH and joins it into the safeEngine
        uint256 collateralBalance = address(this).balance;
        ethJoin_join(safeHandler, collateralBalance);
        // Locks WETH amount into the SAFE
        modifySAFECollateralization(toInt(collateralBalance), 0);

        rebalanceShort();
    }

    /// @notice Repay RAI debt and free ETH
    function _repayDebtAndFreeETH() internal {
        require(status == Status.Short, "LazyArb/status-not-short");
        status = Status.None;

        IERC20Upgradeable lpToken = IERC20Upgradeable(daiConnector.lpToken());
        uint256 lpTokenBalance = lpToken.balanceOf(address(this));
        lpToken.approve(address(daiConnector), lpTokenBalance);
        daiConnector.withdrawAll();

        uint256 daiBalance = DAI.balanceOf(address(this));
        uint256 daiPrice = _getTokenPrice(address(DAI));
        uint256 raiPrice = _getTokenPrice(address(systemCoin));
        uint256 amountMin = (daiBalance * daiPrice) / raiPrice;
        amountMin = (amountMin * 985) / 1000; // add 1.5% slippage
        uniswapSwap(address(DAI), address(systemCoin), daiBalance, amountMin);

        uint256 raiBalance = systemCoin.balanceOf(address(this));

        address safeHandler = safeManager.safes(safe);
        bytes32 collateralType = safeManager.collateralTypes(safe);
        uint256 raiDebtAmount = _getRepaidAllDebt(
            address(this),
            safeHandler,
            collateralType
        );
        if (raiBalance < raiDebtAmount) {
            uint256 missingRaiAmount = raiDebtAmount - raiBalance;
            address WETH = address(ethJoin.collateral());
            uint256 ethPrice = _getTokenPrice(WETH);
            uint256 requiredETHAmount = (missingRaiAmount * raiPrice) /
                ethPrice;
            requiredETHAmount = (requiredETHAmount * 103) / 100; // add 3% slippage

            modifySAFECollateralization(-toInt(requiredETHAmount), 0);
            // Moves the amount from the SAFE handler to proxy's address
            transferCollateral(address(this), requiredETHAmount);
            // Exits WETH amount to proxy address as a token
            ethJoin.exit(address(this), requiredETHAmount);
            // Swap WETH to RAI
            uniswapSwap(
                WETH,
                address(systemCoin),
                requiredETHAmount,
                missingRaiAmount
            );
        }

        (uint256 depositedCollateralToken, uint256 generatedDebt) = safeEngine
            .safes(collateralType, safeHandler);
        // Joins COIN amount into the safeEngine
        _coinJoin_join(safeHandler, raiDebtAmount);
        // Paybacks debt to the SAFE and unlocks WETH amount from it
        modifySAFECollateralization(
            -toInt(depositedCollateralToken),
            -int(generatedDebt)
        );
        // Moves the amount from the SAFE handler to proxy's address
        transferCollateral(address(this), depositedCollateralToken);
        // Exits WETH amount to proxy address as a token
        ethJoin.exit(address(this), depositedCollateralToken);
        // Converts WETH to ETH
        ethJoin.collateral().withdraw(depositedCollateralToken);
    }

    /// @notice Deposit ETH and generate DAI debt at target cRatio
    function _lockETHAndDraw() internal {
        require(
            oracleRelayer.redemptionRate() >= RAY,
            "LazyArb/redemption-rate-positive"
        );

        require(status != Status.Short, "LazyArb/status-short");
        status = Status.Long;

        address urn = daiManager.urns(cdp);
        // address vat = daiManager.vat();
        // bytes32 ilk = daiManager.ilks(cdp);
        // Receives ETH amount, converts it to WETH and joins it into the vat
        uint256 collateralBalance = address(this).balance;
        daiEthJoin_join(urn, collateralBalance);
        // Locks WETH amount into the CDP and generates debt
        daiManager.frob(cdp, toInt(collateralBalance), 0);

        rebalanceLong();
    }

    /// @notice Repay DAI debt and free ETH
    function _wipeAndFreeETH() internal {
        require(status == Status.Long, "LazyArb/status-not-long");
        status = Status.None;

        IERC20Upgradeable lpToken = IERC20Upgradeable(raiConnector.lpToken());
        uint256 lpTokenBalance = lpToken.balanceOf(address(this));
        lpToken.approve(address(raiConnector), lpTokenBalance);
        raiConnector.withdrawAll();

        uint256 raiBalance = systemCoin.balanceOf(address(this));
        uint256 raiPrice = _getTokenPrice(address(systemCoin));
        uint256 daiPrice = _getTokenPrice(address(DAI));
        uint256 amountMin = (raiBalance * raiPrice) / daiPrice;
        amountMin = (amountMin * 985) / 1000; // add 1.5% slippage
        uniswapSwap(address(systemCoin), address(DAI), raiBalance, amountMin);

        uint256 daiBalance = DAI.balanceOf(address(this));

        address vat = daiManager.vat();
        address urn = daiManager.urns(cdp);
        bytes32 ilk = daiManager.ilks(cdp);
        uint256 daiDebtAmount = _getWipeAllWad(vat, address(this), urn, ilk);
        if (daiBalance < daiDebtAmount) {
            uint256 missingDaiAmount = daiDebtAmount - daiBalance;
            address WETH = address(daiEthJoin.gem());
            uint256 ethPrice = _getTokenPrice(WETH);
            uint256 requiredETHAmount = (missingDaiAmount * daiPrice) /
                ethPrice;
            requiredETHAmount = (requiredETHAmount * 101) / 100; // add 1% slippage

            daiManager.frob(cdp, -toInt(requiredETHAmount), 0);
            // Moves the amount from the SAFE handler to proxy's address
            daiManager.flux(cdp, address(this), requiredETHAmount);
            // Exits WETH amount to proxy address as a token
            daiEthJoin.exit(address(this), requiredETHAmount);
            // Swap WETH to DAI
            uniswapSwap(
                WETH,
                address(DAI),
                requiredETHAmount,
                missingDaiAmount
            );
        }

        (uint256 depositedCollateral, uint256 art) = VatLike(vat).urns(
            ilk,
            urn
        );
        // Joins DAI amount into the vat
        _daiJoin_join(urn, daiDebtAmount);
        // Paybacks debt to the CDP and unlocks WETH amount from it
        daiManager.frob(cdp, -toInt(depositedCollateral), -int(art));
        // Moves the amount from the CDP urn to proxy's address
        daiManager.flux(cdp, address(this), depositedCollateral);
        // Exits WETH amount to proxy address as a token
        daiEthJoin.exit(address(this), depositedCollateral);
        // Converts WETH to ETH
        daiEthJoin.gem().withdraw(depositedCollateral);
    }

    /// @notice Exit RAI and swap to DAI
    /// @param deltaWad RAI amount to exit
    function exitRaiAndConvertToDai(uint256 deltaWad) internal {
        // Moves the COIN amount (balance in the safeEngine in rad) to proxy's address
        transferInternalCoins(address(this), toRad(deltaWad));
        // Allows adapter to access to proxy's COIN balance in the safeEngine
        if (safeEngine.canModifySAFE(address(this), address(coinJoin)) == 0) {
            safeEngine.approveSAFEModification(address(coinJoin));
        }
        // Exits COIN as a token
        coinJoin.exit(address(this), deltaWad);

        uint256 systemCoinBalance = systemCoin.balanceOf(address(this));
        uint256 raiPrice = _getTokenPrice(address(systemCoin));
        uint256 daiPrice = _getTokenPrice(address(DAI));
        uint256 amountMin = (systemCoinBalance * raiPrice) / daiPrice;
        amountMin = (amountMin * 985) / 1000; // add 1.5% slippage
        uniswapSwap(
            address(systemCoin),
            address(DAI),
            systemCoinBalance,
            amountMin
        );
    }

    /// @notice Exit DAI and swap to RAI
    /// @param wadD DAI amount to exit
    function exitDaiAndConvertToRai(uint256 wadD) internal {
        address vat = daiManager.vat();

        // Moves the DAI amount (balance in the vat in rad) to proxy's address
        daiManager.move(cdp, address(this), toRad(wadD));
        // Allows adapter to access to proxy's DAI balance in the vat
        if (VatLike(vat).can(address(this), address(daiDaiJoin)) == 0) {
            VatLike(vat).hope(address(daiDaiJoin));
        }
        // Exits DAI to the user's wallet as a token
        daiDaiJoin.exit(address(this), wadD);

        uint256 daiBalance = DAI.balanceOf(address(this));
        uint256 raiPrice = _getTokenPrice(address(systemCoin));
        uint256 daiPrice = _getTokenPrice(address(DAI));
        uint256 amountMin = (daiBalance * daiPrice) / raiPrice;
        amountMin = (amountMin * 985) / 1000; // add 1.5% slippage
        uniswapSwap(address(DAI), address(systemCoin), daiBalance, amountMin);
    }

    /// @notice Deposit DAI into connector
    function depositDai() internal {
        uint256 daiBalance = DAI.balanceOf(address(this));
        DAI.approve(address(daiConnector), daiBalance);

        daiConnector.deposit(daiBalance);
    }

    /// @notice Deposit RAI into connector
    function depositRai() internal {
        uint256 raiBalance = systemCoin.balanceOf(address(this));
        systemCoin.approve(address(raiConnector), raiBalance);

        raiConnector.deposit(raiBalance);
    }

    /// @notice Swap tokenIn to tokenOut through Uniswap v3
    /// @param tokenIn Sell token address
    /// @param tokenOut Buy token address
    /// @param amountIn Sell token amount
    /// @param amountOutMin Minimum buy token amount to get
    function uniswapSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal {
        IERC20Upgradeable(tokenIn).approve(address(uniswapV3Router), amountIn);
        uniswapV3Router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: uint24(500),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /// @notice Joins the system with the a specified value
    /// @param safeHandler address
    /// @param value uint256 - Value to join
    function ethJoin_join(address safeHandler, uint256 value) internal {
        // Wraps ETH in WETH
        ethJoin.collateral().deposit{value: value}();
        // Approves adapter to take the WETH amount
        ethJoin.collateral().approve(address(ethJoin), value);
        // Joins WETH collateral into the safeEngine
        ethJoin.join(safeHandler, value);
    }

    /// @notice Joins the DAI system with the a specified value
    /// @param urn address
    /// @param value uint256 - Value to join
    function daiEthJoin_join(address urn, uint256 value) internal {
        // Wraps ETH in WETH
        daiEthJoin.gem().deposit{value: value}();
        // Approves adapter to take the WETH amount
        daiEthJoin.gem().approve(address(daiEthJoin), value);
        // Joins WETH collateral into the vat
        daiEthJoin.join(urn, value);
    }

    /// @notice Modify a SAFE's collateralization ratio while keeping the generated COIN or collateral freed in the SAFE handler address.
    /// @param deltaCollateral - int
    /// @param deltaDebt - int
    function modifySAFECollateralization(
        int deltaCollateral,
        int deltaDebt
    ) internal {
        safeManager.modifySAFECollateralization(
            safe,
            deltaCollateral,
            deltaDebt
        );
    }

    /// @notice Transfer wad amount of safe collateral from the safe address to a dst address.
    /// @param dst address - destination address
    /// uint256 wad - amount
    function transferCollateral(address dst, uint256 wad) internal {
        safeManager.transferCollateral(safe, dst, wad);
    }

    /// @notice Transfer rad amount of COIN from the safe address to a dst address.
    /// @param dst address - destination address
    /// uint256 rad - amount
    function transferInternalCoins(address dst, uint256 rad) internal {
        safeManager.transferInternalCoins(safe, dst, rad);
    }

    /// @notice Join into the RAI safeEngine
    /// @param safeHandler Safe handler address
    /// @param wad RAI amount
    function _coinJoin_join(address safeHandler, uint256 wad) internal {
        // Approves adapter to take the COIN amount
        coinJoin.systemCoin().approve(address(coinJoin), wad);
        // Joins COIN into the safeEngine
        coinJoin.join(safeHandler, wad);
    }

    /// @notice Join into the DAI safeEngine
    /// @param urn Safe handler address
    /// @param wad DAI amount
    function _daiJoin_join(address urn, uint256 wad) internal {
        // Approves adapter to take the DAI amount
        daiDaiJoin.dai().approve(address(daiDaiJoin), wad);
        // Joins DAI into the vat
        daiDaiJoin.join(urn, wad);
    }

    /// @notice Gets delta debt generated (Total Safe debt minus available safeHandler COIN balance)
    /// @param safeHandler address
    /// @param collateralType bytes32
    /// @return deltaDebt
    function _getGeneratedDeltaDebt(
        address safeHandler,
        bytes32 collateralType,
        uint256 wad
    ) internal returns (int deltaDebt) {
        // Updates stability fee rate
        uint256 rate = taxCollector.taxSingle(collateralType);
        require(rate > 0, "invalid-collateral-type");

        // Gets COIN balance of the handler in the safeEngine
        uint256 coin = safeEngine.coinBalance(safeHandler);

        // If there was already enough COIN in the safeEngine balance, just exits it without adding more debt
        uint256 rad = wad * RAY;
        if (coin < rad) {
            // Calculates the needed deltaDebt so together with the existing coins in the safeEngine is enough to exit wad amount of COIN tokens
            deltaDebt = toInt((rad - coin) / rate);
            // This is neeeded due lack of precision. It might need to sum an extra deltaDebt wei (for the given COIN wad amount)
            deltaDebt = (uint256(deltaDebt) * rate) < rad
                ? deltaDebt + 1
                : deltaDebt;
        }
    }

    /// @notice Gets repaid delta debt generated (rate adjusted debt)
    /// @param coin uint256 amount
    /// @param safeHandler address
    /// @param collateralType bytes32
    /// @return deltaDebt
    function _getRepaidDeltaDebt(
        uint256 coin,
        address safeHandler,
        bytes32 collateralType
    ) internal view returns (int deltaDebt) {
        // Gets actual rate from the safeEngine
        (, uint256 rate, , , , ) = safeEngine.collateralTypes(collateralType);
        require(rate > 0, "invalid-collateral-type");

        // Gets actual generatedDebt value of the safe
        (, uint256 generatedDebt) = safeEngine.safes(
            collateralType,
            safeHandler
        );

        // Uses the whole coin balance in the safeEngine to reduce the debt
        deltaDebt = toInt(coin / rate);
        // Checks the calculated deltaDebt is not higher than safe.generatedDebt (total debt), otherwise uses its value
        deltaDebt = uint256(deltaDebt) <= generatedDebt
            ? -deltaDebt
            : -toInt(generatedDebt);
    }

    /// @notice Gets repaid debt (rate adjusted rate minus COIN balance available in usr's address)
    /// @param usr address
    /// @param safeHandler address
    /// @param collateralType address
    /// @return wad
    function _getRepaidAllDebt(
        address usr,
        address safeHandler,
        bytes32 collateralType
    ) internal view returns (uint256 wad) {
        // Gets actual rate from the safeEngine
        (, uint256 rate, , , , ) = safeEngine.collateralTypes(collateralType);
        // Gets actual generatedDebt value of the safe
        (, uint256 generatedDebt) = safeEngine.safes(
            collateralType,
            safeHandler
        );
        // Gets actual coin amount in the safe
        uint256 coin = safeEngine.coinBalance(usr);

        uint256 rad = (generatedDebt * rate) - coin;
        wad = rad / RAY;

        // If the rad precision has some dust, it will need to request for 1 extra wad wei
        wad = (wad * RAY) < rad ? wad + 1 : wad;
    }

    /// @notice Gets debt amount for wad (rate adjusted debt)
    /// @param vat address
    /// @param urn address
    /// @param ilk bytes32
    /// @param wad uint256
    /// @return dart
    function _getDrawDart(
        address vat,
        address urn,
        bytes32 ilk,
        uint256 wad
    ) internal returns (int dart) {
        // Updates stability fee rate
        uint256 rate = daiJug.drip(ilk);

        // Gets DAI balance of the urn in the vat
        uint256 dai = VatLike(vat).dai(urn);

        // If there was already enough DAI in the vat balance, just exits it without adding more debt
        uint256 rad = wad * RAY;
        if (dai < rad) {
            // Calculates the needed dart so together with the existing dai in the vat is enough to exit wad amount of DAI tokens
            dart = toInt((rad - dai) / rate);
            // This is neeeded due lack of precision. It might need to sum an extra dart wei (for the given DAI wad amount)
            dart = (uint256(dart) * rate) < rad ? dart + 1 : dart;
        }
    }

    /// @notice Gets repaid debt (rate adjusted rate minus COIN balance available in usr's address)
    /// @param vat address
    /// @param usr address
    /// @param urn address
    /// @param ilk bytes32
    /// @return wad
    function _getWipeAllWad(
        address vat,
        address usr,
        address urn,
        bytes32 ilk
    ) internal view returns (uint256 wad) {
        // Gets actual rate from the vat
        (, uint256 rate, , , ) = VatLike(vat).ilks(ilk);
        // Gets actual art value of the urn
        (, uint256 art) = VatLike(vat).urns(ilk, urn);
        // Gets actual dai amount in the urn
        uint256 dai = VatLike(vat).dai(usr);

        uint256 rad = (art * rate) - dai;
        wad = rad / RAY;

        // If the rad precision has some dust, it will need to request for 1 extra wad wei
        wad = (wad * RAY) < rad ? wad + 1 : wad;
    }

    /// @notice Get ETH price from price feed
    /// @return priceFeedValue ETH price
    function _getEthPrice() internal view returns (uint256 priceFeedValue) {
        bytes32 collateralType = safeManager.collateralTypes(safe);
        (address ethFSM, , ) = oracleRelayer.collateralTypes(collateralType);
        priceFeedValue = PriceFeedLike(ethFSM).read();
    }

    /// @notice Get token price from oracle. Reverts if oracle does not exist
    /// @param token Token address
    /// @return price Token price
    function _getTokenPrice(address token) public view returns (uint256 price) {
        address oracle = oracles[token];
        if (oracle != address(0)) {
            return uint256(IOracle(oracle).latestAnswer());
        }
        revert("LazyArb/not-supported-token");
    }

    /// @notice Safe conversion uint256 -> int
    /// @dev Reverts on overflows
    function toInt(uint256 x) internal pure returns (int y) {
        y = int(x);
        require(y >= 0, "int-overflow");
    }

    /// @notice Converts a wad (18 decimal places) to rad (45 decimal places)
    function toRad(uint256 wad) internal pure returns (uint256 rad) {
        rad = wad * RAY;
    }

    receive() external payable {}
}
