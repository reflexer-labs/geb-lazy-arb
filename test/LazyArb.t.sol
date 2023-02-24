// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../src/LazyArb.sol";

contract LazyArbTest is Test {
    LazyArb public implementation;
    UpgradeableBeacon public beacon;
    BeaconProxy public proxy;
    LazyArb public lazyArb;

    address public user = address(0x1);
    address public safeManager =
        address(0xEfe0B4cA532769a3AE758fD82E1426a03A94F185);
    address public taxCollector = address(0xcDB05aEda142a1B0D6044C09C64e4226c1a281EB);
    address public ethJoin = address(0x2D3cD7b81c93f188F3CB8aD87c8Acc73d6226e3A);
    address public coinJoin = address(0x0A5653CCa4DB1B6E265F47CAf6969e64f1CFdC45);
    address public oracle = address(0x4ed9C0dCa0479bC64d8f4EB3007126D5791f7851);
    uint256 public safe;

    function setUp() public {
        implementation = new LazyArb();
        beacon = new UpgradeableBeacon(address(implementation));
        proxy = new BeaconProxy(
            address(beacon),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint256)",
                safeManager,
                taxCollector,
                ethJoin,
                coinJoin,
                oracle,
                safe
            )
        );
        lazyArb = LazyArb(payable(address(proxy)));
    }

    function testRedemptionRate() public {
        uint256 redemptionRate = lazyArb.redemptionRate();
        assertEq(redemptionRate, OracleRelayerLike(oracle).redemptionRate());
    }

    function testDepositETH() public {
        hoax(user);
        uint256 depositAmount = 10 ether;
        assertTrue(lazyArb.depositETH{value: depositAmount}());
        assertEq(address(lazyArb).balance, depositAmount);
    }
}
