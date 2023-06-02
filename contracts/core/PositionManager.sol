// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IRouter.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IOrderBook.sol";

import "../peripherals/interfaces/ITimelock.sol";
import "./BasePositionManager.sol";

contract PositionManager is BasePositionManager {

    address public orderBook;
    bool public inLegacyMode;

    bool public shouldValidateIncreaseOrder = true;

    mapping (address => bool) public isOrderKeeper;
    mapping (address => bool) public isPartner;
    mapping (address => bool) public isLiquidator;

    event SetOrderKeeper(address indexed account, bool isActive);
    event SetLiquidator(address indexed account, bool isActive);
    event SetPartner(address account, bool isActive);
    event SetInLegacyMode(bool inLegacyMode);
    event SetShouldValidateIncreaseOrder(bool shouldValidateIncreaseOrder);

    modifier onlyOrderKeeper() {
        require(isOrderKeeper[msg.sender], "PositionManager: forbidden");
        _;
    }

    modifier onlyLiquidator() {
        require(isLiquidator[msg.sender], "PositionManager: forbidden");
        _;
    }

    modifier onlyPartnersOrLegacyMode() {
        require(isPartner[msg.sender] || inLegacyMode, "PositionManager: forbidden");
        _;
    }

    constructor(
        address _vault,
        address _router,
        address _shortsTracker,
        address _weth,
        uint256 _depositFee,
        address _orderBook
    ) BasePositionManager(_vault, _router, _shortsTracker, _weth, _depositFee) {
        orderBook = _orderBook;
    }

    function setOrderKeeper(address _account, bool _isActive) external onlyAdmin {
        isOrderKeeper[_account] = _isActive;
        emit SetOrderKeeper(_account, _isActive);
    }

    function setLiquidator(address _account, bool _isActive) external onlyAdmin {
        isLiquidator[_account] = _isActive;
        emit SetLiquidator(_account, _isActive);
    }

    function setPartner(address _account, bool _isActive) external onlyAdmin {
        isPartner[_account] = _isActive;
        emit SetPartner(_account, _isActive);
    }

    function setInLegacyMode(bool _inLegacyMode) external onlyAdmin {
        inLegacyMode = _inLegacyMode;
        emit SetInLegacyMode(_inLegacyMode);
    }

    function setShouldValidateIncreaseOrder(bool _shouldValidateIncreaseOrder) external onlyAdmin {
        shouldValidateIncreaseOrder = _shouldValidateIncreaseOrder;
        emit SetShouldValidateIncreaseOrder(_shouldValidateIncreaseOrder);
    }

    function increasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    ) external nonReentrant onlyPartnersOrLegacyMode {
        require(_path.length == 1 || _path.length == 2, "PositionManager: invalid _path.length");

        if (_amountIn > 0) {
            if (_path.length == 1) {
                IRouter(router).pluginTransfer(_path[0], msg.sender, address(this), _amountIn);
            } else {
                IRouter(router).pluginTransfer(_path[0], msg.sender, vault, _amountIn);
                _amountIn = _amountIn.sub(_getVaultFee(_amountIn));
                IRouter(router).pluginTransfer(_path[1], msg.sender, vault, _getVaultFee(_amountIn));
            }
        }

        require(_amountIn >= minOrderValue, "PositionManager: insufficient amountIn");

        address pair = _path.length == 1 ? _getPair(_path[0], _indexToken) : _path[0];

        uint256 newLiquidity = _increaseLiquidity(
            pair,
            _indexToken,
            _amountIn,
            _sizeDelta,
            _isLong
        );

        require(newLiquidity >= _minOut, "PositionManager: insufficient minOut");

        uint256 deposited = _amountIn;
        if (_path.length == 2) {
            deposited = deposited.sub(_getVaultFee(deposited));
        }

        _validateIncreaseOrder(_indexToken, deposited, _sizeDelta, _isLong, _price);

        if (_isLong) {
            IOrderBook(orderBook).addBuyOrder(pair, deposited, _price);
        } else {
            IOrderBook(orderBook).addSellOrder(pair, deposited, _price);
        }
    }

    function decreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    ) external nonReentrant onlyPartnersOrLegacyMode {
        require(_path.length == 1 || _path.length == 2, "PositionManager: invalid _path.length");

        address pair = _path.length == 1 ? _getPair(_path[0], _indexToken) : _path[0];

        _validateDecreaseOrder(_indexToken, _amountIn, _sizeDelta, _isLong, _price);

        uint256 newSize = _decreaseLiquidity(
            pair,
            _indexToken,
            _amountIn,
            _sizeDelta,
            _isLong
        );

        require(newSize >= _minOut, "PositionManager: insufficient minOut");

        if (_amountIn > 0) {
            if (_path.length == 1) {
                IRouter(router).pluginTransfer(pair, address(this), msg.sender, _amountIn);
            } else {
                uint256 withdrawAmount = _amountIn.sub(_getVaultFee(_amountIn));
                IRouter(router).pluginTransfer(pair, vault, msg.sender, withdrawAmount);
                IRouter(router).pluginTransfer(_path[1], vault, msg.sender, _getVaultFee(_amountIn));
            }
        }

        if (_isLong) {
            IOrderBook(orderBook).addSellOrder(pair, _amountIn, _price);
        } else {
            IOrderBook(orderBook).addBuyOrder(pair, _amountIn, _price);
        }
    }

    function executeOrder(
        address _pair,
        address _indexToken,
        bool _isBuy,
        uint256 _price
    ) external nonReentrant onlyLiquidator {
        uint256 amountIn = IOrderBook(orderBook).executeOrder(_pair, _indexToken, _isBuy, _price);

        require(amountIn > 0, "PositionManager: no amountIn");

        if (_isBuy) {
            address[] memory path = new address[](2);
            path[0] = _pair;
            path[1] = _indexToken;
            IRouter(router).pluginSwap(_pair, _price, amountIn, path, address(this));
        } else {
            IRouter(router).pluginTransfer(_pair, address(this), vault, amountIn);
            _increaseShort(_pair, _indexToken, amountIn);
        }
    }

    function liquidatePosition(
        address _pair,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _price
    ) external nonReentrant onlyLiquidator {
        uint256 newSize = _decreaseLiquidity(_pair, _indexToken, 0, _sizeDelta, _isLong);

        require(newSize > 0, "PositionManager: no newSize");

        if (_isLong) {
            IOrderBook(orderBook).addSellOrder(_pair, 0, _price);
        } else {
            IOrderBook(orderBook).addBuyOrder(_pair, 0, _price);
        }
    }

    function _validateIncreaseOrder(
        address _indexToken,
        uint256 _deposited,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    ) internal view {
        if (shouldValidateIncreaseOrder) {
            uint256 newSize = _isLong
                ? vaultManager.longSizes(_indexToken).add(_sizeDelta)
                : vaultManager.shortSizes(_indexToken).add(_sizeDelta);

            uint256 minCollateral = _calculateCollateral(newSize, _price);
            require(_deposited >= minCollateral, "PositionManager: insufficient collateral");
        }
    }

    function _validateDecreaseOrder(
        address _indexToken,
        uint256 _amountIn,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    ) internal view {
        uint256 newSize = _isLong
            ? vaultManager.longSizes(_indexToken).sub(_sizeDelta)
            : vaultManager.shortSizes(_indexToken).sub(_sizeDelta);

        uint256 newCollateral = _isLong
            ? vaultManager.longCollaterals(_indexToken).sub(_amountIn)
            : vaultManager.shortCollaterals(_indexToken).sub(_amountIn);

        uint256 minCollateral = _calculateCollateral(newSize, _price);
        require(newCollateral >= minCollateral, "PositionManager: insufficient collateral");
    }
}
