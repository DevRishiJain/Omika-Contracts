pragma solidity ^0.8.0;

interface IBasePositionManager {
    function maxGlobalLongSizes(address _token) external view returns (uint256);
    function maxGlobalShortSizes(address _token) external view returns (uint256);
}

contract MyContract {
    IBasePositionManager private positionManager;
    address private tokenAddress;

    constructor(address _positionManager, address _token) {
        positionManager = IBasePositionManager(_positionManager);
        tokenAddress = _token;
    }

    function getMaxGlobalLongSize() external view returns (uint256) {
        return positionManager.maxGlobalLongSizes(tokenAddress);
    }

    function getMaxGlobalShortSize() external view returns (uint256) {
        return positionManager.maxGlobalShortSizes(tokenAddress);
    }
}
