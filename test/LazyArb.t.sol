// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../src/LazyArb.sol";
import "../src/LazyArbFactory.sol";
import "../src/connectors/CurveConnector.sol";
import "../src/mock/MockOracle.sol";

contract LazyArbTest is Test {
    LazyArb public implementation;
    UpgradeableBeacon public beacon;
    LazyArbFactory public factory;
    LazyArb public lazyArb;
    CurveConnector public connector;
    MockOracle public mockOracle;

    address public user = address(0x1);
    address public keeper = address(0x2);
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

    SAFEEngineLike public safeEngine;

    function setUp() public {
        startHoax(user);

        mockOracle = new MockOracle(oracle);
        mockOracle.setRedemptionRate(1e27);

        implementation = new LazyArb();
        beacon = new UpgradeableBeacon(address(implementation));
        factory = new LazyArbFactory(
            address(beacon),
            safeManager,
            taxCollector,
            ethJoin,
            coinJoin,
            dai_manager,
            dai_jug,
            dai_ethJoin,
            dai_daiJoin,
            address(mockOracle)
        );
        lazyArb = LazyArb(payable(factory.createLazyArb(500, 600)));

        connector = new CurveConnector(DAI, CurvePool, CurveLP);

        safeEngine = SAFEEngineLike(ManagerLike(safeManager).safeEngine());

        vm.stopPrank();
    }

    function depositETH(address caller, uint256 depositAmount) public returns (bool success) {
        hoax(caller);
        (success, ) = address(lazyArb).call{value: depositAmount}("");
    }

    function short(address caller, uint256 depositAmount) public {
        depositETH(caller, depositAmount);
        startHoax(caller);
        mockOracle.setRedemptionRate(0.998e27);
        lazyArb.lockETHAndGenerateDebt(8000 * 1e18, address(connector));
        vm.stopPrank();
    }

    function long(address caller, uint256 depositAmount) public {
        depositETH(caller, depositAmount);
        startHoax(caller);
        mockOracle.setRedemptionRate(1.002e27);
        lazyArb.lockETHAndDraw(address(connector));
        vm.stopPrank();
    }

    function testRedemptionRate() public {
        mockOracle.setRedemptionRate(1.0001e27);
        uint256 redemptionRate = lazyArb.redemptionRate();
        assertEq(redemptionRate, 1.0001e27);
    }

    function testDepositETH() public {
        uint256 depositAmount = 30 ether;
        assertTrue(depositETH(user, depositAmount));
        assertEq(address(lazyArb).balance, depositAmount);
    }

    function testLockETHAndGenerateDebt_fail_nonOwner() public {
        depositETH(user, 30 ether);
        startHoax(keeper);
        mockOracle.setRedemptionRate(0.998e27);
        vm.expectRevert("LazyArb/not-owner");
        lazyArb.lockETHAndGenerateDebt(8000 * 1e18, address(connector));
        vm.stopPrank();
    }

    function testLockETHAndGenerateDebt() public {
        depositETH(user, 30 ether);
        startHoax(user);
        mockOracle.setRedemptionRate(0.998e27);
        lazyArb.lockETHAndGenerateDebt(8000 * 1e18, address(connector));
        vm.stopPrank();

        assertEq(address(lazyArb).balance, 0);
        assertEq(uint8(lazyArb.status()), uint8(LazyArb.Status.Short));

        address safeHandler = ManagerLike(safeManager).safes(lazyArb.safe());
        bytes32 collateralType = ManagerLike(safeManager).collateralTypes(lazyArb.safe());
        (uint256 depositedCollateralToken, uint256 generatedDebt) = safeEngine.safes(collateralType, safeHandler);
        assertEq(depositedCollateralToken, 30 ether);
        assertGt(generatedDebt, 0);
    }

    function testRebalanceShort_not_short() public {
        startHoax(keeper);
        vm.expectRevert("LazyArb/status-not-short");
        lazyArb.rebalanceShort(0, address(connector));
        vm.stopPrank();
    }

    function testRebalanceShort_cRatio_in_range() public {
        this.short(user, 30 ether);

        startHoax(keeper);
        vm.expectRevert("LazyArb/cRatio-in-range");
        lazyArb.rebalanceShort(0, address(connector));
        vm.stopPrank();
    }

    function testRebalanceShort_cRatio_below_range() public {
        this.short(user, 30 ether);

        hoax(user);
        lazyArb.setCRatio(600, 700);

        startHoax(keeper);
        lazyArb.rebalanceShort(0, address(connector));
        vm.stopPrank();

        assertEq(address(lazyArb).balance, 0);
        assertEq(uint8(lazyArb.status()), uint8(LazyArb.Status.Short));

        address safeHandler = ManagerLike(safeManager).safes(lazyArb.safe());
        bytes32 collateralType = ManagerLike(safeManager).collateralTypes(lazyArb.safe());
        (uint256 depositedCollateralToken, uint256 generatedDebt) = safeEngine.safes(collateralType, safeHandler);
        assertEq(depositedCollateralToken, 30 ether);
        assertGt(generatedDebt, 0);
    }

    function testRebalanceShort_cRatio_above_range() public {
        this.short(user, 30 ether);

        hoax(user);
        lazyArb.setCRatio(400, 500);

        startHoax(keeper);
        lazyArb.rebalanceShort(0, address(connector));
        vm.stopPrank();

        assertEq(address(lazyArb).balance, 0);
        assertEq(uint8(lazyArb.status()), uint8(LazyArb.Status.Short));

        address safeHandler = ManagerLike(safeManager).safes(lazyArb.safe());
        bytes32 collateralType = ManagerLike(safeManager).collateralTypes(lazyArb.safe());
        (uint256 depositedCollateralToken, uint256 generatedDebt) = safeEngine.safes(collateralType, safeHandler);
        assertEq(depositedCollateralToken, 30 ether);
        assertGt(generatedDebt, 0);
    }

    function testRepayDebtAndFreeETH_fail_nonOwner() public {
        depositETH(user, 30 ether);
        startHoax(user);
        mockOracle.setRedemptionRate(0.998e27);
        lazyArb.lockETHAndGenerateDebt(8000 * 1e18, address(connector));
        vm.stopPrank();

        skip(10 days);

        startHoax(keeper);
        address[] memory connectors = new address[](1);
        connectors[0] = address(connector);
        vm.expectRevert("LazyArb/not-owner");
        lazyArb.repayDebtAndFreeETH(4450 * 1e18, connectors);

        vm.stopPrank();
    }

    function testRepayDebtAndFreeETH() public {
        depositETH(user, 30 ether);
        startHoax(user);
        mockOracle.setRedemptionRate(0.998e27);
        lazyArb.lockETHAndGenerateDebt(8000 * 1e18, address(connector));

        skip(10 days);

        address[] memory connectors = new address[](1);
        connectors[0] = address(connector);
        lazyArb.repayDebtAndFreeETH(4450 * 1e18, connectors);

        vm.stopPrank();

        assertApproxEqAbs(address(lazyArb).balance, 30 ether, 0.1 ether);
        assertEq(uint8(lazyArb.status()), uint8(LazyArb.Status.None));

        address safeHandler = ManagerLike(safeManager).safes(lazyArb.safe());
        bytes32 collateralType = ManagerLike(safeManager).collateralTypes(lazyArb.safe());
        (uint256 depositedCollateralToken, uint256 generatedDebt) = safeEngine.safes(collateralType, safeHandler);
        assertEq(depositedCollateralToken, 0);
        assertEq(generatedDebt, 0);
    }

    function testLockETHAndDraw_fail_nonOwner() public {
        depositETH(user, 30 ether);
        startHoax(keeper);
        mockOracle.setRedemptionRate(1.002e27);
        vm.expectRevert("LazyArb/not-owner");
        lazyArb.lockETHAndDraw(address(connector));
        vm.stopPrank();
    }

    function testLockETHAndDraw() public {
        depositETH(user, 30 ether);
        startHoax(user);
        mockOracle.setRedemptionRate(1.002e27);
        lazyArb.lockETHAndDraw(address(connector));
        vm.stopPrank();

        assertEq(address(lazyArb).balance, 0);
        assertEq(uint8(lazyArb.status()), uint8(LazyArb.Status.Long));

        DaiManagerLike daiManager = DaiManagerLike(dai_manager);
        address urn = daiManager.urns(lazyArb.cdp());
        bytes32 ilk = daiManager.ilks(lazyArb.cdp());
        (uint256 depositedCollateral, uint256 art) = VatLike(daiManager.vat()).urns(ilk, urn);
        assertEq(depositedCollateral, 30 ether);
        assertGt(art, 0);
    }

    function testWipeAndFreeETH_fail_nonOwner() public {
        depositETH(user, 30 ether);
        startHoax(user);
        mockOracle.setRedemptionRate(1.002e27);
        lazyArb.lockETHAndDraw(address(connector));
        vm.stopPrank();

        skip(10 days);

        startHoax(keeper);
        address[] memory connectors = new address[](1);
        connectors[0] = address(connector);
        vm.expectRevert("LazyArb/not-owner");
        lazyArb.wipeAndFreeETH(connectors);

        vm.stopPrank();
    }

    function testWipeAndFreeETH() public {
        depositETH(user, 30 ether);
        startHoax(user);
        mockOracle.setRedemptionRate(1.002e27);
        lazyArb.lockETHAndDraw(address(connector));

        skip(10 days);

        address[] memory connectors = new address[](1);
        connectors[0] = address(connector);
        lazyArb.wipeAndFreeETH(connectors);

        vm.stopPrank();

        assertApproxEqAbs(address(lazyArb).balance, 30 ether, 0.1 ether);
        assertEq(uint8(lazyArb.status()), uint8(LazyArb.Status.None));

        DaiManagerLike daiManager = DaiManagerLike(dai_manager);
        address urn = daiManager.urns(lazyArb.cdp());
        bytes32 ilk = daiManager.ilks(lazyArb.cdp());
        (uint256 depositedCollateral, uint256 art) = VatLike(daiManager.vat()).urns(ilk, urn);
        assertEq(depositedCollateral, 0);
        assertEq(art, 0);
    }

    function testRebalanceLong_not_long() public {
        startHoax(keeper);
        vm.expectRevert("LazyArb/status-not-long");
        lazyArb.rebalanceLong(address(connector));
        vm.stopPrank();
    }

    function testRebalanceLong_cRatio_in_range() public {
        this.long(user, 30 ether);

        startHoax(keeper);
        vm.expectRevert("LazyArb/cRatio-in-range");
        lazyArb.rebalanceLong(address(connector));
        vm.stopPrank();
    }

    function testRebalanceLong_cRatio_below_range() public {
        this.long(user, 30 ether);

        hoax(user);
        lazyArb.setCRatio(600, 700);

        startHoax(keeper);
        lazyArb.rebalanceLong(address(connector));
        vm.stopPrank();

        assertEq(address(lazyArb).balance, 0);
        assertEq(uint8(lazyArb.status()), uint8(LazyArb.Status.Long));

        DaiManagerLike daiManager = DaiManagerLike(dai_manager);
        address urn = daiManager.urns(lazyArb.cdp());
        bytes32 ilk = daiManager.ilks(lazyArb.cdp());
        (uint256 depositedCollateral, uint256 art) = VatLike(daiManager.vat()).urns(ilk, urn);
        assertEq(depositedCollateral, 30 ether);
        assertGt(art, 0);
    }

    function testRebalanceLong_cRatio_above_range() public {
        this.long(user, 30 ether);

        hoax(user);
        lazyArb.setCRatio(400, 500);

        startHoax(keeper);
        lazyArb.rebalanceLong(address(connector));
        vm.stopPrank();

        assertEq(address(lazyArb).balance, 0);
        assertEq(uint8(lazyArb.status()), uint8(LazyArb.Status.Long));

        DaiManagerLike daiManager = DaiManagerLike(dai_manager);
        address urn = daiManager.urns(lazyArb.cdp());
        bytes32 ilk = daiManager.ilks(lazyArb.cdp());
        (uint256 depositedCollateral, uint256 art) = VatLike(daiManager.vat()).urns(ilk, urn);
        assertEq(depositedCollateral, 30 ether);
        assertGt(art, 0);
    }

    function testFlip_fail_not_long() public {
        this.short(user, 30 ether);

        vm.expectRevert("LazyArb/status-not-long");
        hoax(user);
        address[] memory connectors = new address[](1);
        connectors[0] = address(connector);
        lazyArb.flip(0, connectors, address(connector));
    }

    function testFlip_fail_not_short() public {
        this.long(user, 30 ether);

        vm.expectRevert("LazyArb/status-not-short");
        hoax(user);
        address[] memory connectors = new address[](1);
        connectors[0] = address(connector);
        lazyArb.flip(0, connectors, address(connector));
    }

    function testFlip_success_long_to_short() public {
        this.long(user, 30 ether);

        startHoax(user);
        mockOracle.setRedemptionRate(0.998e27);
        address[] memory connectors = new address[](1);
        connectors[0] = address(connector);
        lazyArb.flip(0, connectors, address(connector));
        vm.stopPrank();

        assertEq(address(lazyArb).balance, 0);
        assertEq(uint8(lazyArb.status()), uint8(LazyArb.Status.Short));

        address safeHandler = ManagerLike(safeManager).safes(lazyArb.safe());
        bytes32 collateralType = ManagerLike(safeManager).collateralTypes(lazyArb.safe());
        (uint256 depositedCollateralToken, uint256 generatedDebt) = safeEngine.safes(collateralType, safeHandler);
        assertApproxEqAbs(depositedCollateralToken, 30 ether, 0.1 ether);
        assertGt(generatedDebt, 0);

        DaiManagerLike daiManager = DaiManagerLike(dai_manager);
        address urn = daiManager.urns(lazyArb.cdp());
        bytes32 ilk = daiManager.ilks(lazyArb.cdp());
        (uint256 depositedCollateral, uint256 art) = VatLike(daiManager.vat()).urns(ilk, urn);
        assertEq(depositedCollateral, 0);
        assertEq(art, 0);
    }

    function testFlip_success_short_to_long() public {
        this.short(user, 30 ether);

        startHoax(user);
        mockOracle.setRedemptionRate(1.002e27);
        address[] memory connectors = new address[](1);
        connectors[0] = address(connector);
        lazyArb.flip(0, connectors, address(connector));
        vm.stopPrank();

        assertEq(address(lazyArb).balance, 0);
        assertEq(uint8(lazyArb.status()), uint8(LazyArb.Status.Long));

        DaiManagerLike daiManager = DaiManagerLike(dai_manager);
        address urn = daiManager.urns(lazyArb.cdp());
        bytes32 ilk = daiManager.ilks(lazyArb.cdp());
        (uint256 depositedCollateral, uint256 art) = VatLike(daiManager.vat()).urns(ilk, urn);
        assertApproxEqAbs(depositedCollateral, 30 ether, 0.1 ether);
        assertGt(art, 0);

        address safeHandler = ManagerLike(safeManager).safes(lazyArb.safe());
        bytes32 collateralType = ManagerLike(safeManager).collateralTypes(lazyArb.safe());
        (uint256 depositedCollateralToken, uint256 generatedDebt) = safeEngine.safes(collateralType, safeHandler);
        assertEq(depositedCollateralToken, 0);
        assertEq(generatedDebt, 0);
    }
}
