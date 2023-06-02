 // SPDX-License-Identifier: MIT

import "../libraries/math/SafeMath.sol";

import "./interfaces/IVaultPriceFeed.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import "../oracle/interfaces/ISecondaryPriceFeed.sol";
import "../oracle/interfaces/IChainlinkFlags.sol";
import "../amm/interfaces/IPancakePair.sol";

pragma solidity 0.6.12;

contract VaultPriceFeed is IVaultPriceFeed {
    using SafeMath for uint256;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant ONE_USD = PRICE_PRECISION;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant MAX_SPREAD_BASIS_POINTS = 50;
    uint256 public constant MAX_ADJUSTMENT_INTERVAL = 2 hours;
    uint256 public constant MAX_ADJUSTMENT_BASIS_POINTS = 20;

    // Identifier of the Sequencer offline flag on the Flags contract
    address constant private FLAG_ARBITRUM_SEQ_OFFLINE = address(bytes20(bytes32(uint256(keccak256("chainlink.flags.arbitrum-seq-offline")) - 1)));

    address public gov;
    address public chainlinkFlags;

    bool public isAmmEnabled = true;
    bool public isSecondaryPriceEnabled = true;
    bool public useV2Pricing = false;
    bool public favorPrimaryPrice = false;
    uint256 public priceSampleSpace = 3;
    uint256 public maxStrictPriceDeviation = 0;
    address public secondaryPriceFeed;
    uint256 public spreadThresholdBasisPoints = 30;

    address public btc;
    address public eth;
    address public bnb;
    address public bnbBusd;
    address public ethBnb;
    address public btcBnb;

    mapping (address => address) public priceFeeds;
    mapping (address => uint256) public priceDecimals;
    mapping (address => uint256) public spreadBasisPoints;
    // Chainlink can return prices for stablecoins
    // that differs from 1 USD by a larger percentage than stableSwapFeeBasisPoints
    // we use strictStableTokens to cap the price to 1 USD
    // this allows us to configure stablecoins like DAI as being a stableToken
    // while not being a strictStableToken
    mapping (address => bool) public strictStableTokens;

    mapping (address => uint256) public override adjustmentBasisPoints;
    mapping (address => bool) public override isAdjustmentAdditive;
    mapping (address => uint256) public lastAdjustmentTimings;

    modifier onlyGov() {
        require(msg.sender == gov, "VaultPriceFeed: forbidden");
        _;
    }

    constructor() public {
        gov = msg.sender;
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function setChainlinkFlags(address _chainlinkFlags) external onlyGov {
        chainlinkFlags = _chainlinkFlags;
    }

    function setAdjustment(address _token, bool _isAdditive, uint256 _adjustmentBps) external override onlyGov {
        require(
            lastAdjustmentTimings[_token].add(MAX_ADJUSTMENT_INTERVAL) < block.timestamp,
            "VaultPriceFeed: adjustment frequency exceeded"
        );
        require(_adjustmentBps <= MAX_ADJUSTMENT_BASIS_POINTS, "invalid _adjustmentBps");
        isAdjustmentAdditive[_token] = _isAdditive;
        adjustmentBasisPoints[_token] = _adjustmentBps;
        lastAdjustmentTimings[_token] = block.timestamp;
    }

    function setUseV2Pricing(bool _useV2Pricing) external onlyGov {
        useV2Pricing = _useV2Pricing;
    }

    function setIsAmmEnabled(bool _isAmmEnabled) external onlyGov {
        isAmmEnabled = _isAmmEnabled;
    }

    function setIsSecondaryPriceEnabled(bool _isSecondaryPriceEnabled) external onlyGov {
        isSecondaryPriceEnabled = _isSecondaryPriceEnabled;
    }

    function setSecondaryPriceFeed(address _secondaryPriceFeed) external onlyGov {
        secondaryPriceFeed = _secondaryPriceFeed;
    }

    function setTokens(address _btc, address _eth, address _bnb) external onlyGov {
        btc = _btc;
        eth = _eth;
        bnb = _bnb;
    }

    function setPairs(address _bnbBusd, address _ethBnb, address _btcBnb) external onlyGov {
        bnbBusd = _bnbBusd;
        ethBnb = _ethBnb;
        btcBnb = _btcBnb;
    }

    function setPriceFeed(address _token, address _priceFeed, uint256 _priceDecimals) external onlyGov {
        require(_token != address(0), "VaultPriceFeed: invalid token address");
        require(_priceFeed != address(0), "VaultPriceFeed: invalid price feed address");
        require(_priceDecimals > 0, "VaultPriceFeed: invalid price decimals");
        priceFeeds[_token] = _priceFeed;
        priceDecimals[_token] = _priceDecimals;
    }

    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints) external onlyGov {
        require(_spreadBasisPoints <= MAX_SPREAD_BASIS_POINTS, "VaultPriceFeed: invalid spread basis points");
        spreadBasisPoints[_token] = _spreadBasisPoints;
    }

    function setStrictStableTokens(address[] memory _tokens, bool[] memory _isStrictStable) external onlyGov {
        require(_tokens.length == _isStrictStable.length, "VaultPriceFeed: invalid input length");
        for (uint256 i = 0; i < _tokens.length; i++) {
            strictStableTokens[_tokens[i]] = _isStrictStable[i];
        }
    }

    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external onlyGov {
        require(_maxStrictPriceDeviation <= BASIS_POINTS_DIVISOR, "VaultPriceFeed: invalid max strict price deviation");
        maxStrictPriceDeviation = _maxStrictPriceDeviation;
    }

    function setSpreadThresholdBasisPoints(uint256 _spreadThresholdBasisPoints) external onlyGov {
        require(_spreadThresholdBasisPoints <= BASIS_POINTS_DIVISOR, "VaultPriceFeed: invalid spread threshold basis points");
        spreadThresholdBasisPoints = _spreadThresholdBasisPoints;
    }

    function adjustPrice(address _token, uint256 _currentPrice) external view override returns (uint256) {
        uint256 adjustmentBps = adjustmentBasisPoints[_token];
        if (adjustmentBps == 0) {
            return _currentPrice;
        }

        uint256 lastAdjustmentTiming = lastAdjustmentTimings[_token];
        if (lastAdjustmentTiming == 0) {
            return _currentPrice;
        }

        bool additive = isAdjustmentAdditive[_token];
        if (additive) {
            return _currentPrice.add(_currentPrice.mul(adjustmentBps).div(BASIS_POINTS_DIVISOR));
        } else {
            uint256 timeElapsed = block.timestamp.sub(lastAdjustmentTiming);
            uint256 adjustment = _currentPrice.mul(adjustmentBps).div(BASIS_POINTS_DIVISOR);
            uint256 adjustmentPerSec = adjustment.div(MAX_ADJUSTMENT_INTERVAL);
            return _currentPrice.sub(adjustmentPerSec.mul(timeElapsed));
        }
    }

    function getLatestPrice(address _token) public view returns (uint256) {
        if (useV2Pricing) {
            return getLatestPriceV2(_token);
        } else {
            return getLatestPriceV1(_token);
        }
    }

    function getLatestPriceV1(address _token) public view returns (uint256) {
        require(priceFeeds[_token] != address(0), "VaultPriceFeed: price feed not set");
        require(priceDecimals[_token] != 0, "VaultPriceFeed: price decimals not set");
        IPriceFeed priceFeed = IPriceFeed(priceFeeds[_token]);
        uint256 price = priceFeed.getPrice();
        uint256 decimals = priceDecimals[_token];
        require(price <= uint256(-1) / PRICE_PRECISION, "VaultPriceFeed: price exceeds maximum");
        return price.mul(PRICE_PRECISION).div(10 ** decimals);
    }

    function getLatestPriceV2(address _token) public view returns (uint256) {
        if (isAmmEnabled && isAmmToken(_token)) {
            return getAmmPrice(_token);
        } else if (isSecondaryPriceEnabled && secondaryPriceFeed != address(0) && _token != address(0)) {
            return getSecondaryPrice(_token);
        } else {
            return getLatestPriceV1(_token);
        }
    }

    function getAmmPrice(address _token) internal view returns (uint256) {
        IPancakePair ammPair = IPancakePair(getAmmPair(_token));
        uint256 priceCumulative = ammPair.price0CumulativeLast();
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = ammPair.getReserves();
        if (reserve0 == 0 || reserve1 == 0) {
            return 0;
        }
        if (address(ammPair.token0()) == _token) {
            return calculatePrice(reserve1, reserve0, priceCumulative, blockTimestampLast);
        } else {
            return calculatePrice(reserve0, reserve1, priceCumulative, blockTimestampLast);
        }
    }

    function calculatePrice(
        uint256 _reserveBase,
        uint256 _reserveQuote,
        uint256 _priceCumulative,
        uint256 _blockTimestampLast
    ) internal pure returns (uint256) {
        uint256 timeElapsed = block.timestamp - _blockTimestampLast; // overflow is desired
        // overflow is desired, casting never truncates
        uint256 priceAverage = uint256(SafeMath.div(_priceCumulative, timeElapsed));
        uint256 price = priceAverage.mul(_reserveBase).div(_reserveQuote);
        return price;
    }

    function getSecondaryPrice(address _token) internal view returns (uint256) {
        ISecondaryPriceFeed priceFeed = ISecondaryPriceFeed(secondaryPriceFeed);
        uint256 price = priceFeed.getSecondaryPrice(_token);
        require(price <= uint256(-1) / PRICE_PRECISION, "VaultPriceFeed: price exceeds maximum");
        return price.mul(PRICE_PRECISION);
    }

    function isAmmToken(address _token) internal view returns (bool) {
        return _token == btc || _token == eth || _token == bnb;
    }

    function getAmmPair(address _token) internal view returns (address) {
        if (_token == btc) {
            return btcBnb;
        } else if (_token == eth) {
            return ethBnb;
        } else if (_token == bnb) {
            return bnbBusd;
        } else {
            revert("VaultPriceFeed: AMM pair not found for token");
        }
    }

    function adjustForDecimals(uint256 _price, uint256 _tokenDecimals) internal pure returns (uint256) {
        return _price.mul(PRICE_PRECISION).div(10 ** _tokenDecimals);
    }

    function isPriceDeviationAllowed(uint256 _price, uint256 _tokenDecimals, bool _strictStableToken) internal view returns (bool) {
        uint256 maxPriceDeviation = maxStrictPriceDeviation;
        if (_strictStableToken) {
            maxPriceDeviation = BASIS_POINTS_DIVISOR;
        }
        uint256 maxPriceDeviationScaled = maxPriceDeviation.mul(PRICE_PRECISION).div(10 ** _tokenDecimals);
        return _price <= ONE_USD.add(maxPriceDeviationScaled) && _price >= ONE_USD.sub(maxPriceDeviationScaled);
    }

    function isSequencerOffline() internal view returns (bool) {
        if (chainlinkFlags == address(0)) {
            return false;
        }
        IChainlinkFlags flags = IChainlinkFlags(chainlinkFlags);
        return flags.getFlag(FLAG_ARBITRUM_SEQ_OFFLINE);
    }

    function getPrice(address _token) external view override returns (uint256, bool) {
        uint256 price = getLatestPrice(_token);
        uint256 tokenDecimals = priceDecimals[_token];
        bool strictStableToken = strictStableTokens[_token];
        bool deviationAllowed = isPriceDeviationAllowed(price, tokenDecimals, strictStableToken);
        return (price, deviationAllowed);
    }

    function getAmmPriceSampleSpace() external view returns (uint256) {
        return priceSampleSpace;
    }

    function setAmmPriceSampleSpace(uint256 _priceSampleSpace) external onlyGov {
        priceSampleSpace = _priceSampleSpace;
    }

    function getFavorPrimaryPrice() external view returns (bool) {
        return favorPrimaryPrice;
    }

    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external onlyGov {
        favorPrimaryPrice = _favorPrimaryPrice;
    }
}
