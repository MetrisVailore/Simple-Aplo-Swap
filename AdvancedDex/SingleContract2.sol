// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IFactory {
    function feeTo() external view returns (address);
}

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface IAMMFlashCallee {
    function ammFlashCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

interface IAMMFactory {
    function getPair(address tokenA, address tokenB) external view returns (address);
    function createPair(address tokenA, address tokenB, uint24 swapFeeBps)
        external
        returns (address);
}

interface IAMMPair {
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function swapFeeBps() external view returns (uint24);

    function mint(address to)
        external
        returns (
            uint256 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

interface IAMMFlashLoanReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

/// @title AMM Pair Contract
/// @notice Implements a constant product AMM pair with protocol fees and price oracles
/// @dev Based on Uniswap V2 with improvements and bug fixes
contract AMMPair is ERC20, ERC20Permit, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    uint256 private constant MINIMUM_LIQUIDITY = 1_000;
    uint256 private constant INITIAL_MINIMUM_AMOUNT0 = 1_000;
    uint256 private constant INITIAL_MINIMUM_AMOUNT1 = 1_000;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable swapFeeBps;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    error OnlyFactory();
    error ZeroAddress();
    error IdenticalTokens();
    error InvalidFee();
    error Overflow();
    error InsufficientInitialLiquidity();
    error InsufficientLiquidityMinted();
    error InsufficientBurnAmount();
    error InsufficientOutput();
    error InsufficientLiquidity();
    error InvalidRecipient();
    error InsufficientInput();
    error KInvariantViolated();

    event Mint(
        address indexed sender,
        address indexed to,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    event Burn(
        address indexed sender,
        address indexed to,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    event Swap(
        address indexed sender,
        address indexed to,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out
    );

    event Sync(uint112 reserve0, uint112 reserve1);

    modifier onlyFactory() {
        if (msg.sender != factory) revert OnlyFactory();
        _;
    }

    constructor(
        address _token0,
        address _token1,
        uint24 _swapFeeBps
    ) ERC20("AMM LP Token", "AMMLP") ERC20Permit("AMM LP Token") {
        if (_token0 == address(0) || _token1 == address(0)) revert ZeroAddress();
        if (_token0 == _token1) revert IdenticalTokens();
        if (_swapFeeBps > BPS) revert InvalidFee();

        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
        swapFeeBps = _swapFeeBps;
    }

    function getReserves()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function currentCumulativePrices()
        public
        view
        returns (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        )
    {
        price0Cumulative = price0CumulativeLast;
        price1Cumulative = price1CumulativeLast;
        blockTimestamp = uint32(block.timestamp);

        uint112 _reserve0 = reserve0;
        uint112 _reserve1 = reserve1;
        uint32 _blockTimestampLast = blockTimestampLast;

        if (blockTimestamp > _blockTimestampLast && _reserve0 != 0 && _reserve1 != 0) {
            unchecked {
                uint32 timeElapsed = blockTimestamp - _blockTimestampLast;
                price0Cumulative += uint256(_reserve1) * (1 << 112) / _reserve0 * timeElapsed;
                price1Cumulative += uint256(_reserve0) * (1 << 112) / _reserve1 * timeElapsed;
            }
        }
    }

    function mint(address to)
        external
        nonReentrant
        returns (
            uint256 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        (uint112 _reserve0, uint112 _reserve1) = (reserve0, reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        amount0 = balance0 - _reserve0;
        amount1 = balance1 - _reserve1;

        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            if (amount0 < INITIAL_MINIMUM_AMOUNT0 || amount1 < INITIAL_MINIMUM_AMOUNT1) {
                revert InsufficientInitialLiquidity();
            }

            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            if (liquidity == 0) revert InsufficientLiquidityMinted();

            _mint(DEAD, MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(
                (amount0 * _totalSupply) / _reserve0,
                (amount1 * _totalSupply) / _reserve1
            );
        }

        if (liquidity == 0) revert InsufficientLiquidityMinted();

        _mint(to, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1);

        if (feeOn) kLast = uint256(reserve0) * reserve1;

        emit Mint(msg.sender, to, amount0, amount1, liquidity);
    }

    function burn(address to)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        (uint112 _reserve0, uint112 _reserve1) = (reserve0, reserve1);
        address _token0 = token0;
        address _token1 = token1;

        bool feeOn = _mintFee(_reserve0, _reserve1);

        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));
        uint256 _totalSupply = totalSupply();

        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        if (amount0 == 0 || amount1 == 0) revert InsufficientBurnAmount();

        _burn(address(this), liquidity);

        IERC20(_token0).safeTransfer(to, amount0);
        IERC20(_token1).safeTransfer(to, amount1);

        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);

        if (feeOn) kLast = uint256(reserve0) * reserve1;

        emit Burn(msg.sender, to, amount0, amount1, liquidity);
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external nonReentrant {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutput();

        (uint112 _reserve0, uint112 _reserve1) = (reserve0, reserve1);

        if (amount0Out >= _reserve0 || amount1Out >= _reserve1) {
            revert InsufficientLiquidity();
        }
        if (to == token0 || to == token1) revert InvalidRecipient();

        if (amount0Out > 0) IERC20(token0).safeTransfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).safeTransfer(to, amount1Out);

        if (data.length > 0) {
            IAMMFlashCallee(to).ammFlashCall(
                msg.sender,
                amount0Out,
                amount1Out,
                data
            );
        }

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > _reserve0 - amount0Out
            ? balance0 - (_reserve0 - amount0Out)
            : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out
            ? balance1 - (_reserve1 - amount1Out)
            : 0;

        if (amount0In == 0 && amount1In == 0) revert InsufficientInput();

        uint256 balance0Adjusted = (balance0 * BPS) - (amount0In * swapFeeBps);
        uint256 balance1Adjusted = (balance1 * BPS) - (amount1In * swapFeeBps);

        if (balance0Adjusted * balance1Adjusted < uint256(_reserve0) * _reserve1 * (BPS * BPS)) {
            revert KInvariantViolated();
        }

        _update(balance0, balance1, _reserve0, _reserve1);

        address feeTo = IFactory(factory).feeTo();
        if (feeTo != address(0)) {
            kLast = uint256(reserve0) * reserve1;
        } else if (kLast != 0) {
            kLast = 0;
        }

        emit Swap(msg.sender, to, amount0In, amount1In, amount0Out, amount1Out);
    }

    function skim(address to) external nonReentrant {
        address _token0 = token0;
        address _token1 = token1;

        IERC20(_token0).safeTransfer(to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        IERC20(_token1).safeTransfer(to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    function sync() external nonReentrant {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast;

        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
                uint256 rootKLast = Math.sqrt(_kLast);

                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply() * (rootK - rootKLast);
                    uint256 denominator = (rootK * 5) + rootKLast;
                    uint256 liquidity = numerator / denominator;

                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) {
            revert Overflow();
        }

        uint32 blockTimestamp = uint32(block.timestamp);

        unchecked {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;

            if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
                price0CumulativeLast += uint256(_reserve1) * (1 << 112) / _reserve0 * timeElapsed;
                price1CumulativeLast += uint256(_reserve0) * (1 << 112) / _reserve1 * timeElapsed;
            }
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;

        emit Sync(reserve0, reserve1);
    }
}

/// @notice Minimal factory interface
interface IFactory {
    function feeTo() external view returns (address);
}

/// @notice AMM Factory
/// @notice Creates and manages AMM pairs
/// @dev Implements deterministic pair creation with CREATE2
contract AMMFactory is ReentrancyGuard {
    address public immutable weth;

    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    error ZeroAddress();
    error IdenticalTokens();
    error PairExists();
    error InvalidFee();
    error Forbidden();
    error InvalidTokenContract();

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint24 swapFeeBps,
        uint256 pairIndex
    );

    event FeeToUpdated(address indexed feeTo);
    event FeeToSetterUpdated(address indexed feeToSetter);

    constructor(address wethAddress, address feeToSetter_) {
        if (wethAddress == address(0) || feeToSetter_ == address(0)) {
            revert ZeroAddress();
        }

        weth = wethAddress;
        feeToSetter = feeToSetter_;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function pairFor(address tokenA, address tokenB) external view returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = getPair[token0][token1];
        if (pair == address(0)) revert InvalidTokenContract();
    }

    function setFeeTo(address _feeTo) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        feeTo = _feeTo;
        emit FeeToUpdated(_feeTo);
    }

    function setFeeToSetter(address _feeToSetter) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        if (_feeToSetter == address(0)) revert ZeroAddress();

        feeToSetter = _feeToSetter;
        emit FeeToSetterUpdated(_feeToSetter);
    }

    function createPair(
        address tokenA,
        address tokenB,
        uint24 swapFeeBps
    ) external returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);

        if (getPair[token0][token1] != address(0)) revert PairExists();
        if (swapFeeBps > 10_000) revert InvalidFee();

        _validateToken(token0);
        _validateToken(token1);

        bytes memory bytecode = type(AMMPair).creationCode;
        bytes memory initCode = abi.encodePacked(
            bytecode,
            abi.encode(token0, token1, swapFeeBps)
        );
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        assembly {
            pair := create2(0, add(initCode, 32), mload(initCode), salt)
        }

        if (pair == address(0)) revert InvalidTokenContract();

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, swapFeeBps, allPairs.length);
    }

    function _sortTokens(address a, address b)
        internal
        pure
        returns (address token0, address token1)
    {
        if (a == b) revert IdenticalTokens();
        (token0, token1) = a < b ? (a, b) : (b, a);
        if (token0 == address(0)) revert ZeroAddress();
    }

    function _validateToken(address token) private view {
        uint256 size;
        assembly {
            size := extcodesize(token)
        }
        if (size == 0) revert InvalidTokenContract();

        (bool success, ) = token.staticcall(
            abi.encodeWithSelector(IERC20.totalSupply.selector)
        );
        if (!success) revert InvalidTokenContract();
    }
}

