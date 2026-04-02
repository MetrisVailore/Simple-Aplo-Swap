
// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Math.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface IAMMFactory {
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function getPair(address tokenA, address tokenB) external view returns (address);
}

contract AMMPair is ERC20, ERC20Permit, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    uint256 private constant MINIMUM_LIQUIDITY = 1_000;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    address public immutable factory;
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    uint24 public swapFeeBps;
    bool public initialized;

    event Mint(address indexed sender, address indexed to, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Burn(address indexed sender, address indexed to, uint256 amount0, uint256 amount1, uint256 liquidity);
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
        require(msg.sender == factory, "ONLY_FACTORY");
        _;
    }

    constructor() ERC20("AMM LP Token", "AMMLP") ERC20Permit("AMM LP Token") {
        factory = msg.sender;
    }

    function initialize(address _token0, address _token1, uint24 _swapFeeBps) external onlyFactory {
        require(!initialized, "ALREADY_INITIALIZED");
        require(_token0 != address(0) && _token1 != address(0), "ZERO_TOKEN");
        require(_token0 != _token1, "IDENTICAL_TOKENS");
        require(_swapFeeBps <= BPS, "BAD_FEE");

        token0 = _token0;
        token1 = _token1;
        swapFeeBps = _swapFeeBps;
        initialized = true;
    }

    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function currentCumulativePrices()
        public
        view
        returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp)
    {
        price0Cumulative = price0CumulativeLast;
        price1Cumulative = price1CumulativeLast;
        blockTimestamp = uint32(block.timestamp % 2 ** 32);

        if (blockTimestamp > blockTimestampLast) {
            uint256 timeElapsed = blockTimestamp - blockTimestampLast;
            if (reserve0 != 0 && reserve1 != 0) {
                price0Cumulative += (uint256(reserve1) << 112) / reserve0 * timeElapsed;
                price1Cumulative += (uint256(reserve0) << 112) / reserve1 * timeElapsed;
            }
        }
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) internal returns (bool feeOn) {
        address feeTo = IAMMFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast;

        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0) * uint256(_reserve1));
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

    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) internal {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "OVERFLOW");

        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            price0CumulativeLast += (uint256(_reserve1) << 112) / _reserve0 * timeElapsed;
            price1CumulativeLast += (uint256(_reserve0) << 112) / _reserve1 * timeElapsed;
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        IERC20(token).safeTransfer(to, value);
    }

    function mint(address to)
        external
        nonReentrant
        returns (uint256 liquidity, uint256 amount0, uint256 amount1)
    {
        (uint112 _reserve0, uint112 _reserve1, ) = (reserve0, reserve1, blockTimestampLast);
        bool feeOn = _mintFee(_reserve0, _reserve1);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        amount0 = balance0 - _reserve0;
        amount1 = balance1 - _reserve1;

        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            require(liquidity > 0, "INSUFFICIENT_INITIAL_LIQUIDITY");
            _mint(DEAD, MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }

        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1);

        if (feeOn) kLast = uint256(reserve0) * uint256(reserve1);

        emit Mint(msg.sender, to, amount0, amount1, liquidity);
    }

    function burn(address to)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        (uint112 _reserve0, uint112 _reserve1, ) = (reserve0, reserve1, blockTimestampLast);
        bool feeOn = _mintFee(_reserve0, _reserve1);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));
        uint256 _totalSupply = totalSupply();

        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "INSUFFICIENT_BURN_AMOUNT");

        _burn(address(this), liquidity);
        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
        _update(balance0, balance1, _reserve0, _reserve1);

        if (feeOn) kLast = uint256(reserve0) * uint256(reserve1);

        emit Burn(msg.sender, to, amount0, amount1, liquidity);
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, "INSUFFICIENT_OUTPUT");
        require(amount0Out < reserve0 && amount1Out < reserve1, "INSUFFICIENT_LIQUIDITY");
        require(to != token0 && to != token1, "BAD_TO");

        (uint112 _reserve0, uint112 _reserve1, ) = (reserve0, reserve1, blockTimestampLast);

        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > uint256(_reserve0) - amount0Out ? balance0 - (uint256(_reserve0) - amount0Out) : 0;
        uint256 amount1In = balance1 > uint256(_reserve1) - amount1Out ? balance1 - (uint256(_reserve1) - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "INSUFFICIENT_INPUT");

        uint256 balance0Adjusted = (balance0 * BPS) - (amount0In * swapFeeBps);
        uint256 balance1Adjusted = (balance1 * BPS) - (amount1In * swapFeeBps);
        require(
            balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * uint256(_reserve1) * (BPS * BPS),
            "K_INVARIANT"
        );

        _update(balance0, balance1, _reserve0, _reserve1);

        if (IAMMFactory(factory).feeTo() != address(0)) {
            kLast = uint256(reserve0) * uint256(reserve1);
        } else if (kLast != 0) {
            kLast = 0;
        }

        emit Swap(msg.sender, to, amount0In, amount1In, amount0Out, amount1Out);
    }

    function skim(address to) external nonReentrant {
        _safeTransfer(token0, to, IERC20(token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(token1, to, IERC20(token1).balanceOf(address(this)) - reserve1);
    }

    function sync() external nonReentrant {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }
}

contract AMMFactory is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable weth;
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint24 swapFeeBps);
    event FeeToUpdated(address indexed feeTo);
    event FeeToSetterUpdated(address indexed feeToSetter);

    constructor(address wethAddress, address feeToSetter_) {
        require(wethAddress != address(0), "WETH_ZERO");
        require(feeToSetter_ != address(0), "FEESETTER_ZERO");
        weth = wethAddress;
        feeToSetter = feeToSetter_;
    }

    function _sortTokens(address a, address b) internal pure returns (address token0, address token1) {
        require(a != b, "IDENTICAL_TOKENS");
        (token0, token1) = a < b ? (a, b) : (b, a);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        feeTo = _feeTo;
        emit FeeToUpdated(_feeTo);
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        feeToSetter = _feeToSetter;
        emit FeeToSetterUpdated(_feeToSetter);
    }

    function createPair(address tokenA, address tokenB, uint24 swapFeeBps) external returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        require(getPair[token0][token1] == address(0), "PAIR_EXISTS");
        require(swapFeeBps <= 10_000, "BAD_FEE");

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        AMMPair newPair = new AMMPair{salt: salt}();
        newPair.initialize(token0, token1, swapFeeBps);
        pair = address(newPair);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, swapFeeBps);
    }

    function pairFor(address tokenA, address tokenB) public view returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = getPair[token0][token1];
        require(pair != address(0), "PAIR_MISSING");
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
}

