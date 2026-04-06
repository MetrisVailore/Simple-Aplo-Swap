// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AMM Router
/// @notice Router for AMM operations with deadline protection and safety checks
/// @dev Handles swaps, liquidity provision, and supports native ETH via WETH
contract AMMRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable factory;
    address public immutable weth;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

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
    error InsufficientLiquidity();
    error InvalidReserves();
    error PairMissing();
    error SwapFeeMismatch();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize router
    /// @param factory_ Factory contract address
    /// @param weth_ WETH9 contract address
    constructor(address factory_, address weth_) {
        if (factory_ == address(0) || weth_ == address(0)) revert ZeroAddress();
        
        factory = factory_;
        weth = weth_;
    }

    /// @notice Receive ETH only from WETH contract
    receive() external payable {
        if (msg.sender != weth) revert InvalidEthAmount();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate quote for adding liquidity
    /// @param amountA Amount of token A
    /// @param reserveA Reserve of token A
    /// @param reserveB Reserve of token B
    /// @return amountB Required amount of token B
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure returns (uint256 amountB) {
        if (amountA == 0) revert ZeroAmount();
        if (reserveA == 0 || reserveB == 0) revert InvalidReserves();
        
        amountB = (amountA * reserveB) / reserveA;
    }

    /// @notice Calculate output amount for a swap
    /// @param amountIn Input amount
    /// @param reserveIn Reserve of input token
    /// @param reserveOut Reserve of output token
    /// @param swapFeeBps Swap fee in basis points
    /// @return amountOut Output amount after fees
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

    /// @notice Calculate input amount required for desired output
    /// @param amountOut Desired output amount
    /// @param reserveIn Reserve of input token
    /// @param reserveOut Reserve of output token
    /// @param swapFeeBps Swap fee in basis points
    /// @return amountIn Required input amount
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

    /// @notice Calculate output amounts for a swap path
    /// @param amountIn Input amount
    /// @param path Array of token addresses
    /// @return amounts Array of amounts for each step
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
            
            unchecked { ++i; }
        }
    }

    /// @notice Calculate input amounts for a swap path
    /// @param amountOut Desired output amount
    /// @param path Array of token addresses
    /// @return amounts Array of amounts for each step
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
            
            unchecked { --i; }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Add liquidity to a pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param amountADesired Desired amount of token A
    /// @param amountBDesired Desired amount of token B
    /// @param amountAMin Minimum amount of token A (slippage protection)
    /// @param amountBMin Minimum amount of token B (slippage protection)
    /// @param to Recipient of LP tokens
    /// @param deadline Transaction must execute before this timestamp
    /// @param swapFeeBps Swap fee for new pairs (ignored for existing pairs)
    /// @return amountA Actual amount of token A added
    /// @return amountB Actual amount of token B added
    /// @return liquidity Amount of LP tokens received
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
        
        // Calculate optimal amounts
        (amountA, amountB) = _calculateLiquidityAmounts(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );

        // Handle ETH/WETH conversion
        uint256 ethRequired = tokenA == weth ? amountA : tokenB == weth ? amountB : 0;
        if (msg.value != ethRequired) revert InvalidEthAmount();

        // Transfer tokens to pair
        _transferTokensToPair(tokenA, tokenB, amountA, amountB, pair);

        // Mint LP tokens
        (liquidity, , ) = IAMMPair(pair).mint(to);

        emit LiquidityAdded(tokenA, tokenB, amountA, amountB, liquidity, to);
    }

    /// @notice Remove liquidity from a pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountAMin Minimum amount of token A (slippage protection)
    /// @param amountBMin Minimum amount of token B (slippage protection)
    /// @param to Recipient of underlying tokens
    /// @param deadline Transaction must execute before this timestamp
    /// @return amountA Amount of token A received
    /// @return amountB Amount of token B received
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

        // Transfer LP tokens to pair
        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);

        // Burn LP tokens and receive underlying tokens
        (uint256 amount0, uint256 amount1) = IAMMPair(pair).burn(address(this));

        // Sort amounts
        (address token0, ) = _sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);

        // Check slippage
        if (amountA < amountAMin || amountB < amountBMin) revert SlippageExceeded();

        // Transfer tokens to recipient (handle ETH)
        _transferTokensToRecipient(tokenA, tokenB, amountA, amountB, to);

        emit LiquidityRemoved(tokenA, tokenB, amountA, amountB, liquidity, to);
    }

    /// @notice Remove liquidity using permit for gasless approval
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountAMin Minimum amount of token A
    /// @param amountBMin Minimum amount of token B
    /// @param to Recipient address
    /// @param deadline Permit and transaction deadline
    /// @param v Permit signature v
    /// @param r Permit signature r
    /// @param s Permit signature s
    /// @return amountA Amount of token A received
    /// @return amountB Amount of token B received
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
        
        // Use permit to approve router
        IAMMPair(pair).permit(msg.sender, address(this), liquidity, deadline, v, r, s);
        
        // Remove liquidity
        return removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    /*//////////////////////////////////////////////////////////////
                            SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Swap exact input tokens for output tokens
    /// @param amountIn Exact input amount
    /// @param amountOutMin Minimum output amount (slippage protection)
    /// @param path Array of token addresses (route)
    /// @param to Recipient address
    /// @param deadline Transaction must execute before this timestamp
    /// @return amounts Amounts for each step in the path
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

        // Transfer input tokens to first pair
        IERC20(path[0]).safeTransferFrom(
            msg.sender,
            _pairFor(path[0], path[1]),
            amounts[0]
        );

        // Execute swaps
        _swap(amounts, path, to);

        emit TokensSwapped(msg.sender, path, amounts, to);
    }

    /// @notice Swap exact ETH for tokens
    /// @param amountOutMin Minimum output amount
    /// @param path Array of token addresses (must start with WETH)
    /// @param to Recipient address
    /// @param deadline Transaction deadline
    /// @return amounts Amounts for each step
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

        // Wrap ETH and send to first pair
        IWETH9(weth).deposit{value: amounts[0]}();
        IERC20(weth).safeTransfer(_pairFor(path[0], path[1]), amounts[0]);

        // Execute swaps
        _swap(amounts, path, to);

        emit TokensSwapped(msg.sender, path, amounts, to);
    }

    /// @notice Swap exact tokens for ETH
    /// @param amountIn Exact input amount
    /// @param amountOutMin Minimum ETH output
    /// @param path Array of token addresses (must end with WETH)
    /// @param to Recipient address
    /// @param deadline Transaction deadline
    /// @return amounts Amounts for each step
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

        // Transfer input tokens to first pair
        IERC20(path[0]).safeTransferFrom(
            msg.sender,
            _pairFor(path[0], path[1]),
            amounts[0]
        );

        // Execute swaps to this contract
        _swap(amounts, path, address(this));

        // Unwrap WETH and send ETH to recipient
        IWETH9(weth).withdraw(amounts[amounts.length - 1]);
        (bool success, ) = payable(to).call{value: amounts[amounts.length - 1]}("");
        if (!success) revert EthTransferFailed();

        emit TokensSwapped(msg.sender, path, amounts, to);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Sort token addresses
    function _sortTokens(address a, address b)
        internal
        pure
        returns (address token0, address token1)
    {
        if (a == b) revert IdenticalTokens();
        (token0, token1) = a < b ? (a, b) : (b, a);
        if (token0 == address(0)) revert ZeroAddress();
    }

    /// @dev Get pair address from factory
    function _pairFor(address tokenA, address tokenB) internal view returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = IAMMFactory(factory).getPair(token0, token1);
        if (pair == address(0)) revert PairMissing();
    }

    /// @dev Get reserves for a token pair
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

    /// @dev Ensure pair exists, create if needed
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
            // Validate fee matches if pair exists
            uint24 existingFee = IAMMPair(pair).swapFeeBps();
            if (existingFee != swapFeeBps) revert SwapFeeMismatch();
        }
    }

    /// @dev Calculate optimal liquidity amounts
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
            // First liquidity provision
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

    /// @dev Transfer tokens to pair (handles ETH/WETH)
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

    /// @dev Transfer tokens to recipient (handles ETH/WETH)
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

    /// @dev Execute swap through path
    function _swap(
        uint256[] memory amounts,
        address[] calldata path,
        address to
    ) internal {
        for (uint256 i; i < path.length - 1; ) {
            address input = path[i];
            address output = path[i + 1];
            address pair = _pairFor(input, output);
            
            // Determine recipient (next pair or final recipient)
            address recipient = i < path.length - 2
                ? _pairFor(output, path[i + 2])
                : to;

            // Calculate output amounts
            (address token0, ) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));

            // Execute swap
            IAMMPair(pair).swap(amount0Out, amount1Out, recipient);
            
            unchecked { ++i; }
        }
    }
}

/*//////////////////////////////////////////////////////////////
                            INTERFACES
//////////////////////////////////////////////////////////////*/

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256) external;
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
    function mint(address to) external returns (uint256 liquidity, uint256 amount0, uint256 amount1);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external;
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
