// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
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

contract LazyArb is ReentrancyGuardUpgradeable {
    uint256 constant RAY = 10 ** 27;

    ManagerLike public safeManager;
    SAFEEngineLike public safeEngine;
    TaxCollectorLike public taxCollector;
    CollateralJoinLike public ethJoin;
    CoinJoinLike public coinJoin;
    SystemCoinLike public systemCoin;
    OracleRelayerLike public oracleRelayer;

    uint256 public safe;

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
        address oracleRelayer_
    ) external initializer {
        require(safeManager_ != address(0), "LazyArb/null-safe-manager");
        require(taxCollector_ != address(0), "LazyArb/null-tax-collector");
        require(ethJoin_ != address(0), "LazyArb/null-eth-join");
        require(coinJoin_ != address(0), "LazyArb/null-coin-join");
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
    function lockETHAndGenerateDebt(
        uint256 deltaWad,
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
        systemCoin.approve(connector, systemCoinBalance);
        IConnector(connector).deposit(systemCoinBalance);
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