contract AMMRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable factory;
    address public immutable weth;

    constructor(address factory_, address weth_) {
        require(factory_ != address(0) && weth_ != address(0), "ZERO_ADDRESS");
        factory = factory_;
        weth = weth_;
    }

    receive() external payable {
        require(msg.sender == weth, "ETH_NOT_ALLOWED");
    }

    function _sortTokens(address a, address b) internal pure returns (address token0, address token1) {
        require(a != b, "IDENTICAL_TOKENS");
        (token0, token1) = a < b ? (a, b) : (b, a);
    }

    function _pairFor(address tokenA, address tokenB) internal view returns (address pair) {
        pair = AMMFactory(factory).pairFor(tokenA, tokenB);
    }

    function _getReserves(address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
        address pair = _pairFor(tokenA, tokenB);
        (address token0, ) = _sortTokens(tokenA, tokenB);
        (uint112 reserve0, uint112 reserve1, ) = AMMPair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256) {
        require(amountA > 0, "AMOUNT_ZERO");
        require(reserveA > 0 && reserveB > 0, "BAD_RESERVES");
        return (amountA * reserveB) / reserveA;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint24 swapFeeBps)
        public
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "AMOUNT_ZERO");
        require(reserveIn > 0 && reserveOut > 0, "BAD_RESERVES");
        uint256 amountInWithFee = amountIn * (10_000 - swapFeeBps);
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * 10_000 + amountInWithFee);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint24 swapFeeBps)
        public
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "AMOUNT_ZERO");
        require(reserveIn > 0 && reserveOut > 0 && amountOut < reserveOut, "BAD_RESERVES");
        uint256 numerator = reserveIn * amountOut * 10_000;
        uint256 denominator = (reserveOut - amountOut) * (10_000 - swapFeeBps);
        amountIn = (numerator / denominator) + 1;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "BAD_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < path.length - 1; ) {
            address pair = _pairFor(path[i], path[i + 1]);
            (uint112 reserve0, uint112 reserve1, ) = AMMPair(pair).getReserves();
            (address token0, ) = _sortTokens(path[i], path[i + 1]);
            (uint256 reserveIn, uint256 reserveOut) = path[i] == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, AMMPair(pair).swapFeeBps());
            unchecked { ++i; }
        }
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "BAD_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;

        for (uint256 i = path.length - 1; i > 0; ) {
            address pair = _pairFor(path[i - 1], path[i]);
            (uint112 reserve0, uint112 reserve1, ) = AMMPair(pair).getReserves();
            (address token0, ) = _sortTokens(path[i - 1], path[i]);
            (uint256 reserveIn, uint256 reserveOut) = path[i - 1] == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut, AMMPair(pair).swapFeeBps());
            unchecked { --i; }
        }
    }

    function _ensurePair(address tokenA, address tokenB, uint24 swapFeeBps) internal returns (address pair) {
        pair = AMMFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = AMMFactory(factory).createPair(tokenA, tokenB, swapFeeBps);
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint24 swapFeeBps
    ) external payable nonReentrant returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(amountADesired > 0 && amountBDesired > 0, "ZERO_AMOUNT");

        address pair = _ensurePair(tokenA, tokenB, swapFeeBps);
        AMMPair p = AMMPair(pair);

        (address token0, ) = _sortTokens(tokenA, tokenB);
        (uint112 reserve0, uint112 reserve1, ) = p.getReserves();

        (uint256 reserveA, uint256 reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);

        if (reserveA == 0 && reserveB == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            uint256 amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "SLIPPAGE");
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                require(amountAOptimal >= amountAMin, "SLIPPAGE");
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }

        require(amountA >= amountAMin && amountB >= amountBMin, "SLIPPAGE");

        uint256 ethRequired = tokenA == weth ? amountA : tokenB == weth ? amountB : 0;
        require(msg.value == ethRequired, "BAD_ETH");

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

        liquidity = p.mint(msg.sender);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin
    ) public nonReentrant returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0, "LIQUIDITY_ZERO");

        address pair = _pairFor(tokenA, tokenB);
        AMMPair p = AMMPair(pair);

        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = p.burn(address(this));

        (address token0, ) = _sortTokens(tokenA, tokenB);
        if (tokenA == token0) {
            amountA = amount0;
            amountB = amount1;
        } else {
            amountA = amount1;
            amountB = amount0;
        }

        require(amountA >= amountAMin && amountB >= amountBMin, "SLIPPAGE");

        if (tokenA == weth) {
            IWETH9(weth).withdraw(amountA);
            (bool okA, ) = payable(msg.sender).call{value: amountA}("");
            require(okA, "ETH_SEND_FAIL");
        } else {
            IERC20(tokenA).safeTransfer(msg.sender, amountA);
        }

        if (tokenB == weth) {
            IWETH9(weth).withdraw(amountB);
            (bool okB, ) = payable(msg.sender).call{value: amountB}("");
            require(okB, "ETH_SEND_FAIL");
        } else {
            IERC20(tokenB).safeTransfer(msg.sender, amountB);
        }
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB) {
        address pair = _pairFor(tokenA, tokenB);
        AMMPair(pair).permit(msg.sender, address(this), liquidity, deadline, v, r, s);
        return removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(path.length >= 2, "BAD_PATH");
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "SLIPPAGE");

        IERC20(path[0]).safeTransferFrom(msg.sender, _pairFor(path[0], path[1]), amounts[0]);

        for (uint256 i = 0; i < path.length - 1; ) {
            address input = path[i];
            address output = path[i + 1];
            address pair = _pairFor(input, output);
            address recipient = i < path.length - 2 ? _pairFor(output, path[i + 2]) : to;

            (address token0, ) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));

            AMMPair(pair).swap(amount0Out, amount1Out, recipient);
            unchecked { ++i; }
        }
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external payable nonReentrant returns (uint256[] memory amounts) {
        require(path.length >= 2, "BAD_PATH");
        require(path[0] == weth, "PATH_MUST_START_WETH");

        amounts = getAmountsOut(msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "SLIPPAGE");

        IWETH9(weth).deposit{value: amounts[0]}();
        IERC20(weth).safeTransfer(_pairFor(path[0], path[1]), amounts[0]);

        for (uint256 i = 0; i < path.length - 1; ) {
            address input = path[i];
            address output = path[i + 1];
            address pair = _pairFor(input, output);
            address recipient = i < path.length - 2 ? _pairFor(output, path[i + 2]) : to;

            (address token0, ) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            AMMPair(pair).swap(amount0Out, amount1Out, recipient);
            unchecked { ++i; }
        }
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(path.length >= 2, "BAD_PATH");
        require(path[path.length - 1] == weth, "PATH_MUST_END_WETH");

        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "SLIPPAGE");

        IERC20(path[0]).safeTransferFrom(msg.sender, _pairFor(path[0], path[1]), amounts[0]);

        for (uint256 i = 0; i < path.length - 1; ) {
            address input = path[i];
            address output = path[i + 1];
            address pair = _pairFor(input, output);
            address recipient = i < path.length - 2 ? _pairFor(output, path[i + 2]) : address(this);

            (address token0, ) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            AMMPair(pair).swap(amount0Out, amount1Out, recipient);
            unchecked { ++i; }
        }

        IWETH9(weth).withdraw(amounts[amounts.length - 1]);
        (bool ok, ) = payable(to).call{value: amounts[amounts.length - 1]}("");
        require(ok, "ETH_SEND_FAIL");
    }
}
