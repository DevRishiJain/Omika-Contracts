// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IShortsTracker {
    function isGlobalShortDataReady() external view returns (bool);
    function globalShortAveragePrices(address _token) external view returns (uint256);
    function getNextGlobalShortData(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        bool _isIncrease
    ) external view returns (uint256, uint256);
    function updateGlobalShortData(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _markPrice,
        bool _isIncrease
    ) external;
    function setIsGlobalShortDataReady(bool value) external;
    function setInitData(address[] calldata _tokens, uint256[] calldata _averagePrices) external;
}

contract MyContract {
    IShortsTracker private shortsTracker;

    constructor(address _shortsTracker, address[] memory _tokens, uint256[] memory _averagePrices) {
        shortsTracker = IShortsTracker(_shortsTracker);
        shortsTracker.setInitData(_tokens, _averagePrices);
    }

    function isGlobalShortDataReady() external view returns (bool) {
        return shortsTracker.isGlobalShortDataReady();
    }

    function globalShortAveragePrices(address _token) external view returns (uint256) {
        return shortsTracker.globalShortAveragePrices(_token);
    }

    function getNextGlobalShortData(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        bool _isIncrease
    ) external view returns (uint256, uint256) {
        return shortsTracker.getNextGlobalShortData(
            _account,
            _collateralToken,
            _indexToken,
            _nextPrice,
            _sizeDelta,
            _isIncrease
        );
    }

    function updateGlobalShortData(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _markPrice,
        bool _isIncrease
    ) external {
        shortsTracker.updateGlobalShortData(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            _sizeDelta,
            _markPrice,
            _isIncrease
        );
    }

    function setIsGlobalShortDataReady(bool value) external {
        shortsTracker.setIsGlobalShortDataReady(value);
    }
}
