// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract AMMPair is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public factory;
    address public token0;
    address public token1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint24 public swapFeeBps;
    bool public initialized;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

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
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOut
    );

    event Sync(uint256 reserve0, uint256 reserve1);

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    constructor() ERC20("AMM LP Token", "AMMLP") {
        factory = msg.sender;
    }

    function initialize(
        address _token0,
        address _token1,
        uint24 _swapFeeBps
    ) external onlyFactory {
        require(!initialized, "Already initialized");
        require(_token0 != address(0) && _token1 != address(0), "Zero token");
        require(_token0 != _token1, "Identical tokens");
        require(_swapFeeBps <= 10000, "Invalid fee");

        token0 = _token0;
        token1 = _token1;
        swapFeeBps = _swapFeeBps;
        initialized = true;
    }

    function getReserves()
        external
        view
        returns (uint256 _reserve0, uint256 _reserve1)
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    function _update(uint256 balance0, uint256 balance1) internal {
        reserve0 = balance0;
        reserve1 = balance1;
        emit Sync(balance0, balance1);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal view returns (uint256) {
        require(amountIn > 0, "amountIn=0");
        require(reserveIn > 0 && reserveOut > 0, "Invalid reserves");

        uint256 amountInWithFee = amountIn * (10000 - swapFeeBps);
        return (amountInWithFee * reserveOut) /
            (reserveIn * 10000 + amountInWithFee);
    }

    function mint(address to)
        external
        onlyFactory
        nonReentrant
        returns (uint256 liquidity, uint256 amount0, uint256 amount1)
    {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        amount0 = balance0 - reserve0;
        amount1 = balance1 - reserve1;

        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1);
            require(liquidity > MINIMUM_LIQUIDITY, "Insufficient initial liquidity");
            _mint(DEAD, MINIMUM_LIQUIDITY);
            liquidity -= MINIMUM_LIQUIDITY;
        } else {
            liquidity = _min(
                (amount0 * _totalSupply) / reserve0,
                (amount1 * _totalSupply) / reserve1
            );
        }

        require(liquidity > 0, "Insufficient liquidity minted");

        _mint(to, liquidity);
        _update(balance0, balance1);

        emit Mint(msg.sender, to, amount0, amount1, liquidity);
    }

    function burn(address to)
        external
        onlyFactory
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 liquidity = balanceOf(address(this));
        require(liquidity > 0, "No LP tokens");

        uint256 _totalSupply = totalSupply();
        require(_totalSupply > 0, "No supply");

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        require(amount0 > 0 && amount1 > 0, "Insufficient burn amount");

        _burn(address(this), liquidity);

        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
        _update(balance0, balance1);

        emit Burn(msg.sender, to, amount0, amount1, liquidity);
    }

    function swap(
        address tokenIn,
        address to,
        uint256 minAmountOut
    )
        external
        onlyFactory
        nonReentrant
        returns (uint256 amountOut, address tokenOut)
    {
        require(tokenIn == token0 || tokenIn == token1, "Invalid tokenIn");

        bool zeroForOne = tokenIn == token0;
        tokenOut = zeroForOne ? token1 : token0;

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amountIn = zeroForOne
            ? balance0 - reserve0
            : balance1 - reserve1;

        amountOut = _getAmountOut(
            amountIn,
            zeroForOne ? reserve0 : reserve1,
            zeroForOne ? reserve1 : reserve0
        );

        require(amountOut >= minAmountOut, "Slippage");
        require(amountOut < (zeroForOne ? reserve1 : reserve0), "Insufficient liquidity");

        IERC20(tokenOut).safeTransfer(to, amountOut);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
        _update(balance0, balance1);

        emit Swap(msg.sender, to, tokenIn, amountIn, tokenOut, amountOut);
    }
}

