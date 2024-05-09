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

    }
}
