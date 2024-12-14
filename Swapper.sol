// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Контракт токена
 */
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

/**
 * @dev Контракт для обмена токенов и управления ликвидностью
 */
contract Swapper {
    struct LiquidityPool {
        uint256 token0Reserve;
        uint256 token1Reserve;
        address token0;
        address token1;
    }

    mapping(bytes32 => LiquidityPool) public pools;
    mapping(address => bool) public allowedTokens;

    /**
     * @dev Добавить новый токен в список разрешенных для обмена
     * @param tokenAddress Адрес нового токена
     */
    function addToken(address tokenAddress) external {
        require(tokenAddress != address(0), "Invalid token address");
        allowedTokens[tokenAddress] = true;
    }

    /**
     * @dev Создание новой пары ликвидности
     * @param token0 Адрес первого токена
     * @param token1 Адрес второго токена
     */
    function createPool(address token0, address token1) external {
        require(allowedTokens[token0], "Token0 not allowed");
        require(allowedTokens[token1], "Token1 not allowed");
        require(token0 != token1, "Identical tokens");

        bytes32 poolId = getPoolId(token0, token1);
        require(pools[poolId].token0 == address(0), "Pool already exists");

        pools[poolId] = LiquidityPool({
            token0Reserve: 0,
            token1Reserve: 0,
            token0: token0,
            token1: token1
        });
    }

    /**
     * @dev Добавление ликвидности в пул
     * @param token0 Адрес первого токена
     * @param token1 Адрес второго токена
     * @param amount0 Количество токена0
     * @param amount1 Количество токена1
     */
    function addLiquidity(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) external {
        bytes32 poolId = getPoolId(token0, token1);
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");

        require(
            IERC20(token0).transferFrom(msg.sender, address(this), amount0),
            "Token0 transfer failed"
        );
        require(
            IERC20(token1).transferFrom(msg.sender, address(this), amount1),
            "Token1 transfer failed"
        );

        pool.token0Reserve += amount0;
        pool.token1Reserve += amount1;
    }

    /**
     * @dev Удаление ликвидности из пула
     * @param token0 Адрес первого токена
     * @param token1 Адрес второго токена
     * @param amount0 Количество токена0 для удаления
     * @param amount1 Количество токена1 для удаления
     */
    function removeLiquidity(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) external {
        bytes32 poolId = getPoolId(token0, token1);
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");

        require(pool.token0Reserve >= amount0, "Not enough Token0 reserve");
        require(pool.token1Reserve >= amount1, "Not enough Token1 reserve");

        pool.token0Reserve -= amount0;
        pool.token1Reserve -= amount1;

        require(IERC20(token0).transfer(msg.sender, amount0), "Token0 transfer failed");
        require(IERC20(token1).transfer(msg.sender, amount1), "Token1 transfer failed");
    }

    /**
     * @dev Обмен токенов
     * @param tokenIn Адрес входного токена
     * @param tokenOut Адрес выходного токена
     * @param amountIn Количество входного токена
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external {
        bytes32 poolId = getPoolId(tokenIn, tokenOut);
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");

        (uint256 inputReserve, uint256 outputReserve) = tokenIn == pool.token0
            ? (pool.token0Reserve, pool.token1Reserve)
            : (pool.token1Reserve, pool.token0Reserve);

        uint256 amountOut = getSwapAmount(amountIn, inputReserve, outputReserve);
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

    /**
     * @dev Расчет количества токенов для обмена
     * @param inputAmount Количество входных токенов
     * @param inputReserve Резерв входных токенов
     * @param outputReserve Резерв выходных токенов
     */
    function getSwapAmount(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    ) public pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "Invalid reserves");
        uint256 inputAmountWithFee = inputAmount * 997; // 0.3% комиссия
        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = (inputReserve * 1000) + inputAmountWithFee;
        return numerator / denominator;
    }

    /**
     * @dev Генерация уникального идентификатора для пула
     * @param token0 Адрес первого токена
     * @param token1 Адрес второго токена
     */
    function getPoolId(address token0, address token1) public pure returns (bytes32) {
        return token0 < token1
            ? keccak256(abi.encodePacked(token0, token1))
            : keccak256(abi.encodePacked(token1, token0));
    }
}

