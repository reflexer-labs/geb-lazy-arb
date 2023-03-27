// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interface/IConnector.sol";

abstract contract CollateralLike {
    function approve(address, uint) public virtual;

    function transfer(address, uint) public virtual;

    function transferFrom(address, address, uint) public virtual;

    function deposit() public payable virtual;

    function withdraw(uint) public virtual;
}

abstract contract ManagerLike {
    function safeCan(address, uint, address) public view virtual returns (uint);

    function collateralTypes(uint) public view virtual returns (bytes32);

    function ownsSAFE(uint) public view virtual returns (address);

    function safes(uint) public view virtual returns (address);

    function safeEngine() public view virtual returns (address);

    function openSAFE(bytes32, address) public virtual returns (uint);

    function transferSAFEOwnership(uint, address) public virtual;

    function allowSAFE(uint, address, uint) public virtual;

    function allowHandler(address, uint) public virtual;

    function modifySAFECollateralization(uint, int, int) public virtual;

    function transferCollateral(uint, address, uint) public virtual;

    function transferInternalCoins(uint, address, uint) public virtual;

    function quitSystem(uint, address) public virtual;

    function enterSystem(address, uint) public virtual;

    function moveSAFE(uint, uint) public virtual;

    function protectSAFE(uint, address, address) public virtual;
}

abstract contract SAFEEngineLike {
    function canModifySAFE(address, address) public view virtual returns (uint);

    function collateralTypes(
        bytes32
    ) public view virtual returns (uint, uint, uint, uint, uint, uint);

    function coinBalance(address) public view virtual returns (uint);

    function safes(bytes32, address) public view virtual returns (uint, uint);

    function modifySAFECollateralization(
        bytes32,
        address,
        address,
        address,
        int,
        int
    ) public virtual;

    function approveSAFEModification(address) public virtual;

    function transferInternalCoins(address, address, uint) public virtual;
}

abstract contract CollateralJoinLike {
    function decimals() public virtual returns (uint);

    function collateral() public virtual returns (CollateralLike);

    function join(address, uint) public payable virtual;

    function exit(address, uint) public virtual;
}

