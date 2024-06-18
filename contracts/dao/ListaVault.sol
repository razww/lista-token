// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IDistributor.sol";
import "../interfaces/IVeLista.sol";

contract ListaVault is Initializable, AccessControlUpgradeable, ReentrancyGuard {
    event IncreasedAllocation(address indexed receiver, uint256 increasedAmount);

    using SafeERC20 for IERC20;

    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);
    event NewReceiverRegistered(address receiver, uint256 id);

    IERC20 public token;
    mapping(address => uint256) public allocated;
    mapping(uint16 => address) public idToReceiver;
    uint16[65535] public receiverUpdatedWeek;
    uint256[65535] public weeklyEmissions;
    uint256[65535][65535] public weeklyReceiverPercent;
    IVeLista public veLista;
    uint16 receiverId;

    bytes32 public constant MANAGER = keccak256("MANAGER"); // manager role

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
      * @dev Initialize contract
      * @param _admin admin address
      * @param _manager manager address
      * @param _token lista token address
      * @param _veLista veLista token address
      */
    function initialize(
        address _admin,
        address _manager,
        address _token,
        address _veLista
    ) public initializer {
        require(_admin != address(0), "admin is the zero address");
        require(_manager != address(0), "manager is the zero address");
        require(_token != address(0), "token is the zero address");
        require(_veLista != address(0), "veLista is the zero address");

        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
        token = IERC20(_token);
        veLista = IVeLista(_veLista);
    }

    function depositRewards(uint256 amount, uint16 week) onlyRole(MANAGER) external {
        require(amount > 0, "Amount must be greater than 0");
        require(week > veLista.getCurrentWeek(), "week must be greater than current week");

        weeklyEmissions[week] += amount;
        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    function registerReceiver(address receiver) external onlyRole(MANAGER) returns (uint16) {
        uint16 week = veLista.getCurrentWeek();
        ++receiverId;
        receiverUpdatedWeek[receiverId] = week;
        idToReceiver[receiverId] = receiver;
        require(IDistributor(receiver).notifyRegisteredId(receiverId), "Receiver registration failed");
        emit NewReceiverRegistered(receiver, receiverId);
        return receiverId;
    }

    function setWeeklyReceiverPercent(uint16 week, uint16[] memory ids, uint256[] memory percent) onlyRole(MANAGER) external {
        require(week > veLista.getCurrentWeek(), "week must be greater than current week");
        uint256 totalPercent;

        if (weeklyReceiverPercent[week][0] == 1) {
            // this week has set, reset last receiver percent
            for (uint16 i = 1; i <= receiverId; ++i) {
                weeklyReceiverPercent[week][i] = 0;
            }
        }
        for (uint16 i = 0; i < ids.length; ++i) {
            require(idToReceiver[ids[i]] != address(0), "Receiver not registered");
            weeklyReceiverPercent[week][ids[i]] = percent[i];
            totalPercent += percent[i];
        }

        // mark this week set flag
        weeklyReceiverPercent[week][0] = 1;
        require(totalPercent <= 1e18, "Total percent must be less than or equal to 1e18");
    }

    function batchClaimRewards(IDistributor[] memory _distributors) nonReentrant external {
        uint256 total;
        for (uint16 i = 0; i < _distributors.length; ++i) {
            uint256 amount = _distributors[i].vaultClaimReward(msg.sender);
            require(allocated[address(_distributors[i])] >= amount, "Insufficient allocated balance");
            allocated[address(_distributors[i])] -= amount;
            total += amount;
        }
        token.safeTransfer(msg.sender, total);
    }

    function allocateNewEmissions(uint16 id) external returns (uint256) {
        address distributor = idToReceiver[id];
        require(distributor == msg.sender, "Distributor not registered");

        uint16 week = receiverUpdatedWeek[id];
        uint256 currentWeek = veLista.getCurrentWeek();
        if (week == currentWeek) return 0;

        uint256 amount;
        while (week < currentWeek) {
            ++week;
            amount += getReceiverWeeklyEmissions(id, week);
        }

        receiverUpdatedWeek[id] = uint16(currentWeek);
        allocated[msg.sender] += amount;
        require(allocated[msg.sender] <= weeklyEmissions[currentWeek], "Insufficient weekly emission");
        emit IncreasedAllocation(msg.sender, amount);
        return amount;
    }

    function getReceiverWeeklyEmissions(uint16 id, uint16 week) public view returns (uint256) {
        uint256 pct = weeklyReceiverPercent[week][id];
        return (weeklyEmissions[week] * pct) / 1e18;
    }
}