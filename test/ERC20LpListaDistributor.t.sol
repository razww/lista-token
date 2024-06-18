// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../contracts/VeLista.sol";
import "../contracts/ListaToken.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../contracts/dao/ERC20LpListaDistributor.sol";
import "../contracts/dao/ListaVault.sol";
import "../contracts/mock/MockERC20.sol";

contract ERC20LpListaDistributorTest is Test {
    VeLista public veLista = VeLista(0x51075B00313292db08f3450f91fCA53Db6Bd0D11);
    ListaToken public lista = ListaToken(0x1d6d362f3b2034D9da97F0d1BE9Ff831B7CC71EB);
    ProxyAdmin public proxyAdmin = ProxyAdmin(0xc78f64Cd367bD7d2922088669463FCEE33f50b7c);
    uint256 MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    ListaVault listaVault;
    MockERC20 lpToken;
    ERC20LpListaDistributor erc20Distributor;

    address manager = 0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232;
    address user1 = 0x5a97ba0b0B18a618966303371374EBad4960B7D9;
    address user2 = 0x245b3Ee7fCC57AcAe8c208A563F54d630B5C4eD7;

    address proxyAdminOwner = 0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06;

    function setUp() public {
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        vm.startPrank(manager);
        lpToken = new MockERC20(manager, "LisUSD-BNB lp", "LisUSD-BNB lp");
        lpToken.mint(manager, 1_000_000_000 ether);
        vm.stopPrank();

        vm.startPrank(proxyAdminOwner);
        ListaVault listaVaultLogic = new ListaVault();
        TransparentUpgradeableProxy listaVaultProxy = new TransparentUpgradeableProxy(
            address(listaVaultLogic),
            proxyAdminOwner,
            abi.encodeWithSignature("initialize(address,address,address,address)", manager, manager, address(lista), address(veLista))
        );
        listaVault = ListaVault(address(listaVaultProxy));

        ERC20LpListaDistributor distributorLogic = new ERC20LpListaDistributor();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributorLogic),
            proxyAdminOwner,
            abi.encodeWithSignature("initialize(address,address,address,address)", manager, manager, address(listaVault), address(lpToken))
        );
        erc20Distributor = ERC20LpListaDistributor(address(proxy));
        vm.stopPrank();

        vm.prank(user1);
        lpToken.approve(address(erc20Distributor), MAX_UINT);

        vm.prank(user2);
        lpToken.approve(address(erc20Distributor), MAX_UINT);
    }

    function test_depositRewards() public {
        uint16 currentWeek = veLista.getCurrentWeek();
        vm.startPrank(manager);
        lista.approve(address(listaVault), MAX_UINT);
        listaVault.depositRewards(100 ether, currentWeek+1);
        listaVault.depositRewards(200 ether, currentWeek+2);
        vm.stopPrank();

        uint256 week1Emission = listaVault.weeklyEmissions(currentWeek+1);
        uint256 week2Emission = listaVault.weeklyEmissions(currentWeek+2);
        assertEq(week1Emission, 100 ether);
        assertEq(week2Emission, 200 ether);
    }

    function test_registerReceiver() public {
        vm.startPrank(manager);
        uint16 id = listaVault.registerReceiver(address(erc20Distributor));
        vm.stopPrank();

        assertEq(listaVault.idToReceiver(id), address(erc20Distributor), "register receiver failed");
        assertEq(erc20Distributor.emissionId(), id, "register receiver id error");
    }

    function test_setWeeklyReceiverPercent() public {
        uint16 currentWeek = veLista.getCurrentWeek();
        vm.startPrank(manager);
        uint16 id = listaVault.registerReceiver(address(erc20Distributor));
        uint16[] memory ids = new uint16[](1);
        ids[0] = id;
        uint256[] memory percents = new uint256[](1);
        percents[0] = 1e18;
        listaVault.setWeeklyReceiverPercent(currentWeek+1, ids, percents);

        lista.approve(address(listaVault), MAX_UINT);
        listaVault.depositRewards(100 ether, currentWeek+1);
        vm.stopPrank();

        assertEq(listaVault.weeklyReceiverPercent(currentWeek+1, 0), 1, "set weekly receiver percent failed");
        assertEq(listaVault.weeklyReceiverPercent(currentWeek+1, id),  1e18, "set weekly receiver percent failed");
        assertEq(listaVault.getReceiverWeeklyEmissions(id, currentWeek+1), 100 ether, "get receiver weekly emissions error");
    }

    function test_deposit() public {
        vm.startPrank(manager);
        lpToken.transfer(user1, 10000 ether);
        lpToken.transfer(user2, 10000 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        erc20Distributor.deposit(100 ether);
        vm.stopPrank();

        uint256 balance = erc20Distributor.balanceOf(user1);
        uint256 totalSupply = erc20Distributor.totalSupply();
        assertEq(balance, 100 ether, "user1 balance error");
        assertEq(totalSupply, 100 ether, "total supply error");
    }

    function test_withdraw() public {
        vm.startPrank(manager);
        lpToken.transfer(user1, 10000 ether);
        lpToken.transfer(user2, 10000 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        erc20Distributor.deposit(100 ether);
        erc20Distributor.withdraw(10 ether);
        vm.stopPrank();

        uint256 balance = erc20Distributor.balanceOf(user1);
        uint256 totalSupply = erc20Distributor.totalSupply();
        uint256 lpBalance = lpToken.balanceOf(user1);
        assertEq(balance, 90 ether, "user1 balance error");
        assertEq(totalSupply, 90 ether, "total supply error");
        assertEq(lpBalance, 10000 ether - 90 ether, "lp balance error");
    }

    function test_fetchRewards() public {
        uint16 currentWeek = veLista.getCurrentWeek();
        uint256 weekAmount = 700 ether;
        vm.startPrank(manager);

        lista.approve(address(listaVault), MAX_UINT);
        listaVault.depositRewards(weekAmount, currentWeek+1);

        uint16 id = listaVault.registerReceiver(address(erc20Distributor));

        uint16[] memory ids = new uint16[](1);
        ids[0] = id;
        uint256[] memory percents = new uint256[](1);
        percents[0] = 1e18;
        listaVault.setWeeklyReceiverPercent(currentWeek+1, ids, percents);

        vm.stopPrank();

        skip(1 weeks);

        vm.startPrank(user1);
        erc20Distributor.fetchRewards();
        vm.stopPrank();

        uint256 rewardRate = erc20Distributor.rewardRate();
        assertEq(rewardRate, weekAmount / 1 weeks, "reward rate error");
    }

}
