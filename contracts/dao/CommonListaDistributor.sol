// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IVault.sol";

abstract contract CommonListaDistributor is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    event LPTokenDeposited(address indexed lpToken, address indexed receiver, uint256 amount);
    event LPTokenWithdrawn(address indexed lpToken, address indexed receiver, uint256 amount);
    event RewardClaimed(address indexed receiver, uint256 listaAmount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    address public lpToken;
    IVault public vault;
    string public name;
    string public symbol;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    uint256 public periodFinish;
    uint256 public lastUpdate;
    uint256 public rewardIntegral;
    uint256 public rewardRate;
    mapping(address => uint256) public rewardIntegralFor;
    mapping(address => uint256) private storedPendingReward;
    uint16 public emissionId;

    bytes32 public constant MANAGER = keccak256("MANAGER"); // manager role
    bytes32 public constant VAULT = keccak256("VAULT"); // vault role
    uint256 constant REWARD_DURATION = 1 weeks;

    function _deposit(address _account, uint256 amount) internal {
        uint256 balance = balanceOf[_account];
        uint256 supply = totalSupply;

        balanceOf[_account] = balance + amount;
        totalSupply = supply + amount;

        _updateReward(_account, balance, supply);
        if (block.timestamp / 1 weeks >= periodFinish / 1 weeks) _fetchRewards();

        emit Transfer(address(0), _account, amount);
        emit LPTokenDeposited(address(lpToken), _account, amount);
    }

    function _withdraw(address _account, uint256 amount) internal {
        uint256 balance = balanceOf[_account];
        uint256 supply = totalSupply;
        balanceOf[_account] = balance - amount;
        totalSupply = supply - amount;

        _updateReward(_account, balance, supply);
        if (block.timestamp / 1 weeks >= periodFinish / 1 weeks) _fetchRewards();

        emit Transfer(_account, address(0), amount);
        emit LPTokenWithdrawn(address(lpToken), _account, amount);
    }

    function _updateReward(address _account, uint256 balance, uint256 supply) internal {
        // update reward
        uint256 updated = periodFinish;
        if (updated > block.timestamp) updated = block.timestamp;
        uint256 duration = updated - lastUpdate;
        if (duration > 0) lastUpdate = uint32(updated);

        if (duration > 0 && supply > 0) {
            rewardIntegral += (duration * rewardRate * 1e18) / supply;
        }
        if (_account != address(0)) {
            uint256 integralFor = rewardIntegralFor[_account];
            if (rewardIntegral > integralFor) {
                storedPendingReward[_account] += uint128((balance * (rewardIntegral - integralFor)) / 1e18);
                rewardIntegralFor[_account] = rewardIntegral;
            }
        }
    }

    function earned(address account) public view returns (uint256) {
        uint256 balance = balanceOf[account];
        uint256 updated = periodFinish;
        if (updated > block.timestamp) updated = block.timestamp;
        uint256 duration = updated - lastUpdate;

        uint256 _rewardIntegral = rewardIntegral;
        if (duration > 0 && totalSupply > 0) {
            _rewardIntegral += (duration * rewardRate * 1e18) / totalSupply;
        }

        uint256 amount = storedPendingReward[account];

        uint256 integralFor = rewardIntegralFor[account];
        if (totalSupply > integralFor) {
            amount += uint128((balance * (totalSupply - integralFor)) / 1e18);
        }

        return amount;
    }

    function vaultClaimReward(address _account) onlyRole(VAULT) external returns (uint256) {
        _updateReward(_account, balanceOf[_account], totalSupply);
        uint256 amount = storedPendingReward[_account];
        delete storedPendingReward[_account];

        emit RewardClaimed(_account, amount);
        return amount;
    }

    function fetchRewards() external {
        require(block.timestamp / 1 weeks >= periodFinish / 1 weeks, "Can only fetch once per week");
        _updateReward(address(0), 0, totalSupply);
        _fetchRewards();
    }

    function _fetchRewards() internal {
        uint256 amount;
        uint16 id = emissionId;
        if (id > 0) {
            amount = vault.allocateNewEmissions(id);
        }

        uint256 _periodFinish = periodFinish;
        if (block.timestamp < _periodFinish) {
            uint256 remaining = _periodFinish - block.timestamp;
            amount += remaining * rewardRate;
        }

        rewardRate = amount / REWARD_DURATION;

        lastUpdate = block.timestamp;
        periodFinish = block.timestamp + REWARD_DURATION;
    }

    function notifyRegisteredId(uint16 _emissionId) onlyRole(VAULT) external returns (bool) {
        require(emissionId == 0, "Already registered");
        require(_emissionId > 0, "Invalid emission id");
        emissionId = _emissionId;
        return true;
    }
}