abstract contract CoinJoinLike {
    function safeEngine() public virtual returns (SAFEEngineLike);

    function join(address, uint) public payable virtual;

    function exit(address, uint) public virtual;

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

abstract contract TaxCollectorLike {
    function taxSingle(bytes32) public virtual returns (uint);
}

interface GemLike {
    function approve(address, uint) external;
    function transfer(address, uint) external;
    function transferFrom(address, address, uint) external;
    function deposit() external payable;
    function withdraw(uint) external;
}

interface DaiManagerLike {
    function cdpCan(address, uint, address) external view returns (uint);
    function ilks(uint) external view returns (bytes32);
    function owns(uint) external view returns (address);
    function urns(uint) external view returns (address);
    function vat() external view returns (address);
    function open(bytes32, address) external returns (uint);
    function give(uint, address) external;
    function cdpAllow(uint, address, uint) external;
    function urnAllow(address, uint) external;
    function frob(uint, int, int) external;
    function flux(uint, address, uint) external;
    function move(uint, address, uint) external;
    function exit(address, uint, address, uint) external;
    function quit(uint, address) external;
    function enter(address, uint) external;
    function shift(uint, uint) external;
}

interface VatLike {
    function can(address, address) external view returns (uint);
    function ilks(bytes32) external view returns (uint, uint, uint, uint, uint);
    function dai(address) external view returns (uint);
    function urns(bytes32, address) external view returns (uint, uint);
    function frob(bytes32, address, address, address, int, int) external;
    function hope(address) external;
    function move(address, address, uint) external;
}

interface GemJoinLike {
    function dec() external returns (uint);
    function gem() external returns (GemLike);
    function join(address, uint) external payable;
    function exit(address, uint) external;
}

interface DaiJoinLike {
    function vat() external returns (VatLike);
    function dai() external returns (GemLike);
    function join(address, uint) external payable;
    function exit(address, uint) external;
}

interface JugLike {
    function drip(bytes32) external returns (uint);
}

contract LazyArb is ReentrancyGuardUpgradeable {
    uint256 private constant RAY = 10 ** 27;
    ISwapRouter private constant uniswapV3Router =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
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

    /// @notice Initialize LazyArb contract
    /// @param safeManager_ address
    /// @param taxCollector_ address
    /// @param ethJoin_ address
    /// @param coinJoin_ address
    /// @param oracleRelayer_ address
    function initialize(
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
        require(safeManager_ != address(0), "LazyArb/null-safe-manager");
        require(taxCollector_ != address(0), "LazyArb/null-tax-collector");
        require(ethJoin_ != address(0), "LazyArb/null-eth-join");
        require(coinJoin_ != address(0), "LazyArb/null-coin-join");
        require(dai_manager_ != address(0), "LazyArb/null-dai-manager");
        require(dai_jug_ != address(0), "LazyArb/null-dai-jug");
        require(dai_ethJoin_ != address(0), "LazyArb/null-dai-eth-join");
        require(dai_daiJoin_ != address(0), "LazyArb/null-dai-dai-join");
        require(oracleRelayer_ != address(0), "LazyArb/null-oracle-relayer");

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

    /// @notice Returns current redemption rate
    function redemptionRate() external view returns (uint256) {
        return oracleRelayer.redemptionRate();
    }

    /// @notice Deposit ETH
    function depositETH() external payable returns (bool success) {
        return true;
    }

    /// @notice Locks Eth, generates debt and sends COIN amount (deltaWad) to msg.sender
    /// @dev can execute only if the redemption rate is negative
    /// @param deltaWad uint - Amount
    /// @param minDaiAmount uint - Minimum DAI amount expect in swap
    /// @param connector address - External connector address
    function lockETHAndGenerateDebt(
        uint256 deltaWad,
        uint256 minDaiAmount,
        address connector
    ) external {
        require(
            oracleRelayer.redemptionRate() < RAY,
            "LazyArb/redemption-rate-positive"
        );

        address safeHandler = safeManager.safes(safe);
        bytes32 collateralType = safeManager.collateralTypes(safe);

        // Receives ETH amount, converts it to WETH and joins it into the safeEngine
        uint256 collateralBalance = address(this).balance;
        ethJoin_join(safeHandler, collateralBalance);
        // Locks WETH amount into the SAFE and generates debt
        modifySAFECollateralization(
            toInt(collateralBalance),
            _getGeneratedDeltaDebt(safeHandler, collateralType, deltaWad)
        );
        // Moves the COIN amount (balance in the safeEngine in rad) to proxy's address
        transferInternalCoins(address(this), toRad(deltaWad));
        // Allows adapter to access to proxy's COIN balance in the safeEngine
        if (safeEngine.canModifySAFE(address(this), address(coinJoin)) == 0) {
            safeEngine.approveSAFEModification(address(coinJoin));
        }
        // Exits COIN as a token
        coinJoin.exit(address(this), deltaWad);

        uint256 systemCoinBalance = systemCoin.balanceOf(address(this));
        systemCoin.approve(address(uniswapV3Router), systemCoinBalance);

        uniswapV3Router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(systemCoin),
                tokenOut: address(DAI),
                fee: uint24(500),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: systemCoinBalance,
                amountOutMinimum: minDaiAmount,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 daiBalance = DAI.balanceOf(address(this));
        DAI.approve(connector, daiBalance);

        IConnector(connector).deposit(daiBalance);
    }

    function lockETHAndDraw(
        uint wadD,
        address connector
    ) external {
        require(
            oracleRelayer.redemptionRate() > RAY,
            "LazyArb/redemption-rate-positive"
        );

        address urn = dai_manager.urns(cdp);
        address vat = dai_manager.vat();
        bytes32 ilk = dai_manager.ilks(cdp);
        // Receives ETH amount, converts it to WETH and joins it into the vat
        uint256 collateralBalance = address(this).balance;
        dai_ethJoin_join(urn, collateralBalance);
        // Locks WETH amount into the CDP and generates debt
        dai_manager.frob(cdp, toInt(collateralBalance), _getDrawDart(vat, urn, ilk, wadD));
        // Moves the DAI amount (balance in the vat in rad) to proxy's address
        dai_manager.move(cdp, address(this), toRad(wadD));
        // Allows adapter to access to proxy's DAI balance in the vat
        if (VatLike(vat).can(address(this), address(dai_daiJoin)) == 0) {
            VatLike(vat).hope(address(dai_daiJoin));
        }
        // Exits DAI to the user's wallet as a token
        dai_daiJoin.exit(msg.sender, wadD);

        uint256 daiBalance = DAI.balanceOf(address(this));
        DAI.approve(connector, daiBalance);

        IConnector(connector).deposit(daiBalance);
    }

    /// @notice Joins the system with the a specified value
    /// @param safeHandler address
    /// @param value uint - Value to join
    function ethJoin_join(address safeHandler, uint value) internal {
        // Wraps ETH in WETH
        ethJoin.collateral().deposit{value: value}();
        // Approves adapter to take the WETH amount
        ethJoin.collateral().approve(address(ethJoin), value);
        // Joins WETH collateral into the safeEngine
        ethJoin.join(safeHandler, value);
    }

    function dai_ethJoin_join(address urn, uint value) public payable {
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

    /// @notice Transfer rad amount of COIN from the safe address to a dst address.
    /// @param dst address - destination address
    /// uint rad - amount
    function transferInternalCoins(address dst, uint rad) internal {
        safeManager.transferInternalCoins(safe, dst, rad);
    }

    /// @notice Gets delta debt generated (Total Safe debt minus available safeHandler COIN balance)
    /// @param safeHandler address
    /// @param collateralType bytes32
    /// @return deltaDebt
    function _getGeneratedDeltaDebt(
        address safeHandler,
        bytes32 collateralType,
        uint wad
    ) internal returns (int deltaDebt) {
        // Updates stability fee rate
        uint rate = taxCollector.taxSingle(collateralType);
        require(rate > 0, "invalid-collateral-type");

        // Gets COIN balance of the handler in the safeEngine
        uint coin = safeEngine.coinBalance(safeHandler);

        // If there was already enough COIN in the safeEngine balance, just exits it without adding more debt
        if (coin < multiply(wad, RAY)) {
            // Calculates the needed deltaDebt so together with the existing coins in the safeEngine is enough to exit wad amount of COIN tokens
            deltaDebt = toInt(subtract(multiply(wad, RAY), coin) / rate);
            // This is neeeded due lack of precision. It might need to sum an extra deltaDebt wei (for the given COIN wad amount)
            deltaDebt = multiply(uint(deltaDebt), rate) < multiply(wad, RAY)
                ? deltaDebt + 1
                : deltaDebt;
        }
    }

    function _getDrawDart(
        address vat,
        address urn,
        bytes32 ilk,
        uint wad
    ) internal returns (int dart) {
        // Updates stability fee rate
        uint rate = dai_jug.drip(ilk);

        // Gets DAI balance of the urn in the vat
        uint dai = VatLike(vat).dai(urn);

        // If there was already enough DAI in the vat balance, just exits it without adding more debt
        if (dai < multiply(wad, RAY)) {
            // Calculates the needed dart so together with the existing dai in the vat is enough to exit wad amount of DAI tokens
            dart = toInt(subtract(multiply(wad, RAY), dai) / rate);
            // This is neeeded due lack of precision. It might need to sum an extra dart wei (for the given DAI wad amount)
            dart = multiply(uint(dart), rate) < multiply(wad, RAY) ? dart + 1 : dart;
        }
    }

    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "mul-overflow");
    }

    /// @notice Safe subtraction
    /// @dev Reverts on overflows
    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "sub-overflow");
    }

    /// @notice Safe conversion uint -> int
    /// @dev Reverts on overflows
    function toInt(uint x) internal pure returns (int y) {
        y = int(x);
        require(y >= 0, "int-overflow");
    }

    /// @notice Converts a wad (18 decimal places) to rad (45 decimal places)
    function toRad(uint wad) internal pure returns (uint rad) {
        rad = multiply(wad, 10 ** 27);
    }
}