/// @title AMM Router
/// @notice Router for AMM operations with deadline protection and safety checks
/// @dev Handles swaps, liquidity provision, and supports native ETH via WETH
contract AMMRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable factory;
    address public immutable weth;

    error ZeroAddress();
    error IdenticalTokens();
    error ZeroAmount();
    error TransactionExpired();
    error SlippageExceeded();
    error InvalidPath();
    error InvalidEthAmount();
    error PathMustStartWithWeth();
    error PathMustEndWithWeth();
    error EthTransferFailed();
    error InvalidReserves();
    error PairMissing();
    error SwapFeeMismatch();

    event LiquidityAdded(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity,
        address indexed to
    );

    event LiquidityRemoved(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity,
        address indexed to
    );

    event TokensSwapped(
        address indexed sender,
        address[] path,
        uint256[] amounts,
        address indexed to
    );

    constructor(address factory_, address weth_) {
        if (factory_ == address(0) || weth_ == address(0)) revert ZeroAddress();

        factory = factory_;
        weth = weth_;
    }

    receive() external payable {
        if (msg.sender != weth) revert InvalidEthAmount();
    }

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure returns (uint256 amountB) {
        if (amountA == 0) revert ZeroAmount();
        if (reserveA == 0 || reserveB == 0) revert InvalidReserves();

        amountB = (amountA * reserveB) / reserveA;
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint24 swapFeeBps
    ) public pure returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InvalidReserves();

        uint256 amountInWithFee = amountIn * (10_000 - swapFeeBps);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 10_000) + amountInWithFee;

        amountOut = numerator / denominator;
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        uint24 swapFeeBps
    ) public pure returns (uint256 amountIn) {
        if (amountOut == 0) revert ZeroAmount();
        if (reserveIn == 0 || reserveOut == 0 || amountOut >= reserveOut) {
            revert InvalidReserves();
        }

        uint256 numerator = reserveIn * amountOut * 10_000;
        uint256 denominator = (reserveOut - amountOut) * (10_000 - swapFeeBps);

        amountIn = (numerator / denominator) + 1;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        public
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) revert InvalidPath();

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i; i < path.length - 1; ) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(path[i], path[i + 1]);
            address pair = _pairFor(path[i], path[i + 1]);
            uint24 fee = IAMMPair(pair).swapFeeBps();

            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, fee);

            unchecked {
                ++i;
            }
        }
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        public
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) revert InvalidPath();

        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;

        for (uint256 i = path.length - 1; i > 0; ) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(path[i - 1], path[i]);
            address pair = _pairFor(path[i - 1], path[i]);
            uint24 fee = IAMMPair(pair).swapFeeBps();

            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut, fee);

            unchecked {
                --i;
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        uint24 swapFeeBps
    )
        external
        payable
        nonReentrant
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        if (block.timestamp > deadline) revert TransactionExpired();
        if (amountADesired == 0 || amountBDesired == 0) revert ZeroAmount();

        address pair = _ensurePair(tokenA, tokenB, swapFeeBps);

        (amountA, amountB) = _calculateLiquidityAmounts(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );

        uint256 ethRequired = tokenA == weth ? amountA : tokenB == weth ? amountB : 0;
        if (msg.value != ethRequired) revert InvalidEthAmount();

        _transferTokensToPair(tokenA, tokenB, amountA, amountB, pair);

        (liquidity, , ) = IAMMPair(pair).mint(to);

        emit LiquidityAdded(tokenA, tokenB, amountA, amountB, liquidity, to);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public nonReentrant returns (uint256 amountA, uint256 amountB) {
        if (block.timestamp > deadline) revert TransactionExpired();
        if (liquidity == 0) revert ZeroAmount();

        address pair = _pairFor(tokenA, tokenB);

        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);

        (uint256 amount0, uint256 amount1) = IAMMPair(pair).burn(address(this));

        (address token0, ) = _sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);

        if (amountA < amountAMin || amountB < amountBMin) revert SlippageExceeded();

        _transferTokensToRecipient(tokenA, tokenB, amountA, amountB, to);

        emit LiquidityRemoved(tokenA, tokenB, amountA, amountB, liquidity, to);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB) {
        address pair = _pairFor(tokenA, tokenB);

        IAMMPair(pair).permit(msg.sender, address(this), liquidity, deadline, v, r, s);

        return removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts) {
        if (block.timestamp > deadline) revert TransactionExpired();
        if (path.length < 2) revert InvalidPath();

        amounts = getAmountsOut(amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert SlippageExceeded();

        IERC20(path[0]).safeTransferFrom(
            msg.sender,
            _pairFor(path[0], path[1]),
            amounts[0]
        );

        _swap(amounts, path, to);

        emit TokensSwapped(msg.sender, path, amounts, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable nonReentrant returns (uint256[] memory amounts) {
        if (block.timestamp > deadline) revert TransactionExpired();
        if (path.length < 2) revert InvalidPath();
        if (path[0] != weth) revert PathMustStartWithWeth();

        amounts = getAmountsOut(msg.value, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert SlippageExceeded();

        IWETH9(weth).deposit{value: amounts[0]}();
        IERC20(weth).safeTransfer(_pairFor(path[0], path[1]), amounts[0]);

        _swap(amounts, path, to);

        emit TokensSwapped(msg.sender, path, amounts, to);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts) {
        if (block.timestamp > deadline) revert TransactionExpired();
        if (path.length < 2) revert InvalidPath();
        if (path[path.length - 1] != weth) revert PathMustEndWithWeth();

        amounts = getAmountsOut(amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert SlippageExceeded();

        IERC20(path[0]).safeTransferFrom(
            msg.sender,
            _pairFor(path[0], path[1]),
            amounts[0]
        );

        _swap(amounts, path, address(this));

        IWETH9(weth).withdraw(amounts[amounts.length - 1]);
        (bool success, ) = payable(to).call{value: amounts[amounts.length - 1]}("");
        if (!success) revert EthTransferFailed();

        emit TokensSwapped(msg.sender, path, amounts, to);
    }

    function _sortTokens(address a, address b)
        internal
        pure
        returns (address token0, address token1)
    {
        if (a == b) revert IdenticalTokens();
        (token0, token1) = a < b ? (a, b) : (b, a);
        if (token0 == address(0)) revert ZeroAddress();
    }

    function _pairFor(address tokenA, address tokenB) internal view returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = IAMMFactory(factory).getPair(token0, token1);
        if (pair == address(0)) revert PairMissing();
    }

    function _getReserves(address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        address pair = _pairFor(tokenA, tokenB);
        (address token0, ) = _sortTokens(tokenA, tokenB);
        (uint112 reserve0, uint112 reserve1, ) = IAMMPair(pair).getReserves();

        (reserveA, reserveB) = tokenA == token0
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));
    }

    function _ensurePair(
        address tokenA,
        address tokenB,
        uint24 swapFeeBps
    ) internal returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = IAMMFactory(factory).getPair(token0, token1);

        if (pair == address(0)) {
            pair = IAMMFactory(factory).createPair(tokenA, tokenB, swapFeeBps);
        } else {
            uint24 existingFee = IAMMPair(pair).swapFeeBps();
            if (existingFee != swapFeeBps) revert SwapFeeMismatch();
        }
    }

    function _calculateLiquidityAmounts(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        (uint256 reserveA, uint256 reserveB) = _getReserves(tokenA, tokenB);

        if (reserveA == 0 && reserveB == 0) {
            return (amountADesired, amountBDesired);
        }

        uint256 amountBOptimal = quote(amountADesired, reserveA, reserveB);

        if (amountBOptimal <= amountBDesired) {
            if (amountBOptimal < amountBMin) revert SlippageExceeded();
            return (amountADesired, amountBOptimal);
        }

        uint256 amountAOptimal = quote(amountBDesired, reserveB, reserveA);
        if (amountAOptimal > amountADesired || amountAOptimal < amountAMin) {
            revert SlippageExceeded();
        }

        return (amountAOptimal, amountBDesired);
    }

    function _transferTokensToPair(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address pair
    ) internal {
        if (tokenA == weth) {
            IWETH9(weth).deposit{value: amountA}();
            IERC20(weth).safeTransfer(pair, amountA);
        } else {
            IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        }

        if (tokenB == weth) {
            IWETH9(weth).deposit{value: amountB}();
            IERC20(weth).safeTransfer(pair, amountB);
        } else {
            IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
        }
    }

    function _transferTokensToRecipient(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address to
    ) internal {
        if (tokenA == weth) {
            IWETH9(weth).withdraw(amountA);
            (bool success, ) = payable(to).call{value: amountA}("");
            if (!success) revert EthTransferFailed();
        } else {
            IERC20(tokenA).safeTransfer(to, amountA);
        }

        if (tokenB == weth) {
            IWETH9(weth).withdraw(amountB);
            (bool success, ) = payable(to).call{value: amountB}("");
            if (!success) revert EthTransferFailed();
        } else {
            IERC20(tokenB).safeTransfer(to, amountB);
        }
    }

    function _swap(
        uint256[] memory amounts,
        address[] calldata path,
        address to
    ) internal {
        for (uint256 i; i < path.length - 1; ) {
            address input = path[i];
            address output = path[i + 1];
            address pair = _pairFor(input, output);

            address recipient = i < path.length - 2
                ? _pairFor(output, path[i + 2])
                : to;

            (address token0, ) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));

            IAMMPair(pair).swap(amount0Out, amount1Out, recipient, new bytes(0));

            unchecked {
                ++i;
            }
        }
    }
}

