// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRouter {
    function addPlugin(address _plugin) external;
    function pluginTransfer(address _token, address _account, address _receiver, uint256 _amount) external;
    function pluginIncreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) external;
    function pluginDecreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) external returns (uint256);
    function swap(address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver) external;
}

contract MyContract {
    IRouter private router;

    constructor(address _router) {
        router = IRouter(_router);
    }

    function addPlugin(address _plugin) external {
        router.addPlugin(_plugin);
    }

    function pluginTransfer(address _token, address _account, address _receiver, uint256 _amount) external {
        router.pluginTransfer(_token, _account, _receiver, _amount);
    }

    function pluginIncreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) external {
        router.pluginIncreasePosition(_account, _collateralToken, _indexToken, _sizeDelta, _isLong);
    }

    function pluginDecreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) external returns (uint256) {
        return router.pluginDecreasePosition(_account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver);
    }

    function swap(address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver) external {
        router.swap(_path, _amountIn, _minOut, _receiver);
    }
}
