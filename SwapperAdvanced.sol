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

contract Token is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address recipient_
    ) ERC20(name_, symbol_) {
        _mint(recipient_, totalSupply_);
    }
}

contract Swapper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Pool {
        address token0;
        address token1;
        uint256 reserve0;
        uint256 reserve1;
        uint24 swapFeeBps;
        bool exists;
    }

    IWETH9 public immutable weth;
    uint256 public immutable minimumLiquidity;
    uint24 public immutable maxSwapFeeBps;

    mapping(bytes32 => Pool) public pools;
    mapping(bytes32 => mapping(address => uint256)) private _lpBalance;
    mapping(bytes32 => uint256) public lpTotalSupply;
    bytes32[] public poolIds;

    event PoolCreated(
        bytes32 indexed poolId,
        address indexed provider,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidityMinted,
        uint24 swapFeeBps
    );

    event LiquidityAdded(
        bytes32 indexed poolId,
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidityMinted
    );

    event LiquidityRemoved(
        bytes32 indexed poolId,
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidityBurned
    );

    event Swap(
        address indexed user,
        bytes32 indexed poolId,
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOut
    );

    constructor(
        address wethAddress,
        uint256 minimumLiquidity_,
        uint24 maxSwapFeeBps_
    ) {
        require(wethAddress != address(0), "WETH address cannot be zero");
        require(maxSwapFeeBps_ <= 10000, "Invalid max fee");

        weth = IWETH9(wethAddress);
        minimumLiquidity = minimumLiquidity_;
        maxSwapFeeBps = maxSwapFeeBps_;
    }

    function _sortTokens(address a, address b)
        internal
        pure
        returns (address token0, address token1)
    {
        require(a != b, "Identical tokens not allowed");
        (token0, token1) = a < b ? (a, b) : (b, a);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _sendETH(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    function _pullToken(address token, uint256 amount) internal {
        if (token == address(weth)) {
            weth.deposit{value: amount}();
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function _pushToken(address token, address to, uint256 amount) internal {
        if (token == address(weth)) {
            weth.withdraw(amount);
            _sendETH(to, amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function getPoolId(address tokenA, address tokenB)
        public
        pure
        returns (bytes32)
    {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        return keccak256(abi.encodePacked(token0, token1));
    }

    function getLPBalance(bytes32 poolId, address user)
        external
        view
        returns (uint256)
    {
        return _lpBalance[poolId][user];
    }

    function getReserves(bytes32 poolId)
        external
        view
        returns (uint256 reserve0, uint256 reserve1)
    {
        Pool storage pool = pools[poolId];
        require(pool.exists, "Pool does not exist");
        return (pool.reserve0, pool.reserve1);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint24 swapFeeBps
    ) public pure returns (uint256) {
        require(amountIn > 0, "amountIn=0");
        require(reserveIn > 0 && reserveOut > 0, "Invalid reserves");
        require(swapFeeBps <= 10000, "Invalid fee");

        uint256 amountInWithFee = amountIn * (10000 - swapFeeBps);
        return (amountInWithFee * reserveOut) /
            (reserveIn * 10000 + amountInWithFee);
    }

    function createPool(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint24 swapFeeBps
    ) external payable nonReentrant returns (bytes32 poolId, uint256 liquidity) {
        require(amountA > 0 && amountB > 0, "Amounts must be > 0");
        require(swapFeeBps <= maxSwapFeeBps, "Swap fee exceeds max");
        require(amountA >= minimumLiquidity && amountB >= minimumLiquidity, "Below minimum liquidity");

        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        poolId = getPoolId(token0, token1);
        require(!pools[poolId].exists, "Pool already exists");

        (uint256 amount0, uint256 amount1) =
            tokenA == token0 ? (amountA, amountB) : (amountB, amountA);

        uint256 ethRequired =
            token0 == address(weth) ? amount0 :
            token1 == address(weth) ? amount1 :
            0;

        require(msg.value == ethRequired, "Incorrect ETH sent");

        _pullToken(token0, amount0);
        _pullToken(token1, amount1);

        liquidity = Math.sqrt(Math.mulDiv(amount0, amount1, 1));
        require(liquidity > 0, "Insufficient liquidity minted");

        pools[poolId] = Pool({
            token0: token0,
            token1: token1,
            reserve0: amount0,
            reserve1: amount1,
            swapFeeBps: swapFeeBps,
            exists: true
        });

        lpTotalSupply[poolId] = liquidity;
        _lpBalance[poolId][msg.sender] = liquidity;
        poolIds.push(poolId);

        emit PoolCreated(
            poolId,
            msg.sender,
            token0,
            token1,
            amount0,
            amount1,
            liquidity,
            swapFeeBps
        );
    }

    function addLiquidity(
        bytes32 poolId,
        uint256 amount0,
        uint256 amount1
    ) external payable nonReentrant returns (uint256 liquidityMinted) {
        Pool storage pool = pools[poolId];
        require(pool.exists, "Pool does not exist");
        require(amount0 > 0 && amount1 > 0, "Amounts must be > 0");

        uint256 ethRequired =
            pool.token0 == address(weth) ? amount0 :
            pool.token1 == address(weth) ? amount1 :
            0;

        require(msg.value == ethRequired, "Incorrect ETH sent");

        uint256 totalSupply = lpTotalSupply[poolId];

        if (totalSupply == 0 || pool.reserve0 == 0 || pool.reserve1 == 0) {
            liquidityMinted = Math.sqrt(Math.mulDiv(amount0, amount1, 1));
        } else {
            uint256 liquidity0 = Math.mulDiv(amount0, totalSupply, pool.reserve0);
            uint256 liquidity1 = Math.mulDiv(amount1, totalSupply, pool.reserve1);
            require(liquidity0 == liquidity1, "Liquidity must be proportional");
            liquidityMinted = liquidity0;
        }

        require(liquidityMinted > 0, "Insufficient liquidity minted");

        _pullToken(pool.token0, amount0);
        _pullToken(pool.token1, amount1);

        pool.reserve0 += amount0;
        pool.reserve1 += amount1;

        lpTotalSupply[poolId] = totalSupply + liquidityMinted;
        _lpBalance[poolId][msg.sender] += liquidityMinted;

        emit LiquidityAdded(poolId, msg.sender, amount0, amount1, liquidityMinted);
    }

    function removeLiquidity(
        bytes32 poolId,
        uint256 liquidity
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        Pool storage pool = pools[poolId];
        require(pool.exists, "Pool does not exist");
        require(liquidity > 0, "Liquidity=0");

        uint256 userBalance = _lpBalance[poolId][msg.sender];
        require(userBalance >= liquidity, "Not enough LP balance");

        uint256 totalSupply = lpTotalSupply[poolId];
        require(totalSupply > 0, "No LP supply");

        amount0 = Math.mulDiv(liquidity, pool.reserve0, totalSupply);
        amount1 = Math.mulDiv(liquidity, pool.reserve1, totalSupply);

        require(amount0 > 0 && amount1 > 0, "Insufficient withdrawal");

        _lpBalance[poolId][msg.sender] = userBalance - liquidity;
        lpTotalSupply[poolId] = totalSupply - liquidity;

        pool.reserve0 -= amount0;
        pool.reserve1 -= amount1;

        _pushToken(pool.token0, msg.sender, amount0);
        _pushToken(pool.token1, msg.sender, amount1);

        emit LiquidityRemoved(poolId, msg.sender, amount0, amount1, liquidity);
    }

    function swap(
        bytes32 poolId,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external payable nonReentrant returns (uint256 amountOut) {
        Pool storage pool = pools[poolId];
        require(pool.exists, "Pool does not exist");
        require(amountIn > 0, "amountIn=0");
        require(tokenIn == pool.token0 || tokenIn == pool.token1, "Invalid tokenIn");

        bool zeroForOne = tokenIn == pool.token0;
        address tokenOut = zeroForOne ? pool.token1 : pool.token0;

        uint256 reserveIn = zeroForOne ? pool.reserve0 : pool.reserve1;
        uint256 reserveOut = zeroForOne ? pool.reserve1 : pool.reserve0;

        if (tokenIn == address(weth)) {
            require(msg.value == amountIn, "Incorrect ETH sent");
            weth.deposit{value: amountIn}();
        } else {
            require(msg.value == 0, "ETH not allowed");
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut, pool.swapFeeBps);
        require(amountOut >= minAmountOut, "Slippage");
        require(amountOut < reserveOut, "Insufficient liquidity");

        if (zeroForOne) {
            pool.reserve0 += amountIn;
            pool.reserve1 -= amountOut;
        } else {
            pool.reserve1 += amountIn;
            pool.reserve0 -= amountOut;
        }

        _pushToken(tokenOut, msg.sender, amountOut);

        emit Swap(msg.sender, poolId, tokenIn, amountIn, tokenOut, amountOut);
    }

    function getAllPools()
        external
        view
        returns (Pool[] memory allPools, bytes32[] memory ids)
    {
        uint256 len = poolIds.length;
        allPools = new Pool[](len);

        for (uint256 i = 0; i < len; i++) {
            allPools[i] = pools[poolIds[i]];
        }

        return (allPools, poolIds);
    }

    receive() external payable {
        require(msg.sender == address(weth), "Direct ETH deposits not allowed");
    }
}