/// @title AMM Flash Loan Provider
/// @notice Aave-style single-asset flash loans funded by this contract's token balance
contract AMMFlashLoanProvider is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable treasury;
    uint16 public immutable flashLoanFeeBps;

    error ZeroAddress();
    error ZeroAmount();
    error InvalidFee();
    error InsufficientLiquidity();
    error FlashLoanNotRepaid();

    event FlashLoan(
        address indexed receiver,
        address indexed asset,
        uint256 amount,
        uint256 premium,
        address indexed initiator
    );

    constructor(address treasury_, uint16 flashLoanFeeBps_) {
        if (treasury_ == address(0)) revert ZeroAddress();
        if (flashLoanFeeBps_ > 10_000) revert InvalidFee();

        treasury = treasury_;
        flashLoanFeeBps = flashLoanFeeBps_;
    }

    function flashLoan(
        address receiver,
        address asset,
        uint256 amount,
        bytes calldata params
    ) external nonReentrant {
        if (receiver == address(0) || asset == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20 token = IERC20(asset);

        uint256 balanceBefore = token.balanceOf(address(this));
        if (balanceBefore < amount) revert InsufficientLiquidity();

        uint256 premium = (amount * flashLoanFeeBps) / 10_000;

        token.safeTransfer(receiver, amount);

        bool ok = IAMMFlashLoanReceiver(receiver).executeOperation(
            asset,
            amount,
            premium,
            msg.sender,
            params
        );
        if (!ok) revert FlashLoanNotRepaid();

        token.safeTransferFrom(receiver, address(this), amount + premium);

        uint256 balanceAfter = token.balanceOf(address(this));
        if (balanceAfter < balanceBefore + premium) revert FlashLoanNotRepaid();

        if (premium > 0) {
            token.safeTransfer(treasury, premium);
        }

        emit FlashLoan(receiver, asset, amount, premium, msg.sender);
    }
}
