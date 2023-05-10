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
    function safeCan(address, uint256, address) public view virtual returns (uint256);

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
    function canModifySAFE(address, address) public view virtual returns (uint256);

    function collateralTypes(
        bytes32
    ) public view virtual returns (uint256, uint256, uint256, uint256, uint256, uint256);

    function coinBalance(address) public view virtual returns (uint256);

    function safes(bytes32, address) public view virtual returns (uint256, uint256);

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
    function priceSource() virtual public view returns (address);
    function read() virtual public view returns (uint256);
    function getResultWithValidity() virtual external view returns (uint256,bool);
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
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
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
    uint256 public constant WAD = 10**18;
    uint256 private constant RAY = 10 ** 27;
    uint256 public constant MAX_CRATIO = 1000;
    ISwapRouter private constant uniswapV3Router =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IQuoter private constant uniswapV3Quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    IERC20Upgradeable private constant DAI = IERC20Upgradeable(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    ManagerLike public safeManager;
    SAFEEngineLike public safeEngine;
    TaxCollectorLike public taxCollector;
    CollateralJoinLike public ethJoin;
    CoinJoinLike public coinJoin;
    SystemCoinLike public systemCoin;
    DaiManagerLike public dai_manager;
    JugLike public dai_jug;
    GemJoinLike public dai_ethJoin;
    DaiJoinLike public dai_daiJoin;
    OracleRelayerLike public oracleRelayer;

    uint256 public safe;
    uint256 public cdp;
    Status public status;

    modifier onlyOwner {
        require(msg.sender == owner, "LazyArb/not-owner");
        _;
    }

    /// @notice Initialize LazyArb contract
    /// @param owner_ address
    /// @param minCRatio_ uint256
    /// @param maxCRatio_ uint256
    /// @param safeManager_ address
    /// @param taxCollector_ address
    /// @param ethJoin_ address
    /// @param coinJoin_ address
    /// @param dai_manager_ address
    /// @param dai_jug_ address
    /// @param dai_ethJoin_ address
    /// @param dai_daiJoin_ address
    /// @param oracleRelayer_ address
    function initialize(
        address owner_,
        uint256 minCRatio_,
        uint256 maxCRatio_,
        address safeManager_,
        address taxCollector_,
        address ethJoin_,
        address coinJoin_,
        address dai_manager_,
        address dai_jug_,
        address dai_ethJoin_,
        address dai_daiJoin_,
        address oracleRelayer_
    ) external initializer {
        require(owner_ != address(0), "LazyArb/null-owner");
        require(minCRatio_ < maxCRatio_ && maxCRatio_ < MAX_CRATIO, "LazyArb/invalid-cRatio");
        require(safeManager_ != address(0), "LazyArb/null-safe-manager");
        require(taxCollector_ != address(0), "LazyArb/null-tax-collector");
        require(ethJoin_ != address(0), "LazyArb/null-eth-join");
        require(coinJoin_ != address(0), "LazyArb/null-coin-join");
        require(dai_manager_ != address(0), "LazyArb/null-dai-manager");
        require(dai_jug_ != address(0), "LazyArb/null-dai-jug");
        require(dai_ethJoin_ != address(0), "LazyArb/null-dai-eth-join");
        require(dai_daiJoin_ != address(0), "LazyArb/null-dai-dai-join");
        require(oracleRelayer_ != address(0), "LazyArb/null-oracle-relayer");

        owner = owner_;
        minCRatio = minCRatio_;
        maxCRatio = maxCRatio_;

        safeManager = ManagerLike(safeManager_);
        taxCollector = TaxCollectorLike(taxCollector_);
        ethJoin = CollateralJoinLike(ethJoin_);
        coinJoin = CoinJoinLike(coinJoin_);
        oracleRelayer = OracleRelayerLike(oracleRelayer_);

        safeEngine = SAFEEngineLike(safeManager.safeEngine());
        systemCoin = coinJoin.systemCoin();

        safe = safeManager.openSAFE("ETH-A", address(this));
        safeManager.allowSAFE(safe, msg.sender, 1);

        dai_manager = DaiManagerLike(dai_manager_);
        dai_jug = JugLike(dai_jug_);
        dai_ethJoin = GemJoinLike(dai_ethJoin_);
        dai_daiJoin = DaiJoinLike(dai_daiJoin_);

        cdp = dai_manager.open("ETH-A", address(this));

        oracleRelayer.redemptionPrice();
    }

    /// @notice Sets minCRatio, maxCRatio value
    /// @param minCRatio_ New minCRatio value
    /// @param maxCRatio_ New maxCRatio value
    function setCRatio(uint256 minCRatio_, uint256 maxCRatio_) external onlyOwner {
        require(minCRatio_ < maxCRatio_ && maxCRatio_ < MAX_CRATIO, "LazyArb/invalid-cRatio");
        minCRatio = minCRatio_;
        maxCRatio = maxCRatio_;
    }

    /// @notice Returns current redemption rate
    function redemptionRate() external view returns (uint256) {
        return oracleRelayer.redemptionRate();
    }

    function lockETHAndGenerateDebt(
        uint256 minAmount,
        address connector
    ) public onlyOwner {
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
        modifySAFECollateralization(
            toInt(collateralBalance),
            0
        );

        rebalanceShort(minAmount, connector);
    }

    function rebalanceShort(
        uint256 minAmount,
        address connector
    ) public {
        require(status == Status.Short, "LazyArb/status-not-short");

        address safeHandler = safeManager.safes(safe);
        bytes32 collateralType = safeManager.collateralTypes(safe);

        uint256 targetDebtAmount;
        uint256 currentDebtAmount;

        {
            uint256 priceFeedValue;
            {
                (address ethFSM,,) = oracleRelayer.collateralTypes(collateralType);
                priceFeedValue = PriceFeedLike(ethFSM).read();
            }

            (uint256 depositedCollateralToken, ) = safeEngine.safes(collateralType, safeHandler);
            uint256 totalCollateral = mul(depositedCollateralToken, priceFeedValue) / WAD;

            currentDebtAmount = _getRepaidAllDebt(safeHandler, safeHandler, collateralType);
            uint256 currentCRatio = mul(mul(currentDebtAmount, oracleRelayer.redemptionPrice()) / RAY, MAX_CRATIO) / totalCollateral;
            require(currentCRatio < minCRatio || currentCRatio > maxCRatio, "LazyArb/cRatio-in-range");

            uint256 targetCRatio = (minCRatio + maxCRatio) / 2;
            targetDebtAmount = mul(mul(targetCRatio, totalCollateral) / MAX_CRATIO, RAY) / oracleRelayer.redemptionPrice();
        }

        if (targetDebtAmount > currentDebtAmount) {
            uint256 deltaWad = targetDebtAmount - currentDebtAmount;
            // Generates debt
            modifySAFECollateralization(
                0,
                _getGeneratedDeltaDebt(safeHandler, collateralType, deltaWad)
            );

            exitRaiAndConvertToDai(deltaWad, minAmount);
            depositDai(connector);
        } else {
            uint256 deltaWad = currentDebtAmount - targetDebtAmount;
            uint256 requiredDAIAmount = uniswapV3Quoter.quoteExactOutputSingle(
                address(DAI),
                address(systemCoin),
                uint24(500),
                deltaWad,
                0
            );

            IERC20Upgradeable lpToken = IERC20Upgradeable(IConnector(connector).lpToken());
            uint256 lpTokenBalance = lpToken.balanceOf(address(this));
            lpToken.approve(connector, lpTokenBalance);
            IConnector(connector).withdraw(requiredDAIAmount);

            uniswapSwap(address(DAI), address(systemCoin), DAI.balanceOf(address(this)), minAmount);

            uint256 raiBalance = systemCoin.balanceOf(address(this));
            _coinJoin_join(safeHandler, raiBalance);
            // Paybacks debt to the SAFE and unlocks WETH amount from it
            modifySAFECollateralization(
                0,
                -_getGeneratedDeltaDebt(safeHandler, collateralType, deltaWad)
            );
        }
    }

    /// @notice Repays debt and frees ETH (sends it to msg.sender)
    /// @param minRaiAmount uint256 - Minimum RAI amount expect in swap
    /// @param connectors address[] - List of connectors
    function repayDebtAndFreeETH(
        uint256 minRaiAmount,
        address[] calldata connectors
    ) public onlyOwner {
        require(status == Status.Short, "LazyArb/status-not-short");
        status = Status.None;

        uint256 length = connectors.length;
        for (uint256 i; i != length; ++i) {
            IConnector connector = IConnector(connectors[i]);
            IERC20Upgradeable lpToken = IERC20Upgradeable(connector.lpToken());
            uint256 lpTokenBalance = lpToken.balanceOf(address(this));
            lpToken.approve(address(connector), lpTokenBalance);
            connector.withdrawAll();
        }

        uint256 daiBalance = DAI.balanceOf(address(this));
        uniswapSwap(address(DAI), address(systemCoin), daiBalance, minRaiAmount);

        uint256 raiBalance = systemCoin.balanceOf(address(this));

        address safeHandler = safeManager.safes(safe);
        bytes32 collateralType = safeManager.collateralTypes(safe);
        uint256 raiDebtAmount = _getRepaidAllDebt(safeHandler, safeHandler, collateralType);
        if (raiBalance < raiDebtAmount) {
            uint256 missingRaiAmount = raiDebtAmount - raiBalance;
            address WETH = address(ethJoin.collateral());
            uint256 requiredETHAmount = uniswapV3Quoter.quoteExactOutputSingle(
                WETH,
                address(systemCoin),
                uint24(500),
                missingRaiAmount,
                0
            );
            modifySAFECollateralization(
                -toInt(requiredETHAmount),
                0
            );
            // Moves the amount from the SAFE handler to proxy's address
            transferCollateral(address(this), requiredETHAmount);
            // Exits WETH amount to proxy address as a token
            ethJoin.exit(address(this), requiredETHAmount);
            // Swap WETH to RAI
            uniswapSwap(WETH, address(systemCoin), requiredETHAmount, missingRaiAmount);
        }

        (uint256 depositedCollateralToken, uint256 generatedDebt) = safeEngine.safes(collateralType, safeHandler);
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

    function lockETHAndDraw(
        address connector
    ) public onlyOwner {
        require(
            oracleRelayer.redemptionRate() >= RAY,
            "LazyArb/redemption-rate-positive"
        );

        require(status != Status.Short, "LazyArb/status-short");
        status = Status.Long;

        address urn = dai_manager.urns(cdp);
        // address vat = dai_manager.vat();
        // bytes32 ilk = dai_manager.ilks(cdp);
        // Receives ETH amount, converts it to WETH and joins it into the vat
        uint256 collateralBalance = address(this).balance;
        dai_ethJoin_join(urn, collateralBalance);
        // Locks WETH amount into the CDP and generates debt
        dai_manager.frob(cdp, toInt(collateralBalance), 0);

        rebalanceLong(connector);
    }

    function rebalanceLong(
        address connector
    ) public {
        require(status == Status.Long, "LazyArb/status-not-long");

        address urn = dai_manager.urns(cdp);
        address vat = dai_manager.vat();
        bytes32 ilk = dai_manager.ilks(cdp);
        (uint256 depositedCollateral,) = VatLike(vat).urns(ilk, urn);

        uint256 targetDebtAmount;
        uint256 currentDebtAmount;

        {
            uint256 priceFeedValue;
            {
                bytes32 collateralType = safeManager.collateralTypes(safe);
                (address ethFSM,,) = oracleRelayer.collateralTypes(collateralType);
                priceFeedValue = PriceFeedLike(ethFSM).read();
            }

            uint256 totalCollateral = mul(depositedCollateral, priceFeedValue) / WAD;

            currentDebtAmount = _getWipeAllWad(vat, urn, urn, ilk);
            {
                uint256 currentCRatio = mul(currentDebtAmount, MAX_CRATIO) / totalCollateral;
                require(currentCRatio < minCRatio || currentCRatio > maxCRatio, "LazyArb/cRatio-in-range");
            }

            {
                uint256 targetCRatio = (minCRatio + maxCRatio) / 2;
                targetDebtAmount = mul(targetCRatio, totalCollateral) / MAX_CRATIO;
            }
        }

        if (targetDebtAmount > currentDebtAmount) {
            uint256 wadD = targetDebtAmount - currentDebtAmount;
            // Generates debt
            dai_manager.frob(cdp, 0, _getDrawDart(vat, urn, ilk, wadD));

            exitDai(wadD);
            depositDai(connector);
        } else {
            uint256 wadD = currentDebtAmount - targetDebtAmount;
            IERC20Upgradeable lpToken = IERC20Upgradeable(IConnector(connector).lpToken());
            uint256 lpTokenBalance = lpToken.balanceOf(address(this));
            lpToken.approve(connector, lpTokenBalance);
            IConnector(connector).withdraw(wadD);
            wadD = DAI.balanceOf(address(this));

            // Joins DAI amount into the vat
            _daiJoin_join(urn, wadD);
            // Paybacks debt to the CDP and unlocks WETH amount from it
            dai_manager.frob(
                cdp,
                0,
                -_getDrawDart(vat, urn, ilk, wadD)
            );
        }
    }

    function wipeAndFreeETH(
        address[] calldata connectors
    ) public onlyOwner {
        require(status == Status.Long, "LazyArb/status-not-long");
        status = Status.None;

        uint256 length = connectors.length;
        for (uint256 i; i != length; ++i) {
            IConnector connector = IConnector(connectors[i]);
            IERC20Upgradeable lpToken = IERC20Upgradeable(connector.lpToken());
            uint256 lpTokenBalance = lpToken.balanceOf(address(this));
            lpToken.approve(address(connector), lpTokenBalance);
            connector.withdrawAll();
        }

        uint256 daiBalance = DAI.balanceOf(address(this));

        address vat = dai_manager.vat();
        address urn = dai_manager.urns(cdp);
        bytes32 ilk = dai_manager.ilks(cdp);
        uint256 daiDebtAmount = _getWipeAllWad(vat, urn, urn, ilk);
        if (daiBalance < daiDebtAmount) {
            uint256 missingDaiAmount = daiDebtAmount - daiBalance;
            address WETH = address(dai_ethJoin.gem());
            uint256 requiredETHAmount = uniswapV3Quoter.quoteExactOutputSingle(
                WETH,
                address(DAI),
                uint24(500),
                missingDaiAmount,
                0
            );
            dai_manager.frob(
                cdp,
                -toInt(requiredETHAmount),
                0
            );
            // Moves the amount from the SAFE handler to proxy's address
            dai_manager.flux(cdp, address(this), requiredETHAmount);
            // Exits WETH amount to proxy address as a token
            dai_ethJoin.exit(address(this), requiredETHAmount);
            // Swap WETH to DAI
            uniswapSwap(WETH, address(DAI), requiredETHAmount, missingDaiAmount);
        }

        (uint256 depositedCollateral, uint256 art) = VatLike(vat).urns(ilk, urn);
        // Joins DAI amount into the vat
        _daiJoin_join(urn, daiDebtAmount);
        // Paybacks debt to the CDP and unlocks WETH amount from it
        dai_manager.frob(
            cdp,
            -toInt(depositedCollateral),
            -int(art)
        );
        // Moves the amount from the CDP urn to proxy's address
        dai_manager.flux(cdp, address(this), depositedCollateral);
        // Exits WETH amount to proxy address as a token
        dai_ethJoin.exit(address(this), depositedCollateral);
        // Converts WETH to ETH
        dai_ethJoin.gem().withdraw(depositedCollateral);
    }

    function flip(
        uint256 minAmount,
        address[] calldata connectors,
        address connector
    ) external {
        if (oracleRelayer.redemptionRate() < RAY) {
            require(status == Status.Long, "LazyArb/status-not-long");

            wipeAndFreeETH(connectors);
            lockETHAndGenerateDebt(minAmount, connector);
        } else {
            require(status == Status.Short, "LazyArb/status-not-short");

            repayDebtAndFreeETH(minAmount, connectors);
            lockETHAndDraw(connector);
        }
    }

    function exitRaiAndConvertToDai(
        uint256 deltaWad,
        uint256 minDaiAmount
    ) internal {
        // Moves the COIN amount (balance in the safeEngine in rad) to proxy's address
        transferInternalCoins(address(this), toRad(deltaWad));
        // Allows adapter to access to proxy's COIN balance in the safeEngine
        if (safeEngine.canModifySAFE(address(this), address(coinJoin)) == 0) {
            safeEngine.approveSAFEModification(address(coinJoin));
        }
        // Exits COIN as a token
        coinJoin.exit(address(this), deltaWad);

        uint256 systemCoinBalance = systemCoin.balanceOf(address(this));
        uniswapSwap(address(systemCoin), address(DAI), systemCoinBalance, minDaiAmount);
    }

    function exitDai(uint256 wadD) internal {
        address vat = dai_manager.vat();

        // Moves the DAI amount (balance in the vat in rad) to proxy's address
        dai_manager.move(cdp, address(this), toRad(wadD));
        // Allows adapter to access to proxy's DAI balance in the vat
        if (VatLike(vat).can(address(this), address(dai_daiJoin)) == 0) {
            VatLike(vat).hope(address(dai_daiJoin));
        }
        // Exits DAI to the user's wallet as a token
        dai_daiJoin.exit(address(this), wadD);
    }

    function depositDai(address connector) internal {
        uint256 daiBalance = DAI.balanceOf(address(this));
        DAI.approve(connector, daiBalance);

        IConnector(connector).deposit(daiBalance);
    }

    function uniswapSwap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin) internal {
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

    function dai_ethJoin_join(address urn, uint256 value) internal {
        // Wraps ETH in WETH
        dai_ethJoin.gem().deposit{value: value}();
        // Approves adapter to take the WETH amount
        dai_ethJoin.gem().approve(address(dai_ethJoin), value);
        // Joins WETH collateral into the vat
        dai_ethJoin.join(urn, value);
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
    function transferCollateral(
        address dst,
        uint256 wad
    ) internal {
        safeManager.transferCollateral(safe, dst, wad);
    }

    /// @notice Transfer rad amount of COIN from the safe address to a dst address.
    /// @param dst address - destination address
    /// uint256 rad - amount
    function transferInternalCoins(address dst, uint256 rad) internal {
        safeManager.transferInternalCoins(safe, dst, rad);
    }

    function _coinJoin_join(address safeHandler, uint256 wad) internal {
        // Approves adapter to take the COIN amount
        coinJoin.systemCoin().approve(address(coinJoin), wad);
        // Joins COIN into the safeEngine
        coinJoin.join(safeHandler, wad);
    }

    function _daiJoin_join(address urn, uint256 wad) internal {
        // Approves adapter to take the DAI amount
        dai_daiJoin.dai().approve(address(dai_daiJoin), wad);
        // Joins DAI into the vat
        dai_daiJoin.join(urn, wad);
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
        if (coin < mul(wad, RAY)) {
            // Calculates the needed deltaDebt so together with the existing coins in the safeEngine is enough to exit wad amount of COIN tokens
            deltaDebt = toInt(sub(mul(wad, RAY), coin) / rate);
            // This is neeeded due lack of precision. It might need to sum an extra deltaDebt wei (for the given COIN wad amount)
            deltaDebt = mul(uint256(deltaDebt), rate) < mul(wad, RAY)
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
        (, uint256 rate,,,,) = safeEngine.collateralTypes(collateralType);
        require(rate > 0, "invalid-collateral-type");

        // Gets actual generatedDebt value of the safe
        (, uint256 generatedDebt) = safeEngine.safes(collateralType, safeHandler);

        // Uses the whole coin balance in the safeEngine to reduce the debt
        deltaDebt = toInt(coin / rate);
        // Checks the calculated deltaDebt is not higher than safe.generatedDebt (total debt), otherwise uses its value
        deltaDebt = uint256(deltaDebt) <= generatedDebt ? - deltaDebt : - toInt(generatedDebt);
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
        (, uint256 rate,,,,) = safeEngine.collateralTypes(collateralType);
        // Gets actual generatedDebt value of the safe
        (, uint256 generatedDebt) = safeEngine.safes(collateralType, safeHandler);
        // Gets actual coin amount in the safe
        uint256 coin = safeEngine.coinBalance(usr);

        uint256 rad = sub(mul(generatedDebt, rate), coin);
        wad = rad / RAY;

        // If the rad precision has some dust, it will need to request for 1 extra wad wei
        wad = mul(wad, RAY) < rad ? wad + 1 : wad;
    }

    function _getDrawDart(
        address vat,
        address urn,
        bytes32 ilk,
        uint256 wad
    ) internal returns (int dart) {
        // Updates stability fee rate
        uint256 rate = dai_jug.drip(ilk);

        // Gets DAI balance of the urn in the vat
        uint256 dai = VatLike(vat).dai(urn);

        // If there was already enough DAI in the vat balance, just exits it without adding more debt
        if (dai < mul(wad, RAY)) {
            // Calculates the needed dart so together with the existing dai in the vat is enough to exit wad amount of DAI tokens
            dart = toInt(sub(mul(wad, RAY), dai) / rate);
            // This is neeeded due lack of precision. It might need to sum an extra dart wei (for the given DAI wad amount)
            dart = mul(uint256(dart), rate) < mul(wad, RAY) ? dart + 1 : dart;
        }
    }

    function _getWipeAllWad(
        address vat,
        address usr,
        address urn,
        bytes32 ilk
    ) internal view returns (uint256 wad) {
        // Gets actual rate from the vat
        (, uint256 rate,,,) = VatLike(vat).ilks(ilk);
        // Gets actual art value of the urn
        (, uint256 art) = VatLike(vat).urns(ilk, urn);
        // Gets actual dai amount in the urn
        uint256 dai = VatLike(vat).dai(usr);

        uint256 rad = sub(mul(art, rate), dai);
        wad = rad / RAY;

        // If the rad precision has some dust, it will need to request for 1 extra wad wei
        wad = mul(wad, RAY) < rad ? wad + 1 : wad;
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "mul-overflow");
    }

    /// @notice Safe subtraction
    /// @dev Reverts on overflows
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "sub-overflow");
    }

    /// @notice Safe conversion uint256 -> int
    /// @dev Reverts on overflows
    function toInt(uint256 x) internal pure returns (int y) {
        y = int(x);
        require(y >= 0, "int-overflow");
    }

    /// @notice Converts a wad (18 decimal places) to rad (45 decimal places)
    function toRad(uint256 wad) internal pure returns (uint256 rad) {
        rad = mul(wad, 10 ** 27);
    }

    receive() external payable {}
}
