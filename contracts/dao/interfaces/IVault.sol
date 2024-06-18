pragma solidity ^0.8.10;

interface IVault {
    function allocateNewEmissions(uint16 id) external returns (uint256);
}