// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../src/LazyArb.sol";
import "../src/connectors/CurveConnector.sol";
import "../src/mock/MockOracle.sol";

contract LazyArbTest is Test {
    LazyArb public implementation;
    UpgradeableBeacon public beacon;
    BeaconProxy public proxy;
    LazyArb public lazyArb;
    CurveConnector public connector;
    MockOracle public mockOracle;

    address public user = address(0x1);
    address public safeManager =
        address(0xEfe0B4cA532769a3AE758fD82E1426a03A94F185);
    address public taxCollector = address(0xcDB05aEda142a1B0D6044C09C64e4226c1a281EB);
    address public ethJoin = address(0x2D3cD7b81c93f188F3CB8aD87c8Acc73d6226e3A);
    address public coinJoin = address(0x0A5653CCa4DB1B6E265F47CAf6969e64f1CFdC45);
    address public dai_manager = address(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
    address public dai_jug = address(0x19c0976f590D67707E62397C87829d896Dc0f1F1);
    address public dai_ethJoin = address(0x2F0b23f53734252Bda2277357e97e1517d6B042A);
    address public dai_daiJoin = address(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
    address public oracle = address(0x4ed9C0dCa0479bC64d8f4EB3007126D5791f7851);
    address public RAI = address(0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919);
    address public DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public AaveLendigPool = address(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    address public CurvePool = address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    address public CurveLP = address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);

    function setUp() public {
        startHoax(user);

        mockOracle = new MockOracle(oracle);
        mockOracle.setRedemptionRate(1e27);

        implementation = new LazyArb();
        beacon = new UpgradeableBeacon(address(implementation));
        proxy = new BeaconProxy(
            address(beacon),
            abi.encodeWithSignature(
                "initialize(address,uint256,address,address,address,address,address,address,address,address,address)",
                user,
                500,
                safeManager,
                taxCollector,
                ethJoin,
                coinJoin,
                dai_manager,
                dai_jug,
                dai_ethJoin,
                dai_daiJoin,
                address(mockOracle)
            )
        );
        lazyArb = LazyArb(payable(address(proxy)));

        connector = new CurveConnector(DAI, CurvePool, CurveLP);

        vm.stopPrank();
    }

    function depositETH(uint256 depositAmount) public returns (bool) {
        return lazyArb.depositETH{value: depositAmount}();
    }

    function testRedemptionRate() public {
        mockOracle.setRedemptionRate(1.0001e27);
        uint256 redemptionRate = lazyArb.redemptionRate();
        assertEq(redemptionRate, 1.0001e27);
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
        mockOracle.setRedemptionRate(0.998e27);
        lazyArb.lockETHAndGenerateDebt(8000 * 1e18, address(connector));
        vm.stopPrank();
    }

    function testRepayDebtAndFreeETH() public {
        startHoax(user);
        this.depositETH(10 ether);
        mockOracle.setRedemptionRate(0.998e27);
        lazyArb.lockETHAndGenerateDebt(8000 * 1e18, address(connector));

        skip(10 days);

        address[] memory connectors = new address[](1);
        connectors[0] = address(connector);
        lazyArb.repayDebtAndFreeETH(5 ether, 4450 * 1e18, connectors);

        vm.stopPrank();
    }

    function testLockETHAndDraw() public {
        startHoax(user);
        this.depositETH(10 ether);
        mockOracle.setRedemptionRate(1.002e27);
        lazyArb.lockETHAndDraw(address(connector));
        vm.stopPrank();
    }

    function testWipeAndFreeETH() public {
        startHoax(user);
        this.depositETH(10 ether);
        mockOracle.setRedemptionRate(1.002e27);
        lazyArb.lockETHAndDraw(address(connector));

        skip(10 days);

        address[] memory connectors = new address[](1);
        connectors[0] = address(connector);
        lazyArb.wipeAndFreeETH(5 ether, connectors);

        vm.stopPrank();
    }
}
