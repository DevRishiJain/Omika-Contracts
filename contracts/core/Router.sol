 // SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./libraries/math/SafeMath.sol";
import "./libraries/token/IERC20.sol";
import "./libraries/token/SafeERC20.sol";
import "./libraries/utils/Address.sol";

import "./tokens/interfaces/IWETH.sol";
import "./vault/interfaces/IVault.sol";
import "./router/interfaces/IRouter.sol";

contract Router is IRouter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public gov;

    // Wrapped BNB / ETH
    address public weth;
    address public usdg;
    address public vault;

    mapping(address => bool) public plugins;
    mapping(address => mapping(address => bool)) public approvedPlugins;

    event Swap(address account, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    modifier onlyGov() {
        require(msg.sender == gov, "Router: forbidden");
        _;
    }

    constructor(address _vault, address _usdg, address _weth) {
        vault = _vault;
        usdg = _usdg;
        weth = _weth;
        gov = msg.sender;
    }

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function addPlugin(address _plugin) external override onlyGov {
        plugins[_plugin] = true;
    }

    function removePlugin(address _plugin) external onlyGov {
        plugins[_plugin] = false;
    }

    function approvePlugin(address _plugin) external {
        approvedPlugins[msg.sender][_plugin] = true;
    }

    function denyPlugin(address _plugin) external {
        approvedPlugins[msg.sender][_plugin] = false;
    }

    function pluginTransfer(
        address _token,
        address _account,
        address _receiver,
        uint256 _amount
    ) external override {
        _validatePlugin(_account);
        IERC20(_token).safeTransferFrom(_account, _receiver, _amount);
    }

    function pluginIncreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    ) external override {
        _validatePlugin(_account);
        IVault(vault).increasePosition(_account, _collateralToken, _indexToken, _sizeDelta, _isLong);
    }

    function pluginDecreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver
    ) external override returns (uint256) {
        _validatePlugin(_account);
        return
            IVault(vault).decreasePosition(
                _account,
                _collateralToken,
                _indexToken,
                _collateralDelta,
                _sizeDelta,
                _isLong,
                _receiver
            );
    }

    function directPoolSwap(
        address[] calldata _path,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _receiver
    ) external override {
        address tokenIn = _path[0];
        address tokenOut = _path[_path.length - 1];
        require(tokenIn != tokenOut, "Router: invalid path");

        if (_amountIn > 0) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
        }

        uint256 amountOut = _directPoolSwap(_path, _amountIn, _amountOutMin);

        if (amountOut > 0) {
            if (tokenOut == weth) {
                IWETH(weth).withdraw(amountOut);
                payable(_receiver).sendValue(amountOut);
            } else {
                IERC20(tokenOut).safeTransfer(_receiver, amountOut);
            }
        }

        emit Swap(msg.sender, tokenIn, tokenOut, _amountIn, amountOut);
    }

    function _directPoolSwap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) internal returns (uint256) {
        for (uint256 i = 0; i < _path.length - 1; i++) {
            address tokenIn = _path[i];
            address tokenOut = _path[i + 1];
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(tokenIn, tokenOut);

            uint256 amountOut = _getAmountOut(_amountIn, reserveIn, reserveOut);
            require(amountOut >= _amountOutMin, "Router: insufficient output amount");

            (uint256 amountInNext, uint256 amountOutNext) =
                _calculateSwap(tokenIn, tokenOut, _amountIn, amountOut, reserveIn, reserveOut);
            _amountIn = amountInNext;

            emit Swap(address(this), tokenIn, tokenOut, _amountIn, amountOutNext);
        }

        return _amountIn;
    }

    function _calculateSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOut,
        uint256 _reserveIn,
        uint256 _reserveOut
    ) internal returns (uint256, uint256) {
        if (_tokenIn == weth && _tokenOut == weth) {
            return (_amountIn, _amountOut);
        }

        if (_tokenIn == weth) {
            address[] memory path = new address[](2);
            path[0] = weth;
            path[1] = _tokenOut;

            uint256[] memory amounts = _swapExactTokensForTokens(_amountIn, _amountOut, path, address(this));
            return (_amountsIn(amounts), amounts[amounts.length - 1]);
        }

        if (_tokenOut == weth) {
            address[] memory path = new address[](2);
            path[0] = _tokenIn;
            path[1] = weth;

            uint256[] memory amounts = _swapExactTokensForTokens(_amountIn, _amountOut, path, address(this));
            return (_amountsIn(amounts), amounts[amounts.length - 1]);
        }

        address[] memory path = new address[](3);
        path[0] = _tokenIn;
        path[1] = weth;
        path[2] = _tokenOut;

        uint256[] memory amounts = _swapExactTokensForTokens(_amountIn, _amountOut, path, address(this));
        return (_amountsIn(amounts), amounts[amounts.length - 1]);
    }

    function _amountsIn(uint256[] memory amounts) internal pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < amounts.length - 1; i++) {
            sum += amounts[i];
        }
        return sum;
    }

    function _getAmountOut(
        uint256 _amountIn,
        uint256 _reserveIn,
        uint256 _reserveOut
    ) internal pure returns (uint256) {
        uint256 amountInWithFee = _amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(_reserveOut);
        uint256 denominator = _reserveIn.mul(1000).add(amountInWithFee);
        return numerator / denominator;
    }

    function _getReserves(address _tokenA, address _tokenB) internal view returns (uint256, uint256) {
        return IVault(vault).getReserves(_tokenA, _tokenB);
    }

    function _validatePlugin(address _plugin) internal view {
        require(plugins[_plugin] || approvedPlugins[msg.sender][_plugin], "Router: plugin not allowed");
    }
}
