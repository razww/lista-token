// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVeLista.sol";

import "./MerkleVerifier.sol";

contract SlisBnbDistributor is Initializable, AccessControlUpgradeable {
    address public veLista; // veLista
    address public vault; // Lista vault

    uint16 private emissionId;

    mapping(uint16 => Epoch) public merkleRoots; // week => merkle root
    mapping(uint16 => mapping(address => bool)) public claimed; // week => account => claimed

    struct Epoch {
        bytes32 merkleRoot;
        bool claimed; // check if we need this
    }

    event SetMerkleRoot(uint16 week, bytes32 merkleRoot);
    event Claimed(address account, uint256 amount, uint16 week);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @param _token Address of veLista token
     * @param _vault Address of Lista vault
     * @param reclaimDelay Delay in seconds after contract creation for reclaiming unclaimed tokens
     */
    function initialize(address _token, address _vault, uint256 reclaimDelay, address _admin) external initializer {
        require(_token != address(0) && _vault != address(0), "Invalid address");

        veLista = _token;
        vault = _vault;
        reclaimPeriod = block.timestamp + reclaimDelay;
         _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @dev Set merkle root for rewards epoch. Merkle root can only be updated before the epoch starts.
     */
    function setMerkleRoot(uint16 _week, bytes32 _merkleRoot) external onlyRole(DEFAULT_ADMIN_ROLE)  {
        require(_week < IVeLista(veLista).getCurrentWeek(), "Can only set merkle root for past weeks");
        require(!merkleRoots[_week].claimed, "Should not update merkle root for claimed week");

        merkleRoots[_week].merkleRoot = _merkleRoot;
        emit SetMerkleRoot(_week, _merkleRoot);
    }

    /**
     * @dev Claim veLista rewards. Can be called by anyone as long as proof is valid. Rewards are available after the rewards epoch(week) ends.
     * @param week Week of the rewards epoch
     * @param account Address of the recipient
     * @param balance User's slisBnb balance
     * @param proof Merkle proof of the claim
     */
    function claim(
        uint16 week,
        address account,
        uint256 ratio,
        bytes32[] memory proof
    ) external {
        require(week < IVeLista(veLista).getCurrentWeek(), "Unable to claim yet");
        require(!claimed[week][account], "Airdrop already claimed");
        bytes32 leaf = keccak256(abi.encode(block.chainid, week, account, amount));
        MerkleVerifier._verifyProof(leaf, merkleRoots[week].merkleRoot, proof);
        claimed[week][account] = true;
        if (!merkleRoots[week].claimed) {
            merkleRoots[week].claimed = true;
        }
        if (getWeek(block.timestamp) >= getWeek(periodFinish)) {
            vault.allocateNewEmissions(emissionId);
        }

        uint256 amount = ratio * vault.getReceiverWeeklyEmissions(emissionId, week);
        vault.transferAllocatedTokens(emissionId, account, amount);

        emit Claimed(account, amount, week);
    }

    function notifyRegisteredId(uint16 _emissionId) onlyRole(VAULT) external returns (bool) {
        require(emissionId == 0, "Already registered");
        require(_emissionId > 0, "Invalid emission id");
        emissionId = _emissionId;
        return true;
    }
}
