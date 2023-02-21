pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./OracleRelayerLike.sol";
import "./GebSafeManagerLike.sol";

abstract contract LazyArbLike is ReentrancyGuardUpgradeable {
    // --- Variables ---
    OracleRelayerLike  public oracleRelayer;
    GebSafeManagerLike public safeManager;
}
