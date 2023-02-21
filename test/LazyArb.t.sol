// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../src/LazyArb.sol";
import "../src/utils/Proxy.sol";

contract LazyArbTest is Test {
    LazyArb public implementation;
    AdminUpgradeabilityProxy public beacon;
    BeaconProxy public proxy;
    LazyArb public lazyArb;

    address public user = address(0x1);
    address public oracle = address(0x4ed9C0dCa0479bC64d8f4EB3007126D5791f7851);
    address public safeManaber = address(0xEfe0B4cA532769a3AE758fD82E1426a03A94F185);

    function setUp() public {
        implementation = new LazyArb();
        beacon = new AdminUpgradeabilityProxy(
            address(implementation),
            user,
            ""
        );
        proxy = new BeaconProxy(
            address(beacon),
            abi.encodeWithSignature(
                "initialize(address,address)",
                oracle,
                safeManaber
            )
        );
        lazyArb = LazyArb(address(proxy));
    }
}
