// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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

contract Swapper is Ownable {
    struct LiquidityPool {
        uint256 token0Reserve;
        uint256 token1Reserve;
        address token0;
        address token1;
        address owner;
        uint256 swapFee;
    }

    mapping(bytes32 => LiquidityPool) public pools;
    mapping(address => bool) public allowedTokens;

    uint256 public minimumLiquidity;
    uint256 public maxSwapFee;

    constructor(uint256 initialMinimumLiquidity, uint256 initialMaxSwapFee) {
        minimumLiquidity = initialMinimumLiquidity;
        maxSwapFee = initialMaxSwapFee;
    }

    function setMinimumLiquidity(uint256 newMinimumLiquidity) external onlyOwner {
        require(newMinimumLiquidity > 0, "Minimum liquidity must be greater than 0");
        minimumLiquidity = newMinimumLiquidity;
    }

    function setMaxSwapFee(uint256 newMaxSwapFee) external onlyOwner {
        require(newMaxSwapFee <= 10000, "Max swap fee must be <= 100%");
        maxSwapFee = newMaxSwapFee;
    }

    function addToken(address tokenAddress) external {
        require(tokenAddress != address(0), "Invalid token address");
        allowedTokens[tokenAddress] = true;
    }

    function createPool(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 swapFee
    ) external {
        require(allowedTokens[token0], "Token0 not allowed");
        require(allowedTokens[token1], "Token1 not allowed");
        require(token0 != token1, "Identical tokens");
        require(amount0 >= minimumLiquidity, "Token0 liquidity below minimum");
        require(amount1 >= minimumLiquidity, "Token1 liquidity below minimum");
        require(swapFee <= maxSwapFee, "Swap fee exceeds max limit");

        bytes32 poolId = getPoolId(token0, token1);
        require(pools[poolId].token0 == address(0), "Pool already exists");

        require(
            IERC20(token0).transferFrom(msg.sender, address(this), amount0),
            "Token0 transfer failed"
        );
        require(
            IERC20(token1).transferFrom(msg.sender, address(this), amount1),
            "Token1 transfer failed"
        );

        pools[poolId] = LiquidityPool({
            token0Reserve: amount0,
            token1Reserve: amount1,
            token0: token0,
            token1: token1,
            owner: msg.sender,
            swapFee: swapFee
        });
    }

    function setPoolSwapFee(
        bytes32 poolId,
        uint256 newSwapFee
    ) external {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");
        require(msg.sender == pool.owner, "Only pool owner can set swap fee");
        require(newSwapFee <= maxSwapFee, "Swap fee exceeds max limit");

        pool.swapFee = newSwapFee;
    }

    function addLiquidity(
        bytes32 poolId,
        uint256 amount0,
        uint256 amount1
    ) external {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");

        uint256 expectedAmount1 = (amount0 * pool.token1Reserve) / pool.token0Reserve;
        require(amount1 == expectedAmount1, "Liquidity must be added proportionally");

        require(
            IERC20(pool.token0).transferFrom(msg.sender, address(this), amount0),
            "Token0 transfer failed"
        );
        require(
            IERC20(pool.token1).transferFrom(msg.sender, address(this), amount1),
            "Token1 transfer failed"
        );

        pool.token0Reserve += amount0;
        pool.token1Reserve += amount1;
    }

    function removeLiquidity(
        bytes32 poolId,
        uint256 amount0,
        uint256 amount1
    ) external {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");
        require(msg.sender == pool.owner, "Only pool owner can remove liquidity");

        require(pool.token0Reserve >= amount0, "Not enough Token0 reserve");
        require(pool.token1Reserve >= amount1, "Not enough Token1 reserve");

        pool.token0Reserve -= amount0;
        pool.token1Reserve -= amount1;

        require(IERC20(pool.token0).transfer(msg.sender, amount0), "Token0 transfer failed");
        require(IERC20(pool.token1).transfer(msg.sender, amount1), "Token1 transfer failed");
    }

    function swap(
        bytes32 poolId,
        address tokenIn,
        uint256 amountIn
    ) external {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");

        (uint256 inputReserve, uint256 outputReserve, address tokenOut) = tokenIn == pool.token0
            ? (pool.token0Reserve, pool.token1Reserve, pool.token1)
            : (pool.token1Reserve, pool.token0Reserve, pool.token0);

        uint256 amountOut = getSwapAmount(amountIn, inputReserve, outputReserve, pool.swapFee);
        require(amountOut > 0, "Insufficient output amount");

        require(
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn),
            "Input token transfer failed"
        );

        if (tokenIn == pool.token0) {
            pool.token0Reserve += amountIn;
            pool.token1Reserve -= amountOut;
        } else {
            pool.token1Reserve += amountIn;
            pool.token0Reserve -= amountOut;
        }

        require(IERC20(tokenOut).transfer(msg.sender, amountOut), "Output token transfer failed");
    }

    function getSwapAmount(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve,
        uint256 swapFee
    ) public pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "Invalid reserves");
        uint256 inputAmountWithFee = inputAmount * (10000 - swapFee) / 10000;
        // Use the standard AMM formula
        uint256 amountOut = (inputAmountWithFee * outputReserve) / (inputReserve + inputAmountWithFee);
        return amountOut;
    }

    function getPoolId(address token0, address token1) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(token0, token1));
    }
}