contract AMMFactory is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable weth;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint24 swapFeeBps
    );

    event LiquidityAdded(
        address indexed user,
        address indexed pair,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    event LiquidityRemoved(
        address indexed user,
        address indexed pair,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    event Swap(
        address indexed user,
        address indexed pair,
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOut
    );

    constructor(address wethAddress) {
        require(wethAddress != address(0), "WETH zero address");
        weth = wethAddress;
    }

    receive() external payable {
        require(msg.sender == weth, "Direct ETH not allowed");
    }

    function _sortTokens(address a, address b)
        internal
        pure
        returns (address token0, address token1)
    {
        require(a != b, "Identical tokens");
        (token0, token1) = a < b ? (a, b) : (b, a);
    }

    function _sendETH(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    function _quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256) {
        require(amountA > 0, "amountA=0");
        require(reserveA > 0 && reserveB > 0, "Invalid reserves");
        return (amountA * reserveB) / reserveA;
    }

    function _pushToken(address token, address to, uint256 amount) internal {
        if (token == weth) {
            IWETH9(weth).withdraw(amount);
            _sendETH(to, amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function createPair(
        address tokenA,
        address tokenB,
        uint24 swapFeeBps
    ) external returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        require(getPair[token0][token1] == address(0), "Pair exists");
        require(swapFeeBps <= 10000, "Invalid fee");

        AMMPair newPair = new AMMPair();
        newPair.initialize(token0, token1, swapFeeBps);

        pair = address(newPair);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, swapFeeBps);
    }

    function pairFor(address tokenA, address tokenB)
        public
        view
        returns (address pair)
    {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = getPair[token0][token1];
        require(pair != address(0), "Pair does not exist");
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    )
        external
        payable
        nonReentrant
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        require(amountADesired > 0 && amountBDesired > 0, "Zero amount");

        address pair = pairFor(tokenA, tokenB);
        AMMPair p = AMMPair(pair);

        (address token0, address token1) = (p.token0(), p.token1());
        (uint256 reserve0, uint256 reserve1) = p.getReserves();

        bool aIsToken0 = tokenA == token0;

        if (reserve0 == 0 && reserve1 == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
            require(amountA >= amountAMin && amountB >= amountBMin, "Slippage");
        } else {
            if (aIsToken0) {
                uint256 amountBOptimal = _quote(amountADesired, reserve0, reserve1);
                if (amountBOptimal <= amountBDesired) {
                    require(amountBOptimal >= amountBMin, "Slippage");
                    amountA = amountADesired;
                    amountB = amountBOptimal;
                } else {
                    uint256 amountAOptimal = _quote(amountBDesired, reserve1, reserve0);
                    require(amountAOptimal >= amountAMin, "Slippage");
                    amountA = amountAOptimal;
                    amountB = amountBDesired;
                }
            } else {
                uint256 amountAOptimal = _quote(amountBDesired, reserve1, reserve0);
                if (amountAOptimal <= amountADesired) {
                    require(amountAOptimal >= amountAMin, "Slippage");
                    amountA = amountAOptimal;
                    amountB = amountBDesired;
                } else {
                    uint256 amountBOptimal = _quote(amountADesired, reserve0, reserve1);
                    require(amountBOptimal >= amountBMin, "Slippage");
                    amountA = amountADesired;
                    amountB = amountBOptimal;
                }
            }
        }

        uint256 ethRequired =
            tokenA == weth ? amountA :
            tokenB == weth ? amountB :
            0;

        require(msg.value == ethRequired, "Incorrect ETH sent");

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

        (liquidity, , ) = p.mint(msg.sender);

        emit LiquidityAdded(msg.sender, pair, amountA, amountB, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin
    )
        external
        nonReentrant
        returns (uint256 amountA, uint256 amountB)
    {
        require(liquidity > 0, "Liquidity=0");

        address pair = pairFor(tokenA, tokenB);
        AMMPair p = AMMPair(pair);

        address token0 = p.token0();
        address token1 = p.token1();

        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = p.burn(address(this));

        if (tokenA == token0) {
            amountA = amount0;
            amountB = amount1;
        } else {
            amountA = amount1;
            amountB = amount0;
        }

        require(amountA >= amountAMin && amountB >= amountBMin, "Slippage");

        _pushToken(token0, msg.sender, amount0);
        _pushToken(token1, msg.sender, amount1);

        emit LiquidityRemoved(msg.sender, pair, amountA, amountB, liquidity);
    }

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external payable nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "amountIn=0");
        require(tokenIn != tokenOut, "Identical tokens");

        address pair = pairFor(tokenIn, tokenOut);
        AMMPair p = AMMPair(pair);

        require(tokenIn == p.token0() || tokenIn == p.token1(), "Invalid tokenIn");
        require(tokenOut == p.token0() || tokenOut == p.token1(), "Invalid tokenOut");

        uint256 ethRequired = tokenIn == weth ? amountIn : 0;
        require(msg.value == ethRequired, "Incorrect ETH sent");

        if (tokenIn == weth) {
            IWETH9(weth).deposit{value: amountIn}();
            IERC20(weth).safeTransfer(pair, amountIn);
        } else {
            require(msg.value == 0, "ETH not allowed");
            IERC20(tokenIn).safeTransferFrom(msg.sender, pair, amountIn);
        }

        (amountOut, address actualTokenOut) = p.swap(tokenIn, address(this), minAmountOut);
        require(actualTokenOut == tokenOut, "Wrong output token");

        _pushToken(tokenOut, msg.sender, amountOut);

        emit Swap(msg.sender, pair, tokenIn, amountIn, tokenOut, amountOut);
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
}
