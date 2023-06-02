// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPositionRouterCallbackReceiver {
    function gmxPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease) external;
}

contract MyContract {
    IPositionRouterCallbackReceiver private callbackReceiver;

    constructor(address _callbackReceiver) {
        callbackReceiver = IPositionRouterCallbackReceiver(_callbackReceiver);
    }

    function invokeGmxPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease) external {
        callbackReceiver.gmxPositionCallback(positionKey, isExecuted, isIncrease);
    }
}
