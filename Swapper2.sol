// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
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

contract Swapper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct LiquidityPool {
        uint256 token0Reserve;
        uint256 token1Reserve;
        address token0;
        address token1;
        address poolOwner;
        uint256 swapFee; // in bps
        bool locked;
    }

    IWETH9 public weth;

    mapping(bytes32 => LiquidityPool) public pools;
    mapping(address => bytes32[]) public userPools;
    bytes32[] public poolIds;

    uint256 public minimumLiquidity;
    uint256 public maxSwapFee;
    uint256 public maxDevFee;

    address public devAddress;
    uint256 public devFee; // in bps

    event LiquidityLocked(bytes32 indexed poolId);

    event Swap(
        address indexed user,
        bytes32 indexed poolId,
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOut
    );

    event LiquidityAdded(
        address indexed user,
        bytes32 indexed poolId,
        uint256 amount0,
        uint256 amount1,
        uint256 newToken0Reserve,
        uint256 newToken1Reserve
    );

    event LiquidityRemoved(
        address indexed user,
        bytes32 indexed poolId,
        uint256 amount0,
        uint256 amount1,
        uint256 newToken0Reserve,
        uint256 newToken1Reserve
    );

    constructor(
        address wethAddress,
        uint256 initialMinimumLiquidity,
        uint256 initialMaxSwapFee,
        uint256 initialMaxDevFee,
        address initialDevAddress
    ) Ownable(msg.sender) {
        require(wethAddress != address(0), "WETH address cannot be zero");
        require(initialDevAddress != address(0), "Dev address cannot be zero");

        weth = IWETH9(wethAddress);
        minimumLiquidity = initialMinimumLiquidity;
        maxSwapFee = initialMaxSwapFee;
        maxDevFee = initialMaxDevFee;
        devAddress = initialDevAddress;
    }

    // ========================= Internal Helpers =========================

    function _sortTokens(address a, address b)
        internal
        pure
        returns (address token0, address token1)
    {
        require(a != b, "Identical tokens not allowed");
        (token0, token1) = a < b ? (a, b) : (b, a);
    }

    function _sendETH(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    // ========================= Admin Functions =========================

    function setMinimumLiquidity(uint256 newMinimumLiquidity) external onlyOwner {
        require(newMinimumLiquidity > 0, "Minimum liquidity must be > 0");
        minimumLiquidity = newMinimumLiquidity;
    }

    function setMaxSwapFee(uint256 newMaxSwapFee) external onlyOwner {
        require(newMaxSwapFee <= 10000, "Max swap fee must be <= 100%");
        maxSwapFee = newMaxSwapFee;
    }

    function setMaxDevFee(uint256 newMaxDevFee) external onlyOwner {
        require(newMaxDevFee <= 10000, "Max dev fee must be <= 100%");
        maxDevFee = newMaxDevFee;
    }

    function setDevAddress(address newDevAddress) external onlyOwner {
        require(newDevAddress != address(0), "Dev address cannot be zero");
        devAddress = newDevAddress;
    }

    function setDevFee(uint256 newDevFee) external onlyOwner {
        require(newDevFee <= maxDevFee, "Dev fee exceeds max limit");
        devFee = newDevFee;
    }

    function setPoolSwapFee(bytes32 poolId, uint256 newSwapFee) external {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");
        require(msg.sender == pool.poolOwner, "Only pool owner can set fee");
        require(newSwapFee <= maxSwapFee, "Swap fee exceeds max limit");

        pool.swapFee = newSwapFee;
    }

    // ========================= Pool Management =========================

    function createPool(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 swapFee
    ) external payable nonReentrant {
        require(amountA >= minimumLiquidity, "Token A below minimum");
        require(amountB >= minimumLiquidity, "Token B below minimum");
        require(swapFee <= maxSwapFee, "Swap fee exceeds max limit");

        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        bytes32 poolId = getPoolId(token0, token1);
        require(pools[poolId].token0 == address(0), "Pool already exists");

        (uint256 amount0, uint256 amount1) =
            tokenA == token0 ? (amountA, amountB) : (amountB, amountA);

        uint256 ethAmount =
            token0 == address(weth) ? amount0 :
            token1 == address(weth) ? amount1 :
            0;

        require(msg.value == ethAmount, "Incorrect ETH sent");

        if (token0 == address(weth)) {
            weth.deposit{value: amount0}();
        } else {
            IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        }

        if (token1 == address(weth)) {
            weth.deposit{value: amount1}();
        } else {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
        }

        pools[poolId] = LiquidityPool({
            token0Reserve: amount0,
            token1Reserve: amount1,
            token0: token0,
            token1: token1,
            poolOwner: msg.sender,
            swapFee: swapFee,
            locked: false
        });

        userPools[msg.sender].push(poolId);
        poolIds.push(poolId);
    }

    // ========================= Liquidity Functions =========================

    function addLiquidity(
        bytes32 poolId,
        uint256 amount0,
        uint256 amount1
    ) external payable nonReentrant {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");

        uint256 ethAmount =
            pool.token0 == address(weth) ? amount0 :
            pool.token1 == address(weth) ? amount1 :
            0;

        require(msg.value == ethAmount, "Incorrect ETH sent");

        if (pool.token0Reserve != 0 && pool.token1Reserve != 0) {
            uint256 expectedAmount1 = (amount0 * pool.token1Reserve) / pool.token0Reserve;
            require(amount1 == expectedAmount1, "Liquidity must be proportional");
        }

        if (pool.token0 == address(weth)) {
            weth.deposit{value: amount0}();
        } else {
            IERC20(pool.token0).safeTransferFrom(msg.sender, address(this), amount0);
        }

        if (pool.token1 == address(weth)) {
            weth.deposit{value: amount1}();
        } else {
            IERC20(pool.token1).safeTransferFrom(msg.sender, address(this), amount1);
        }

        pool.token0Reserve += amount0;
        pool.token1Reserve += amount1;

        emit LiquidityAdded(
            msg.sender,
            poolId,
            amount0,
            amount1,
            pool.token0Reserve,
            pool.token1Reserve
        );
    }

    function lockLiquidity(bytes32 poolId) external {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");
        require(msg.sender == pool.poolOwner, "Only pool owner can lock");
        require(!pool.locked, "Liquidity already locked");

        pool.locked = true;
        emit LiquidityLocked(poolId);
    }

    function removeLiquidity(
        bytes32 poolId,
        uint256 amount0,
        uint256 amount1
    ) external nonReentrant {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");
        require(msg.sender == pool.poolOwner, "Only pool owner can remove");
        require(!pool.locked, "Liquidity is locked");

        require(pool.token0Reserve >= amount0, "Not enough Token0 reserve");
        require(pool.token1Reserve >= amount1, "Not enough Token1 reserve");

        pool.token0Reserve -= amount0;
        pool.token1Reserve -= amount1;

        if (pool.token0 == address(weth)) {
            weth.withdraw(amount0);
            _sendETH(msg.sender, amount0);
        } else {
            IERC20(pool.token0).safeTransfer(msg.sender, amount0);
        }

        if (pool.token1 == address(weth)) {
            weth.withdraw(amount1);
            _sendETH(msg.sender, amount1);
        } else {
            IERC20(pool.token1).safeTransfer(msg.sender, amount1);
        }

        emit LiquidityRemoved(
            msg.sender,
            poolId,
            amount0,
            amount1,
            pool.token0Reserve,
            pool.token1Reserve
        );
    }

    // ========================= Swap Function =========================

    function swap(
        bytes32 poolId,
        address tokenIn,
        uint256 amountIn
    ) external payable nonReentrant {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");
        require(amountIn > 0, "amountIn=0");
        require(tokenIn == pool.token0 || tokenIn == pool.token1, "Invalid tokenIn");

        bool zeroForOne = tokenIn == pool.token0;

        uint256 inputReserve = zeroForOne ? pool.token0Reserve : pool.token1Reserve;
        uint256 outputReserve = zeroForOne ? pool.token1Reserve : pool.token0Reserve;
        address tokenOut = zeroForOne ? pool.token1 : pool.token0;

        if (tokenIn == address(weth)) {
            require(msg.value == amountIn, "Incorrect ETH sent");
            weth.deposit{value: amountIn}();
        } else {
            require(msg.value == 0, "ETH not allowed");
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        uint256 devAmount = (amountIn * devFee) / 10000;
        uint256 amountAfterDevFee = amountIn - devAmount;

        uint256 amountOut = getSwapAmount(
            amountAfterDevFee,
            inputReserve,
            outputReserve,
            pool.swapFee
        );

        require(amountOut > 0 && amountOut < outputReserve, "Insufficient output");

        if (devAmount > 0) {
            IERC20(tokenIn).safeTransfer(devAddress, devAmount);
        }

        if (zeroForOne) {
            pool.token0Reserve += amountAfterDevFee;
            pool.token1Reserve -= amountOut;
        } else {
            pool.token1Reserve += amountAfterDevFee;
            pool.token0Reserve -= amountOut;
        }

        if (tokenOut == address(weth)) {
            weth.withdraw(amountOut);
            _sendETH(msg.sender, amountOut);
        } else {
            IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        }

        emit Swap(msg.sender, poolId, tokenIn, amountIn, tokenOut, amountOut);
    }

    // ========================= Helper Functions =========================

    function getSwapAmount(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve,
        uint256 swapFeeBps
    ) public pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "Invalid reserves");
        require(swapFeeBps <= 10000, "Invalid fee");

        uint256 inputAmountWithFee = (inputAmount * (10000 - swapFeeBps)) / 10000;
        return (inputAmountWithFee * outputReserve) /
            (inputReserve + inputAmountWithFee);
    }

    function getPoolId(address tokenA, address tokenB)
        public
        pure
        returns (bytes32)
    {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        return keccak256(abi.encodePacked(token0, token1));
    }

    function getPoolsByOwner(address owner_)
        external
        view
        returns (bytes32[] memory)
    {
        return userPools[owner_];
    }

    function getAllPools()
        external
        view
        returns (LiquidityPool[] memory, bytes32[] memory)
    {
        uint256 poolCount = poolIds.length;
        LiquidityPool[] memory allPools = new LiquidityPool[](poolCount);

        for (uint256 i = 0; i < poolCount; i++) {
            allPools[i] = pools[poolIds[i]];
        }

        return (allPools, poolIds);
    }

    receive() external payable {
        require(msg.sender == address(weth), "Direct ETH deposits not allowed");
    }
}
