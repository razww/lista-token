pragma solidity ^0.8.10;

import "./CommonListaDistributor.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/INonfungiblePositionManager.sol";

contract ERC721LpListaDistributor is CommonListaDistributor, ReentrancyGuard {
    struct NFT {
        uint256 priceLower;
        uint256 priceUpper;
        uint128 liquidity;
    }
    mapping(address => mapping(uint256 => NFT)) public userNFTs;
    mapping(address => uint256[]) public userNFTIds;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
      * @dev Initialize contract
      * @param _admin admin address
      * @param _manager manager address
      * @param _lpToken lp token address
      */
    function initialize(
        address _admin,
        address _manager,
        address _vault,
        address _lpToken
    ) external initializer {
        require(_admin != address(0), "admin is the zero address");
        require(_manager != address(0), "manager is the zero address");
        require(_lpToken != address(0), "lp token is the zero address");
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
        _setupRole(VAULT, _vault);
        lpToken = _lpToken;
        vault = IVault(_vault);
        name = string.concat("Lista-", IERC20Metadata(_lpToken).name());
        symbol = string.concat("Lista LP ", IERC20Metadata(_lpToken).symbol(), " Distributor");
    }

    function deposit(uint256 tokenId) nonReentrant external {
        require(IERC721(lpToken).ownerOf(tokenId) == msg.sender, "Not owner of token");
        require(checkNFT(tokenId), "Invalid NFT");
        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = INonfungiblePositionManager(lpToken).positions(tokenId);
        _addNFT(msg.sender, tokenId, 0, 0, liquidity);
        _deposit(msg.sender, liquidity);
        IERC721(lpToken).safeTransferFrom(msg.sender, address(this), tokenId);
    }

    function withdraw(uint256 tokenId) nonReentrant external {
        uint256 amount = userNFTs[msg.sender][tokenId].liquidity;
        _removeNFT(msg.sender, tokenId);
        _withdraw(msg.sender, amount);
        IERC721(lpToken).safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function checkNFT(uint256 tokenId) public view returns (bool) {
        return true;
    }

    function _addNFT(address _account, uint256 tokenId, uint256 priceLower, uint256 priceUpper, uint128 liquidity) internal {
        require(userNFTs[_account][tokenId].liquidity == 0, "NFT already added");
        userNFTs[_account][tokenId] = NFT(priceLower, priceUpper, liquidity);
        userNFTIds[_account].push(tokenId);
    }

    function _removeNFT(address _account, uint256 tokenId) internal {
        require(userNFTs[_account][tokenId].liquidity > 0, "NFT not added");
        delete userNFTs[_account][tokenId];
        uint256[] storage nftIds = userNFTIds[_account];
        for (uint256 i = 0; i < nftIds.length; i++) {
            if (nftIds[i] == tokenId) {
                nftIds[i] = nftIds[nftIds.length - 1];
                nftIds.pop();
                break;
            }
        }
    }
}