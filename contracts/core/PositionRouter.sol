 // SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./interfaces/IRouter.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IPositionRouter.sol";
import "./interfaces/IPositionRouterCallbackReceiver.sol";

import "../libraries/utils/Address.sol";
import "../peripherals/interfaces/ITimelock.sol";
import "./BasePositionManager.sol";

contract PositionRouter is BasePositionManager, IPositionRouter {
    using Address for address;

    struct IncreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 amountIn;
        uint256 minOut;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
        bool hasCollateralInETH;
        address callbackTarget;
    }

    struct DecreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        address receiver;
        uint256 acceptablePrice;
        uint256 minOut;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
        bool withdrawETH;
        address callbackTarget;
    }

    uint256 public minExecutionFee;

    uint256 public minBlockDelayKeeper;
    uint256 public minTimeDelayPublic;
    uint256 public maxTimeDelay;

    bool public isLeverageEnabled = true;

    bytes32[] public override increasePositionRequestKeys;
    bytes32[] public override decreasePositionRequestKeys;

    uint256 public override increasePositionRequestKeysStart;
    uint256 public override decreasePositionRequestKeysStart;

    uint256 public callbackGasLimit;
    mapping (address => uint256) public customCallbackGasLimits;

    mapping (address => bool) public isPositionKeeper;

    mapping (address => uint256) public increasePositionsIndex;
    mapping (bytes32 => IncreasePositionRequest) public increasePositionRequests;

    mapping (address => uint256) public decreasePositionsIndex;
    mapping (bytes32 => DecreasePositionRequest) public decreasePositionRequests;

    event CreateIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 index,
        uint256 queueIndex,
        uint256 blockNumber,
        uint256 blockTime,
        uint256 gasPrice
    );

    event ExecuteIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CancelIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CreateDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        uint256 index,
        uint256 queueIndex,
        uint256 blockNumber,
        uint256 blockTime,
        uint256 gasPrice
    );

    event ExecuteDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CancelDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event SetMinExecutionFee(
        uint256 oldMinExecutionFee,
        uint256 newMinExecutionFee
    );

    event SetDelayValues(
        uint256 oldMinBlockDelayKeeper,
        uint256 oldMinTimeDelayPublic,
        uint256 oldMaxTimeDelay,
        uint256 newMinBlockDelayKeeper,
        uint256 newMinTimeDelayPublic,
        uint256 newMaxTimeDelay
    );

    event SetRequestKeysStartValues(
        uint256 oldIncreasePositionRequestKeysStart,
        uint256 oldDecreasePositionRequestKeysStart,
        uint256 newIncreasePositionRequestKeysStart,
        uint256 newDecreasePositionRequestKeysStart
    );

    event SetIsLeverageEnabled(
        bool oldIsLeverageEnabled,
        bool newIsLeverageEnabled
    );

    event SetCallbackGasLimit(
        uint256 oldCallbackGasLimit,
        uint256 newCallbackGasLimit
    );

    event SetCustomCallbackGasLimit(
        address indexed callbackTarget,
        uint256 oldCallbackGasLimit,
        uint256 newCallbackGasLimit
    );

    event SetPositionKeeper(
        address indexed positionKeeper,
        bool isActive
    );

    constructor(
        address _router,
        address _vault,
        address _indexToken,
        uint256 _leverageAmount,
        uint256 _minExecutionFee,
        uint256 _minBlockDelayKeeper,
        uint256 _minTimeDelayPublic,
        uint256 _maxTimeDelay,
        uint256 _increasePositionRequestKeysStart,
        uint256 _decreasePositionRequestKeysStart,
        uint256 _callbackGasLimit
    )
        public
        BasePositionManager(
            _router,
            _vault,
            _indexToken,
            _leverageAmount
        )
    {
        minExecutionFee = _minExecutionFee;
        minBlockDelayKeeper = _minBlockDelayKeeper;
        minTimeDelayPublic = _minTimeDelayPublic;
        maxTimeDelay = _maxTimeDelay;
        increasePositionRequestKeysStart = _increasePositionRequestKeysStart;
        decreasePositionRequestKeysStart = _decreasePositionRequestKeysStart;
        callbackGasLimit = _callbackGasLimit;
    }

    function setPositionKeeper(address positionKeeper, bool isActive)
        external
        onlyRouter
    {
        isPositionKeeper[positionKeeper] = isActive;
        emit SetPositionKeeper(positionKeeper, isActive);
    }

    function setCallbackGasLimit(uint256 newCallbackGasLimit)
        external
        onlyRouter
    {
        emit SetCallbackGasLimit(callbackGasLimit, newCallbackGasLimit);
        callbackGasLimit = newCallbackGasLimit;
    }

    function setCustomCallbackGasLimit(address callbackTarget, uint256 newCallbackGasLimit)
        external
        onlyRouter
    {
        uint256 oldCallbackGasLimit = customCallbackGasLimits[callbackTarget];
        emit SetCustomCallbackGasLimit(callbackTarget, oldCallbackGasLimit, newCallbackGasLimit);
        customCallbackGasLimits[callbackTarget] = newCallbackGasLimit;
    }

    function setMinExecutionFee(uint256 newMinExecutionFee) external onlyRouter {
        emit SetMinExecutionFee(minExecutionFee, newMinExecutionFee);
        minExecutionFee = newMinExecutionFee;
    }

    function setDelayValues(
        uint256 newMinBlockDelayKeeper,
        uint256 newMinTimeDelayPublic,
        uint256 newMaxTimeDelay
    )
        external
        onlyRouter
    {
        emit SetDelayValues(
            minBlockDelayKeeper,
            minTimeDelayPublic,
            maxTimeDelay,
            newMinBlockDelayKeeper,
            newMinTimeDelayPublic,
            newMaxTimeDelay
        );
        minBlockDelayKeeper = newMinBlockDelayKeeper;
        minTimeDelayPublic = newMinTimeDelayPublic;
        maxTimeDelay = newMaxTimeDelay;
    }

    function setRequestKeysStartValues(
        uint256 newIncreasePositionRequestKeysStart,
        uint256 newDecreasePositionRequestKeysStart
    )
        external
        onlyRouter
    {
        emit SetRequestKeysStartValues(
            increasePositionRequestKeysStart,
            decreasePositionRequestKeysStart,
            newIncreasePositionRequestKeysStart,
            newDecreasePositionRequestKeysStart
        );
        increasePositionRequestKeysStart = newIncreasePositionRequestKeysStart;
        decreasePositionRequestKeysStart = newDecreasePositionRequestKeysStart;
    }

    function setIsLeverageEnabled(bool newIsLeverageEnabled) external onlyRouter {
        emit SetIsLeverageEnabled(isLeverageEnabled, newIsLeverageEnabled);
        isLeverageEnabled = newIsLeverageEnabled;
    }

    function createIncreasePosition(
        address[] memory path,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        address callbackTarget
    ) external override returns (bytes32) {
        require(isLeverageEnabled, "Leverage is disabled");
        require(path.length > 0, "Path not specified");
        require(sizeDelta > 0, "Invalid size delta");
        require(amountIn > 0, "Invalid amount in");
        require(minOut > 0, "Invalid min out");
        require(acceptablePrice > 0, "Invalid acceptable price");

        address account = msg.sender;
        bytes32 requestId = generateIncreasePositionRequestId();
        IncreasePositionRequest storage request = increasePositionRequests[requestId];

        request.account = account;
        request.path = path;
        request.indexToken = path[path.length - 1];
        request.amountIn = amountIn;
        request.minOut = minOut;
        request.sizeDelta = sizeDelta;
        request.isLong = isLong;
        request.acceptablePrice = acceptablePrice;
        request.executionFee = calculateExecutionFee(amountIn);
        request.blockNumber = block.number;
        request.blockTime = block.timestamp;
        request.hasCollateralInETH = hasCollateralInETH(path);
        request.callbackTarget = callbackTarget;

        increasePositionsIndex[account]++;

        emit CreateIncreasePosition(
            account,
            path,
            request.indexToken,
            amountIn,
            minOut,
            sizeDelta,
            isLong,
            acceptablePrice,
            request.executionFee,
            increasePositionsIndex[account],
            increasePositionRequestKeys.length,
            request.blockNumber,
            request.blockTime,
            tx.gasprice
        );

        increasePositionRequestKeys.push(requestId);

        return requestId;
    }

    function cancelIncreasePosition(bytes32 requestId) external override {
        IncreasePositionRequest storage request = increasePositionRequests[requestId];
        require(request.account == msg.sender, "Not the owner");
        require(requestId < increasePositionRequestKeys[increasePositionsIndex[request.account] - 1], "Invalid request ID");

        delete increasePositionRequests[requestId];
        emit CancelIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountIn,
            request.minOut,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.executionFee,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );
    }

    function createDecreasePosition(
        address[] memory path,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        address callbackTarget
    ) external override returns (bytes32) {
        require(path.length > 0, "Path not specified");
        require(sizeDelta > 0, "Invalid size delta");
        require(collateralDelta > 0, "Invalid collateral delta");
        require(acceptablePrice > 0, "Invalid acceptable price");
        require(receiver != address(0), "Invalid receiver");

        address account = msg.sender;
        bytes32 requestId = generateDecreasePositionRequestId();
        DecreasePositionRequest storage request = decreasePositionRequests[requestId];

        request.account = account;
        request.path = path;
        request.indexToken = path[path.length - 1];
        request.collateralDelta = collateralDelta;
        request.sizeDelta = sizeDelta;
        request.isLong = isLong;
        request.receiver = receiver;
        request.acceptablePrice = acceptablePrice;
        request.minOut = minOut;
        request.executionFee = calculateExecutionFee(collateralDelta);
        request.blockNumber = block.number;
        request.blockTime = block.timestamp;
        request.withdrawETH = hasCollateralInETH(path);
        request.callbackTarget = callbackTarget;

        decreasePositionsIndex[account]++;

        emit CreateDecreasePosition(
            account,
            path,
            request.indexToken,
            collateralDelta,
            sizeDelta,
            isLong,
            receiver,
            acceptablePrice,
            minOut,
            request.executionFee,
            decreasePositionsIndex[account],
            decreasePositionRequestKeys.length,
            request.blockNumber,
            request.blockTime,
            tx.gasprice
        );

        decreasePositionRequestKeys.push(requestId);

        return requestId;
    }

    function cancelDecreasePosition(bytes32 requestId) external override {
        DecreasePositionRequest storage request = decreasePositionRequests[requestId];
        require(request.account == msg.sender, "Not the owner");
        require(requestId < decreasePositionRequestKeys[decreasePositionsIndex[request.account] - 1], "Invalid request ID");

        delete decreasePositionRequests[requestId];
        emit CancelDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.minOut,
            request.executionFee,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );
    }

    function executeIncreasePosition(bytes32 requestId, uint256 deadline)
        external
        payable
        override
        returns (uint256 receivedAmount)
    {
        IncreasePositionRequest storage request = increasePositionRequests[requestId];
        require(request.account != address(0), "Request does not exist");
        require(request.amountIn > 0, "Amount in not specified");
        require(request.minOut > 0, "Min out not specified");
        require(request.sizeDelta > 0, "Size delta not specified");
        require(request.acceptablePrice > 0, "Acceptable price not specified");
        require(request.executionFee > 0, "Execution fee not specified");
        require(request.blockNumber > 0, "Block number not specified");
        require(request.blockTime > 0, "Block time not specified");
        require(block.number >= request.blockNumber.add(minBlockDelayKeeper), "Block delay not met");
        require(block.timestamp >= request.blockTime.add(minTimeDelayPublic), "Time delay not met");
        require(block.timestamp <= request.blockTime.add(maxTimeDelay), "Request expired");
        require(deadline >= block.timestamp, "Transaction deadline exceeded");
        require(msg.value >= request.executionFee, "Insufficient ETH");

        address account = request.account;
        address[] memory path = request.path;
        address indexToken = request.indexToken;
        uint256 amountIn = request.amountIn;
        uint256 minOut = request.minOut;
        uint256 sizeDelta = request.sizeDelta;
        bool isLong = request.isLong;
        uint256 acceptablePrice = request.acceptablePrice;
        uint256 executionFee = request.executionFee;
        bool hasCollateralInETH = request.hasCollateralInETH;
        address callbackTarget = request.callbackTarget;

        delete increasePositionRequests[requestId];

        receivedAmount = executeIncreasePositionInternal(
            account,
            path,
            indexToken,
            amountIn,
            minOut,
            sizeDelta,
            isLong,
            acceptablePrice,
            executionFee,
            hasCollateralInETH,
            callbackTarget
        );

        emit ExecuteIncreasePosition(
            account,
            path,
            indexToken,
            amountIn,
            minOut,
            sizeDelta,
            isLong,
            acceptablePrice,
            executionFee,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );

        return receivedAmount;
    }

    function executeDecreasePosition(bytes32 requestId, uint256 deadline)
        external
        payable
        override
        returns (uint256 receivedCollateral)
    {
        DecreasePositionRequest storage request = decreasePositionRequests[requestId];
        require(request.account != address(0), "Request does not exist");
        require(request.collateralDelta > 0, "Collateral delta not specified");
        require(request.sizeDelta > 0, "Size delta not specified");
        require(request.acceptablePrice > 0, "Acceptable price not specified");
        require(request.minOut > 0, "Min out not specified");
        require(request.executionFee > 0, "Execution fee not specified");
        require(request.blockNumber > 0, "Block number not specified");
        require(request.blockTime > 0, "Block time not specified");
        require(block.number >= request.blockNumber.add(minBlockDelayKeeper), "Block delay not met");
        require(block.timestamp >= request.blockTime.add(minTimeDelayPublic), "Time delay not met");
        require(block.timestamp <= request.blockTime.add(maxTimeDelay), "Request expired");
        require(deadline >= block.timestamp, "Transaction deadline exceeded");
        require(msg.value >= request.executionFee, "Insufficient ETH");

        address account = request.account;
        address[] memory path = request.path;
        address indexToken = request.indexToken;
        uint256 collateralDelta = request.collateralDelta;
        uint256 sizeDelta = request.sizeDelta;
        bool isLong = request.isLong;
        address receiver = request.receiver;
        uint256 acceptablePrice = request.acceptablePrice;
        uint256 minOut = request.minOut;
        uint256 executionFee = request.executionFee;
        bool withdrawETH = request.withdrawETH;
        address callbackTarget = request.callbackTarget;

        delete decreasePositionRequests[requestId];

        receivedCollateral = executeDecreasePositionInternal(
            account,
            path,
            indexToken,
            collateralDelta,
            sizeDelta,
            isLong,
            receiver,
            acceptablePrice,
            minOut,
            executionFee,
            withdrawETH,
            callbackTarget
        );

        emit ExecuteDecreasePosition(
            account,
            path,
            indexToken,
            collateralDelta,
            sizeDelta,
            isLong,
            receiver,
            acceptablePrice,
            minOut,
            executionFee,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );

        return receivedCollateral;
    }
}
