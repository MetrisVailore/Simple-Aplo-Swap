// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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

contract Swapper is Ownable {
    struct LiquidityPool {
        uint256 token0Reserve;
        uint256 token1Reserve;
        address token0;
        address token1;
        address owner;
        uint256 swapFee;
    }

    IWETH9 public weth;
    mapping(bytes32 => LiquidityPool) public pools;
    mapping(address => bytes32[]) public userPools;

    bytes32[] public poolIds;

    uint256 public minimumLiquidity;
    uint256 public maxSwapFee;
    uint256 public maxDevFee;

    address public devAddress;
    uint256 public devFee;

    constructor(
        address wethAddress,
        uint256 initialMinimumLiquidity,
        uint256 initialMaxSwapFee,
        uint256 initialMaxDevFee,
        address initialDevAddress
    ) {
        weth = IWETH9(wethAddress);
        minimumLiquidity = initialMinimumLiquidity;
        maxSwapFee = initialMaxSwapFee;
        maxDevFee = initialMaxDevFee;
        devAddress = initialDevAddress;
    }

    // ========================= Admin Functions =========================
    function setMinimumLiquidity(uint256 newMinimumLiquidity)
        external
        onlyOwner
    {
        require(
            newMinimumLiquidity > 0,
            "Minimum liquidity must be greater than 0"
        );
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

    function setPoolSwapFee(bytes32 poolId, uint256 newSwapFee) external {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");
        require(msg.sender == pool.owner, "Only pool owner can set swap fee");
        require(newSwapFee <= maxSwapFee, "Swap fee exceeds max limit");

        pool.swapFee = newSwapFee;
    }

    function setDevFee(uint256 newDevFee) external onlyOwner {
        require(newDevFee <= maxDevFee, "Dev fee exceeds max limit");
        devFee = newDevFee;
    }

    // ========================= Pool Management =========================
    function createPool(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 swapFee
    ) external payable {
        require(token0 != token1, "Identical tokens not allowed");
        require(amount0 >= minimumLiquidity, "Token0 liquidity below minimum");
        require(amount1 >= minimumLiquidity, "Token1 liquidity below minimum");
        require(swapFee <= maxSwapFee, "Swap fee exceeds max limit");

        bytes32 poolId = getPoolId(token0, token1);
        require(pools[poolId].token0 == address(0), "Pool already exists");

        if (token0 == address(weth)){
            require(msg.value > 0, "Waplo amount0 reserve must be > 0");
        }

        if (token1 == address(weth)){
            require(msg.value > 0, "Waplo amount1 reserve must be > 0");
        }

        // Handle WETH deposits
        if (token0 == address(weth) && msg.value > 0) {
            weth.deposit{value: msg.value}();
            amount0 = msg.value;
        } else {
            require(
                IERC20(token0).transferFrom(msg.sender, address(this), amount0),
                "Token0 transfer failed"
            );
        }

        if (token1 == address(weth) && msg.value > 0) {
            weth.deposit{value: msg.value}();
            amount1 = msg.value;
        } else {
            require(
                IERC20(token1).transferFrom(msg.sender, address(this), amount1),
                "Token1 transfer failed"
            );
        }

        pools[poolId] = LiquidityPool({
            token0Reserve: amount0,
            token1Reserve: amount1,
            token0: token0,
            token1: token1,
            owner: msg.sender,
            swapFee: swapFee
        });

        userPools[msg.sender].push(poolId);
        poolIds.push(poolId);
    }

    // ========================= Liquidity Functions =========================
    function addLiquidity(
        bytes32 poolId,
        uint256 amount0,
        uint256 amount1
    ) external payable {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");

        if (pool.token0 == address(weth)){
            require(msg.value > 0, "Waplo amount0 reserve must be > 0");
        }

        if (pool.token1 == address(weth)){
            require(msg.value > 0, "Waplo amount1 reserve must be > 0");
        }

        if (pool.token0 == address(weth) && msg.value > 0) {
            weth.deposit{value: msg.value}();
            amount0 = msg.value;
        }

        if (pool.token1 == address(weth) && msg.value > 0) {
            weth.deposit{value: msg.value}();
            amount1 = msg.value;
        }

        if (pool.token0Reserve == 0 || pool.token1Reserve == 0) {
            // Если резервы пула пусты, разрешаем добавление ликвидности без пропорции
            pool.token0Reserve += amount0;
            pool.token1Reserve += amount1;
        } else {
        // Вычисляем пропорцию для добавления ликвидности
            uint256 expectedAmount1 = (amount0 * pool.token1Reserve) / pool.token0Reserve;
            require(amount1 == expectedAmount1, "Liquidity must be added proportionally");
        
            pool.token0Reserve += amount0;
            pool.token1Reserve += amount1;
        }

        if (pool.token0 != address(weth)) {
            require(
                IERC20(pool.token0).transferFrom(
                    msg.sender,
                    address(this),
                    amount0
                ),
                "Token0 transfer failed"
            );
        }
        if (pool.token1 != address(weth)) {
            require(
                IERC20(pool.token1).transferFrom(
                    msg.sender,
                    address(this),
                    amount1
                ),
                "Token1 transfer failed"
            );
        }
    }

    function removeLiquidity(
        bytes32 poolId,
        uint256 amount0,
        uint256 amount1
    ) external {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");
        require(
            msg.sender == pool.owner,
            "Only pool owner can remove liquidity"
        );

        require(pool.token0Reserve >= amount0, "Not enough Token0 reserve");
        require(pool.token1Reserve >= amount1, "Not enough Token1 reserve");

        pool.token0Reserve -= amount0;
        pool.token1Reserve -= amount1;

        if (pool.token0 == address(weth)) {
            weth.withdraw(amount0);
            payable(msg.sender).transfer(amount0);
        } else {
            require(
                IERC20(pool.token0).transfer(msg.sender, amount0),
                "Token0 transfer failed"
            );
        }

        if (pool.token1 == address(weth)) {
            weth.withdraw(amount1);
            payable(msg.sender).transfer(amount1);
        } else {
            require(
                IERC20(pool.token1).transfer(msg.sender, amount1),
                "Token1 transfer failed"
            );
        }
    }

    // ========================= Swap Function =========================
    function swap(
        bytes32 poolId,
        address tokenIn,
        uint256 amountIn
    ) external payable {
        LiquidityPool storage pool = pools[poolId];
        require(pool.token0 != address(0), "Pool does not exist");

        (
            uint256 inputReserve,
            uint256 outputReserve,
            address tokenOut
        ) = tokenIn == pool.token0
                ? (pool.token0Reserve, pool.token1Reserve, pool.token1)
                : (pool.token1Reserve, pool.token0Reserve, pool.token0);

        uint256 totalFee = pool.swapFee + devFee;
        require(totalFee <= 10000, "Total fee exceeds 100%");

        uint256 amountOut = getSwapAmount(
            amountIn,
            inputReserve,
            outputReserve,
            totalFee
        );
        require(amountOut > 0, "Insufficient output amount");

        uint256 devAmount = (amountIn * devFee) / 10000;
        uint256 amountInAfterFees = amountIn - devAmount;

        if (tokenIn == address(weth) && msg.value > 0) {
            weth.deposit{value: msg.value}();
            amountIn = msg.value;
        } else {
            require(
                IERC20(tokenIn).transferFrom(
                    msg.sender,
                    address(this),
                    amountIn
                ),
                "Input token transfer failed"
            );
        }

        // Transfer dev fee
        if (devAmount > 0) {
            require(
                IERC20(tokenIn).transfer(devAddress, devAmount),
                "Dev fee transfer failed"
            );
        }

        if (tokenIn == pool.token0) {
            pool.token0Reserve += amountInAfterFees;
            pool.token1Reserve -= amountOut;
        } else {
            pool.token1Reserve += amountInAfterFees;
            pool.token0Reserve -= amountOut;
        }

        if (tokenOut == address(weth)) {
            weth.withdraw(amountOut);
            payable(msg.sender).transfer(amountOut);
        } else {
            require(
                IERC20(tokenOut).transfer(msg.sender, amountOut),
                "Output token transfer failed"
            );
        }
    }

    // ========================= Helper Functions =========================
    function getSwapAmount(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve,
        uint256 swapFee
    ) public pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "Invalid reserves");
        uint256 inputAmountWithFee = (inputAmount * (10000 - swapFee)) / 10000;
        uint256 amountOut = (inputAmountWithFee * outputReserve) /
            (inputReserve + inputAmountWithFee);
        return amountOut;
    }

    function getPoolId(address token0, address token1)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(token0, token1));
    }

    function getPoolsByOwner(address owner)
        external
        view
        returns (bytes32[] memory)
    {
        return userPools[owner];
    }

    function getAllPools() external view returns (LiquidityPool[] memory, bytes32[] memory) {
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
