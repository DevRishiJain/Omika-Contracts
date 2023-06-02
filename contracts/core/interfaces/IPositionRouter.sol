// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPositionRouter {
    function increasePositionRequestKeysStart() external view returns (uint256);
    function decreasePositionRequestKeysStart() external view returns (uint256);
    function increasePositionRequestKeys(uint256 index) external view returns (bytes32);
    function decreasePositionRequestKeys(uint256 index) external view returns (bytes32);
    function executeIncreasePositions(uint256 _count, address payable _executionFeeReceiver) external;
    function executeDecreasePositions(uint256 _count, address payable _executionFeeReceiver) external;
    function getRequestQueueLengths() external view returns (uint256, uint256, uint256, uint256);
    function getIncreasePositionRequestPath(bytes32 _key) external view returns (address[] memory);
    function getDecreasePositionRequestPath(bytes32 _key) external view returns (address[] memory);
}

contract MyContract {
    IPositionRouter private positionRouter;

    constructor(address _positionRouter) {
        positionRouter = IPositionRouter(_positionRouter);
    }

    function increasePositionRequestKeysStart() external view returns (uint256) {
        return positionRouter.increasePositionRequestKeysStart();
    }

    function decreasePositionRequestKeysStart() external view returns (uint256) {
        return positionRouter.decreasePositionRequestKeysStart();
    }

    function increasePositionRequestKeys(uint256 index) external view returns (bytes32) {
        return positionRouter.increasePositionRequestKeys(index);
    }

    function decreasePositionRequestKeys(uint256 index) external view returns (bytes32) {
        return positionRouter.decreasePositionRequestKeys(index);
    }

    function executeIncreasePositions(uint256 _count, address payable _executionFeeReceiver) external {
        positionRouter.executeIncreasePositions(_count, _executionFeeReceiver);
    }

    function executeDecreasePositions(uint256 _count, address payable _executionFeeReceiver) external {
        positionRouter.executeDecreasePositions(_count, _executionFeeReceiver);
    }

    function getRequestQueueLengths() external view returns (uint256, uint256, uint256, uint256) {
        return positionRouter.getRequestQueueLengths();
    }

    function getIncreasePositionRequestPath(bytes32 _key) external view returns (address[] memory) {
        return positionRouter.getIncreasePositionRequestPath(_key);
    }

    function getDecreasePositionRequestPath(bytes32 _key) external view returns (address[] memory) {
        return positionRouter.getDecreasePositionRequestPath(_key);
    }
}
