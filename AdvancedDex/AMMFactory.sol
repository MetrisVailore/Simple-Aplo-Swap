// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title AMM Factory
/// @notice Creates and manages AMM pairs
/// @dev Implements deterministic pair creation with CREATE2
contract AMMFactory is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable weth;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error IdenticalTokens();
    error PairExists();
    error InvalidFee();
    error Forbidden();
    error InvalidTokenContract();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint24 swapFeeBps,
        uint256 pairIndex
    );

    event FeeToUpdated(address indexed feeTo);
    event FeeToSetterUpdated(address indexed feeToSetter);

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize factory
    /// @param wethAddress WETH9 contract address
    /// @param feeToSetter_ Initial fee setter address
    constructor(address wethAddress, address feeToSetter_) {
        if (wethAddress == address(0) || feeToSetter_ == address(0)) {
            revert ZeroAddress();
        }
        
        weth = wethAddress;
        feeToSetter = feeToSetter_;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get total number of pairs
    /// @return Number of pairs created
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /// @notice Get pair address for token pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return pair Pair address (reverts if doesn't exist)
    function pairFor(address tokenA, address tokenB) external view returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = getPair[token0][token1];
        if (pair == address(0)) revert InvalidTokenContract();
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Update protocol fee recipient
    /// @param _feeTo New fee recipient address (zero address to disable fees)
    function setFeeTo(address _feeTo) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        feeTo = _feeTo;
        emit FeeToUpdated(_feeTo);
    }

    /// @notice Update fee setter address
    /// @param _feeToSetter New fee setter address
    function setFeeToSetter(address _feeToSetter) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        if (_feeToSetter == address(0)) revert ZeroAddress();
        
        feeToSetter = _feeToSetter;
        emit FeeToSetterUpdated(_feeToSetter);
    }

    /*//////////////////////////////////////////////////////////////
                            PAIR CREATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new trading pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param swapFeeBps Swap fee in basis points (max 10000 = 100%)
    /// @return pair Address of created pair
    function createPair(
        address tokenA,
        address tokenB,
        uint24 swapFeeBps
    ) external returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        
        if (getPair[token0][token1] != address(0)) revert PairExists();
        if (swapFeeBps > 10_000) revert InvalidFee();

        // Validate tokens are actual contracts with totalSupply
        _validateToken(token0);
        _validateToken(token1);

        // Deploy pair with CREATE2 for deterministic addresses
        bytes memory bytecode = _getPairBytecode(token0, token1, swapFeeBps);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        if (pair == address(0)) revert InvalidTokenContract();

        // Register pair
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, swapFeeBps, allPairs.length);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Sort tokens by address
    function _sortTokens(address a, address b)
        internal
        pure
        returns (address token0, address token1)
    {
        if (a == b) revert IdenticalTokens();
        (token0, token1) = a < b ? (a, b) : (b, a);
        if (token0 == address(0)) revert ZeroAddress();
    }

    /// @dev Validate token is a valid ERC20 contract
    function _validateToken(address token) private view {
        // Check contract has code
        uint256 size;
        assembly {
            size := extcodesize(token)
        }
        if (size == 0) revert InvalidTokenContract();

        // Try to call totalSupply() to validate it's an ERC20
        (bool success, ) = token.staticcall(
            abi.encodeWithSelector(IERC20.totalSupply.selector)
        );
        if (!success) revert InvalidTokenContract();
    }

    /// @dev Get pair contract bytecode
    function _getPairBytecode(
        address token0,
        address token1,
        uint24 swapFeeBps
    ) private pure returns (bytes memory) {
        bytes memory bytecode = type(AMMPair).creationCode;
        return abi.encodePacked(
            bytecode,
            abi.encode(token0, token1, swapFeeBps)
        );
    }
}

/// @notice Import pair contract for bytecode access
import "./AMMPair.sol";
