// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IOrderBook {
    function getSwapOrder(address _account, uint256 _orderIndex) external view returns (
        address path0, 
        address path1,
        address path2,
        uint256 amountIn,
        uint256 minOut,
        uint256 triggerRatio,
        bool triggerAboveThreshold,
        bool shouldUnwrap,
        uint256 executionFee
    );

    function getIncreaseOrder(address _account, uint256 _orderIndex) external view returns (
        address purchaseToken, 
        uint256 purchaseTokenAmount,
        address collateralToken,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee
    );

    function getDecreaseOrder(address _account, uint256 _orderIndex) external view returns (
        address collateralToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee
    );

    function executeSwapOrder(address, uint256, address payable) external;
    function executeDecreaseOrder(address, uint256, address payable) external;
    function executeIncreaseOrder(address, uint256, address payable) external;
}

contract MyContract {
    IOrderBook private orderBook;

    constructor(address _orderBook) {
        orderBook = IOrderBook(_orderBook);
    }

    function getSwapOrder(address _account, uint256 _orderIndex) external view returns (
        address, 
        address,
        address,
        uint256,
        uint256,
        uint256,
        bool,
        bool,
        uint256
    ) {
        return orderBook.getSwapOrder(_account, _orderIndex);
    }

    function getIncreaseOrder(address _account, uint256 _orderIndex) external view returns (
        address, 
        uint256,
        address,
        address,
        uint256,
        bool,
        uint256,
        bool,
        uint256
    ) {
        return orderBook.getIncreaseOrder(_account, _orderIndex);
    }

    function getDecreaseOrder(address _account, uint256 _orderIndex) external view returns (
        address,
        uint256,
        address,
        uint256,
        bool,
        uint256,
        bool,
        uint256
    ) {
        return orderBook.getDecreaseOrder(_account, _orderIndex);
    }

    function executeSwapOrder(address _account, uint256 _orderIndex, address payable _receiver) external {
        orderBook.executeSwapOrder(_account, _orderIndex, _receiver);
    }

    function executeDecreaseOrder(address _account, uint256 _orderIndex, address payable _receiver) external {
        orderBook.executeDecreaseOrder(_account, _orderIndex, _receiver);
    }

    function executeIncreaseOrder(address _account, uint256 _orderIndex, address payable _receiver) external {
        orderBook.executeIncreaseOrder(_account, _orderIndex, _receiver);
    }
}
