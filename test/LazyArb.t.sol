// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../src/LazyArb.sol";
import "../src/connectors/AaveConnector.sol";
import "../src/connectors/CurveConnector.sol";

contract LazyArbTest is Test {
    LazyArb public implementation;
    UpgradeableBeacon public beacon;
    BeaconProxy public proxy;
    LazyArb public lazyArb;
    AaveConnector public connector1;
    CurveConnector public connector2;

    address public user = address(0x1);
    address public safeManager =
        address(0xEfe0B4cA532769a3AE758fD82E1426a03A94F185);
    address public taxCollector = address(0xcDB05aEda142a1B0D6044C09C64e4226c1a281EB);
    address public ethJoin = address(0x2D3cD7b81c93f188F3CB8aD87c8Acc73d6226e3A);
    address public coinJoin = address(0x0A5653CCa4DB1B6E265F47CAf6969e64f1CFdC45);
    address public oracle = address(0x4ed9C0dCa0479bC64d8f4EB3007126D5791f7851);
    address public RAI = address(0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919);
    address public AaveLendigPool = address(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    address public CurvePool = address(0x618788357D0EBd8A37e763ADab3bc575D54c2C7d);

    function setUp() public {
        implementation = new LazyArb();
        beacon = new UpgradeableBeacon(address(implementation));
        proxy = new BeaconProxy(
            address(beacon),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address)",
                safeManager,
                taxCollector,
                ethJoin,
                coinJoin,
                oracle
            )
        );
        lazyArb = LazyArb(payable(address(proxy)));

        connector1 = new AaveConnector(RAI, AaveLendigPool);
        connector2 = new CurveConnector(RAI, CurvePool);
    }

    function depositETH(uint256 depositAmount) public returns (bool) {
        return lazyArb.depositETH{value: depositAmount}();
    }

    function testRedemptionRate() public {
        uint256 redemptionRate = lazyArb.redemptionRate();
        assertEq(redemptionRate, OracleRelayerLike(oracle).redemptionRate());
    }

    function testDepositETH() public {
        hoax(user);
        uint256 depositAmount = 10 ether;
        assertTrue(this.depositETH(depositAmount));
        assertEq(address(lazyArb).balance, depositAmount);
    }

    function testLockETHAndGenerateDebt() public {
        startHoax(user);
        this.depositETH(10 ether);
        lazyArb.lockETHAndGenerateDebt(400 * 1e19, address(connector2));
        vm.stopPrank();
    }
}
