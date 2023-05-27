 pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface ITimelock {
function getPendingAdmin(address target) external view returns (address);
function acceptAdmin(address target) external;
}

contract TokenManager is ReentrancyGuard {
bool public isInitialized;
uint256 public actionsNonce;
uint256 public minAuthorizations;
address public admin;
address[] public signers;
mapping(address => bool) public isSigner;
mapping(bytes32 => bool) public pendingActions;
mapping(address => mapping(bytes32 => bool)) public signedActions;
event SignalApprove(address indexed token, address indexed spender, uint256 amount, bytes32 action, uint256 nonce);
event SignalApproveNFT(address indexed token, address indexed spender, uint256 tokenId, bytes32 action, uint256 nonce);
event SignalApproveNFTs(address indexed token, address indexed spender, uint256[] tokenIds, bytes32 action, uint256 nonce);
event SignalSetAdmin(address indexed target, address indexed admin, bytes32 action, uint256 nonce);
event SignalSetGov(address indexed timelock, address indexed target, address indexed gov, bytes32 action, uint256 nonce);
event SignalPendingAction(bytes32 indexed action, uint256 nonce);
event SignAction(bytes32 indexed action, uint256 nonce);
event ClearAction(bytes32 indexed action, uint256 nonce);

constructor(uint256 _minAuthorizations) {
    admin = msg.sender;
    minAuthorizations = _minAuthorizations;
}

modifier onlyAdmin() {
    require(msg.sender == admin, "TokenManager: unauthorized");
    _;
}

modifier onlySigner() {
    require(isSigner[msg.sender], "TokenManager: unauthorized");
    _;
}

function initialize(address[] calldata _signers) external onlyAdmin {
    require(!isInitialized, "TokenManager: already initialized");
    isInitialized = true;

    signers = _signers;
    for (uint256 i = 0; i < _signers.length; i++) {
        address signer = _signers[i];
        isSigner[signer] = true;
    }
}

function signersLength() external view returns (uint256) {
    return signers.length;
}

function signalApprove(address _token, address _spender, uint256 _amount) external nonReentrant onlyAdmin {
    actionsNonce++;
    uint256 nonce = actionsNonce;
    bytes32 action = keccak256(abi.encode("approve", _token, _spender, _amount, nonce));
    _setPendingAction(action, nonce);
    emit SignalApprove(_token, _spender, _amount, action, nonce);
}

function signApprove(address _token, address _spender, uint256 _amount, uint256 _nonce) external nonReentrant onlySigner {
    bytes32 action = keccak256(abi.encode("approve", _token, _spender, _amount, _nonce));
    _validateAction(action);
    require(!signedActions[msg.sender][action], "TokenManager: already signed");
    signedActions[msg.sender][action] = true;
    emit SignAction(action, _nonce);
}

function approve(address _token, address _spender, uint256 _amount, uint256 _nonce) external nonReentrant onlyAdmin {
    bytes32 action = keccak256(abi.encode("approve", _token, _spender, _amount, _
}

function setAdmin(address _target, address _admin) external nonReentrant onlyAdmin {
    actionsNonce++;
    uint256 nonce = actionsNonce;
    bytes32 action = keccak256(abi.encodePacked("setAdmin", _target, _admin, nonce));
    _setPendingAction(action, nonce);
    emit SignalSetAdmin(_target, _admin, action, nonce);
}

function signSetAdmin(address _target, address _admin, uint256 _nonce) external nonReentrant onlySigner {
    bytes32 action = keccak256(abi.encodePacked("setAdmin", _target, _admin, _nonce));
    _validateAction(action);
    require(!signedActions[msg.sender][action], "TokenManager: already signed");
    signedActions[msg.sender][action] = true;
    emit SignAction(action, _nonce);
}

function executeSetAdmin(address _target, address _admin, uint256 _nonce) external nonReentrant onlyAdmin {
    bytes32 action = keccak256(abi.encodePacked("setAdmin", _target, _admin, _nonce));
    _validateAction(action);
    _validateAuthorization(action);

    ITimelock(_target).setAdmin(_admin);
    _clearAction(action, _nonce);
}

function setGov(address _timelock, address _target, address _gov) external nonReentrant onlyAdmin {
    actionsNonce++;
    uint256 nonce = actionsNonce;
    bytes32 action = keccak256(abi.encodePacked("setGov", _timelock, _target, _gov, nonce));
    _setPendingAction(action, nonce);
    emit SignalSetGov(_timelock, _target, _gov, action, nonce);
}

function signSetGov(address _timelock, address _target, address _gov, uint256 _nonce) external nonReentrant onlySigner {
    bytes32 action = keccak256(abi.encodePacked("setGov", _timelock, _target, _gov, _nonce));
    _validateAction(action);
    require(!signedActions[msg.sender][action], "TokenManager: already signed");
    signedActions[msg.sender][action] = true;
    emit SignAction(action, _nonce);
}

function executeSetGov(address _timelock, address _target, address _gov, uint256 _nonce) external nonReentrant onlyAdmin {
    bytes32 action = keccak256(abi.encodePacked("setGov", _timelock, _target, _gov, _nonce));
    _validateAction(action);
    _validateAuthorization(action);

    ITimelock(_timelock).setPendingAdmin(_gov);
    _clearAction(action, _nonce);
}

function _setPendingAction(bytes32 _action, uint256 _nonce) private {
    require(!pendingActions[_action], "TokenManager: action already pending");
    pendingActions[_action] = true;
    emit SignalPendingAction(_action, _nonce);
}

function _validateAction(bytes32 _action) private view {
    require(pendingActions[_action], "TokenManager: action not pending");
}

function _validateAuthorization(bytes32 _action) private view {
    uint256 count;
    for (uint256 i = 0; i < signers.length; i++) {
        address signer = signers[i];
        if (signedActions[signer][_action]) {
            count++;
        }
    }
    require(count >= minAuthorizations, "TokenManager: not enough authorizations");
}

function _clearAction(bytes32 _action, uint256 _nonce) private {
    delete pendingActions[_
 function signalSetAdmin(address _target, address _admin) external nonReentrant onlySigner {
        actionsNonce++;
        uint256 nonce = actionsNonce;
        bytes32 action = keccak256(abi.encodePacked("setAdmin", _target, _admin, nonce));
        _setPendingAction(action, nonce);
        signedActions[msg.sender][action] = true;
        emit SignalSetAdmin(_target, _admin, action, nonce);
    }

    function signSetAdmin(address _target, address _admin, uint256 _nonce) external nonReentrant onlySigner {
        bytes32 action = keccak256(abi.encodePacked("setAdmin", _target, _admin, _nonce));
        _validateAction(action);
        require(!signedActions[msg.sender][action], "TokenManager: already signed");
        signedActions[msg.sender][action] = true;
        emit SignAction(action, _nonce);
    }

    function setAdmin(address _target, address _admin, uint256 _nonce) external nonReentrant onlySigner {
        bytes32 action = keccak256(abi.encodePacked("setAdmin", _target, _admin, _nonce));
        _validateAction(action);
        _validateAuthorization(action);

        ITimelock(_target).setAdmin(_admin);
        _clearAction(action, _nonce);
    }

    function signalSetGov(address _timelock, address _target, address _gov) external nonReentrant onlyAdmin {
        actionsNonce++;
        uint256 nonce = actionsNonce;
        bytes32 action = keccak256(abi.encodePacked("signalSetGov", _timelock, _target, _gov, nonce));
        _setPendingAction(action, nonce);
        signedActions[msg.sender][action] = true;
        emit SignalSetGov(_timelock, _target, _gov, action, nonce);
    }

    function signSetGov(address _timelock, address _target, address _gov, uint256 _nonce) external nonReentrant onlySigner {
        bytes32 action = keccak256(abi.encodePacked("signalSetGov", _timelock, _target, _gov, _nonce));
        _validateAction(action);
        require(!signedActions[msg.sender][action], "TokenManager: already signed");
        signedActions[msg.sender][action] = true;
        emit SignAction(action, _nonce);
    }

    function setGov(address _timelock, address _target, address _gov, uint256 _nonce) external nonReentrant onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("signalSetGov", _timelock, _target, _gov, _nonce));
        _validateAction(action);
        _validateAuthorization(action);

        ITimelock(_timelock).signalSetGov(_target, _gov);
        _clearAction(action, _nonce);
    }

    function _setPendingAction(bytes32 _action, uint256 _nonce) private {
        pendingActions[_action] = true;
        emit SignalPendingAction(_action, _nonce);
    }

    function _validateAction(bytes32 _action) private view {
        require(pendingActions[_action], "TokenManager: action not signalled");
    }

    function _validateAuthorization(bytes32 _action) private view {
        uint256 count = 0;
        for (uint256 i = 0; i < signers.length; i++) {
            address signer = signers[i];
            if (signedActions[signer][_action]) {
                count++;
            }
        }
function _clearAction(bytes32 _action, uint256 _nonce) private {
    delete pendingActions[_

        if (count == 0) {
            revert("TokenManager: action not authorized");
        }
        require(count >= minAuthorizations, "TokenManager: insufficient authorization");
    }

    function _clearAction(bytes32 _action, uint256 _nonce) private {
        require(pendingActions[_action], "TokenManager: invalid _action");
        delete pendingActions[_action];
        emit ClearAction(_action, _nonce);
    }
}
