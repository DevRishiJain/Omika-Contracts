pragma solidity ^0.8.0;

interface IVault {
    // Add IVault interface functions here
}

interface IRouter {
    // Add IRouter interface functions here
}

interface IShortsTracker {
    // Add IShortsTracker interface functions here
}

interface ITimelock {
    // Add ITimelock interface functions here
}

interface IWETH {
    // Add IWETH interface functions here
}

interface IReferralStorage {
    // Add IReferralStorage interface functions here
}

contract BasePositionManager {
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    address public admin;
    address public vault;
    address public shortsTracker;
    address public router;
    address public weth;
    uint256 public ethTransferGasLimit = 500 * 1000;
    uint256 public depositFee;
    uint256 public increasePositionBufferBps = 100;
    address public referralStorage;
    mapping (address => uint256) public feeReserves;
    mapping (address => uint256) public maxGlobalLongSizes;
    mapping (address => uint256) public maxGlobalShortSizes;

    event SetDepositFee(uint256 depositFee);
    event SetEthTransferGasLimit(uint256 ethTransferGasLimit);
    event SetIncreasePositionBufferBps(uint256 increasePositionBufferBps);
    event SetReferralStorage(address referralStorage);
    event SetAdmin(address admin);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Forbidden");
        _;
    }

    constructor(
        address _vault,
        address _router,
        address _shortsTracker,
        address _weth,
        uint256 _depositFee
    ) {
        vault = _vault;
        router = _router;
        weth = _weth;
        depositFee = _depositFee;
        shortsTracker = _shortsTracker;
        admin = msg.sender;
    }

    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
        emit SetAdmin(_admin);
    }

    function setEthTransferGasLimit(uint256 _ethTransferGasLimit) external onlyAdmin {
        ethTransferGasLimit = _ethTransferGasLimit;
        emit SetEthTransferGasLimit(_ethTransferGasLimit);
    }

    function setDepositFee(uint256 _depositFee) external onlyAdmin {
        depositFee = _depositFee;
        emit SetDepositFee(_depositFee);
    }

    function setIncreasePositionBufferBps(uint256 _increasePositionBufferBps) external onlyAdmin {
        increasePositionBufferBps = _increasePositionBufferBps;
        emit SetIncreasePositionBufferBps(_increasePositionBufferBps);
    }

    function setReferralStorage(address _referralStorage) external onlyAdmin {
        referralStorage = _referralStorage;
        emit SetReferralStorage(_referralStorage);
    }

    function setMaxGlobalSizes(
        address[] memory _tokens,
        uint256[] memory _longSizes,
        uint256[] memory _shortSizes
    ) external onlyAdmin {
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            maxGlobalLongSizes[token] = _longSizes[i];
            maxGlobalShortSizes[token] = _shortSizes[i];
        }
    }

    function withdrawFees(address _token, address _receiver) external onlyAdmin {
        uint256 amount = feeReserves[_token];
        if (amount == 0) {
            return;
        }

        feeReserves[_token] = 0;
        payable(_receiver).transfer(amount);
    }
}

contract PositionManager is BasePositionManager {
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant COLLATERAL_RATIO_PRECISION = 1e18;
    uint256 public constant COLLATERAL_RATIO_MAX = 10e17;

    struct Position {
        uint256 longSize;
        uint256 shortSize;
        uint256 collateral;
        uint256 collateralRatio;
        uint256 openPrice;
        uint256 liquidationPrice;
    }

    mapping (address => Position) public positions;

    event IncreasePosition(
        address indexed account,
        address indexed token,
        uint256 indexed amount,
        uint256 cost,
        uint256 size,
        uint256 collateralRatio
    );

    constructor(
        address _vault,
        address _router,
        address _shortsTracker,
        address _weth,
        uint256 _depositFee
    ) BasePositionManager(_vault, _router, _shortsTracker, _weth, _depositFee) {}

    function increasePosition(
        address _token,
        uint256 _amount,
        uint256 _minAmountOut
    ) external payable {
        // Add logic for increasing a position here
    }
}
