 // SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

contract GlpManager {
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant USDG_DECIMALS = 18;
    uint256 public constant GLP_PRECISION = 10 ** 18;
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    address public vault;
    address public shortsTracker;
    address public usdg;
    address public glp;

    uint256 public cooldownDuration;

    uint256 public aumAddition;
    uint256 public aumDeduction;

    bool public inPrivateMode;
    uint256 public shortsTrackerAveragePriceWeight;
    mapping (address => bool) public isHandler;

    event AddLiquidity(
        address account,
        address token,
        uint256 amount,
        uint256 aumInUsdg,
        uint256 glpSupply,
        uint256 usdgAmount,
        uint256 mintAmount
    );

    event RemoveLiquidity(
        address account,
        address token,
        uint256 glpAmount,
        uint256 aumInUsdg,
        uint256 glpSupply,
        uint256 usdgAmount,
        uint256 amountOut
    );

    constructor(address _vault, address _usdg, address _glp, address _shortsTracker, uint256 _cooldownDuration) public {
        vault = _vault;
        usdg = _usdg;
        glp = _glp;
        shortsTracker = _shortsTracker;
        cooldownDuration = _cooldownDuration;
    }

    function setInPrivateMode(bool _inPrivateMode) external {
        inPrivateMode = _inPrivateMode;
    }

    function setShortsTracker(address _shortsTracker) external {
        shortsTracker = _shortsTracker;
    }

    function setShortsTrackerAveragePriceWeight(uint256 _shortsTrackerAveragePriceWeight) external {
        require(_shortsTrackerAveragePriceWeight <= BASIS_POINTS_DIVISOR, "GlpManager: invalid weight");
        shortsTrackerAveragePriceWeight = _shortsTrackerAveragePriceWeight;
    }

    function setHandler(address _handler, bool _isActive) external {
        isHandler[_handler] = _isActive;
    }

    function setCooldownDuration(uint256 _cooldownDuration) external {
        require(_cooldownDuration <= MAX_COOLDOWN_DURATION, "GlpManager: invalid _cooldownDuration");
        cooldownDuration = _cooldownDuration;
    }

    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction) external {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    function addLiquidity(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256) {
        if (inPrivateMode) { revert("GlpManager: action not enabled"); }
        return _addLiquidity(msg.sender, msg.sender, _token, _amount, _minUsdg, _minGlp);
    }

    function addLiquidityForAccount(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256) {
        _validateHandler();
        return _addLiquidity(_fundingAccount, _account, _token, _amount, _minUsdg, _minGlp);
    }

    function _addLiquidity(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) internal returns (uint256) {
        require(isHandler[_account] || isHandler[_fundingAccount], "GlpManager: unauthorized");
        uint256 glpAmount = _calcGlpOutGivenTokenIn(_token, _amount);
        require(glpAmount >= _minGlp, "GlpManager: slippage");
        uint256 aumInUsdg = _calcAumInUsdg(_token, _amount);
        require(aumInUsdg >= _minUsdg, "GlpManager: minUsdg");

        _transferFrom(_token, _fundingAccount, address(this), _amount);
        _mintGlp(_account, glpAmount);
        _mintUsdg(_account, aumInUsdg);

        emit AddLiquidity(_account, _token, _amount, aumInUsdg, IERC20(glp).totalSupply(), _calcUsdgOutGivenGlpIn(glpAmount), glpAmount);

        return glpAmount;
    }

    function removeLiquidity(address _token, uint256 _glpAmount, uint256 _minUsdg, uint256 _minToken) external returns (uint256, uint256) {
        if (inPrivateMode) { revert("GlpManager: action not enabled"); }
        return _removeLiquidity(msg.sender, msg.sender, _token, _glpAmount, _minUsdg, _minToken);
    }

    function removeLiquidityToAccount(address _account, address _token, uint256 _glpAmount, uint256 _minUsdg, uint256 _minToken) external returns (uint256, uint256) {
        _validateHandler();
        return _removeLiquidity(msg.sender, _account, _token, _glpAmount, _minUsdg, _minToken);
    }

    function _removeLiquidity(address _account, address _recipient, address _token, uint256 _glpAmount, uint256 _minUsdg, uint256 _minToken) internal returns (uint256, uint256) {
        require(isHandler[_account], "GlpManager: unauthorized");
        require(_glpAmount <= IERC20(glp).balanceOf(_account), "GlpManager: not enough GLP");

        uint256 usdgOut = _calcUsdgOutGivenGlpIn(_glpAmount);
        uint256 tokenOut = _calcTokenOutGivenGlpIn(_token, _glpAmount);
        require(usdgOut >= _minUsdg, "GlpManager: slippage (USDG)");
        require(tokenOut >= _minToken, "GlpManager: slippage (Token)");

        _burnGlp(_account, _glpAmount);
        _burnUsdg(_account, usdgOut);
        _transfer(_token, _recipient, tokenOut);

        emit RemoveLiquidity(_account, _token, _glpAmount, usdgOut, IERC20(glp).totalSupply(), tokenOut, usdgOut);

        return (usdgOut, tokenOut);
    }

    function _calcAumInUsdg(address _token, uint256 _amount) internal view returns (uint256) {
        uint256 price = _getTokenPrice(_token);
        return _amount.mul(price).div(PRICE_PRECISION);
    }

    function _calcGlpOutGivenTokenIn(address _token, uint256 _amount) internal view returns (uint256) {
        uint256 usdgValue = _calcAumInUsdg(_token, _amount);
        return _calcGlpOutGivenUsdgIn(usdgValue);
    }

    function _calcGlpOutGivenUsdgIn(uint256 _usdgAmount) internal view returns (uint256) {
        uint256 usdgSupply = IERC20(usdg).totalSupply();
        uint256 glpSupply = IERC20(glp).totalSupply();
        if (usdgSupply == 0 || glpSupply == 0) {
            return _usdgAmount;
        }
        uint256 effectiveUsdgAmount = _usdgAmount.sub(aumDeduction).add(aumAddition);
        uint256 mintAmount = effectiveUsdgAmount.mul(glpSupply).div(usdgSupply);
        return mintAmount.mul(GLP_PRECISION).div(PRICE_PRECISION);
    }

    function _calcUsdgOutGivenGlpIn(uint256 _glpAmount) internal view returns (uint256) {
        uint256 usdgSupply = IERC20(usdg).totalSupply();
        uint256 glpSupply = IERC20(glp).totalSupply();
        if (usdgSupply == 0 || glpSupply == 0) {
            return _glpAmount;
        }
        uint256 usdgAmount = _glpAmount.mul(usdgSupply).mul(PRICE_PRECISION).div(glpSupply).div(GLP_PRECISION);
        return usdgAmount.sub(aumAddition).add(aumDeduction);
    }

    function _calcTokenOutGivenGlpIn(address _token, uint256 _glpAmount) internal view returns (uint256) {
        uint256 price = _getTokenPrice(_token);
        return _glpAmount.mul(price).div(PRICE_PRECISION);
    }

    function _getTokenPrice(address _token) internal view returns (uint256) {
        (bool success, bytes memory data) = _token.staticcall(abi.encodeWithSignature("price()"));
        if (!success) { revert("GlpManager: invalid token"); }
        return abi.decode(data, (uint256));
    }

    function _transfer(address _token, address _recipient, uint256 _amount) internal {
        (bool success, ) = _token.call(abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount));
        if (!success) { revert("GlpManager: transfer failed"); }
    }

    function _transferFrom(address _token, address _sender, address _recipient, uint256 _amount) internal {
        (bool success, ) = _token.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", _sender, _recipient, _amount));
        if (!success) { revert("GlpManager: transferFrom failed"); }
    }

    function _mintGlp(address _account, uint256 _amount) internal {
        (bool success, ) = glp.call(abi.encodeWithSignature("mint(address,uint256)", _account, _amount));
        if (!success) { revert("GlpManager: mint GLP failed"); }
    }

    function _burnGlp(address _account, uint256 _amount) internal {
        (bool success, ) = glp.call(abi.encodeWithSignature("burn(address,uint256)", _account, _amount));
        if (!success) { revert("GlpManager: burn GLP failed"); }
    }

    function _mintUsdg(address _account, uint256 _amount) internal {
        (bool success, ) = usdg.call(abi.encodeWithSignature("mint(address,uint256)", _account, _amount));
        if (!success) { revert("GlpManager: mint USDG failed"); }
    }

    function _burnUsdg(address _account, uint256 _amount) internal {
        (bool success, ) = usdg.call(abi.encodeWithSignature("burn(address,uint256)", _account, _amount));
        if (!success) { revert("GlpManager: burn USDG failed"); }
    }

    function _validateHandler() internal view {
        require(isHandler[msg.sender], "GlpManager: unauthorized handler");
    }
}
