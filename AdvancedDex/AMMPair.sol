// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AMM Pair Contract
/// @notice Implements a constant product AMM pair with protocol fees and price oracles
/// @dev Based on Uniswap V2 with improvements and bug fixes
contract AMMPair is ERC20, ERC20Permit, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant BPS = 10_000;
    uint256 private constant MINIMUM_LIQUIDITY = 1_000;
    uint256 private constant INITIAL_MINIMUM_AMOUNT0 = 1_000; // Prevent price manipulation
    uint256 private constant INITIAL_MINIMUM_AMOUNT1 = 1_000;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable swapFeeBps;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyFactory();
    error AlreadyInitialized();
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

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyFactory() {
        if (msg.sender != factory) revert OnlyFactory();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new AMM pair
    /// @dev Called by factory, tokens and fee are set via initialize
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

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get current reserves and last update timestamp
    /// @return _reserve0 Reserve of token0
    /// @return _reserve1 Reserve of token1
    /// @return _blockTimestampLast Last update timestamp
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

    /// @notice Calculate current cumulative prices
    /// @return price0Cumulative Cumulative price of token0
    /// @return price1Cumulative Cumulative price of token1
    /// @return blockTimestamp Current block timestamp
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
                // Fix: proper operator precedence for price accumulation
                price0Cumulative += uint256(_reserve1) * (1 << 112) / _reserve0 * timeElapsed;
                price1Cumulative += uint256(_reserve0) * (1 << 112) / _reserve1 * timeElapsed;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint LP tokens
    /// @param to Recipient of LP tokens
    /// @return liquidity Amount of LP tokens minted
    /// @return amount0 Amount of token0 deposited
    /// @return amount1 Amount of token1 deposited
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
        
        // Mint protocol fee if applicable
        bool feeOn = _mintFee(_reserve0, _reserve1);

        // Get actual balances (handles fee-on-transfer tokens)
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        amount0 = balance0 - _reserve0;
        amount1 = balance1 - _reserve1;

        uint256 _totalSupply = totalSupply();
        
        if (_totalSupply == 0) {
            // First liquidity provision - prevent price manipulation
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

    /// @notice Burn LP tokens to withdraw liquidity
    /// @param to Recipient of underlying tokens
    /// @return amount0 Amount of token0 withdrawn
    /// @return amount1 Amount of token1 withdrawn
    function burn(address to)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        (uint112 _reserve0, uint112 _reserve1) = (reserve0, reserve1);
        address _token0 = token0;
        address _token1 = token1;
        
        // Mint protocol fee if applicable
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

    /*//////////////////////////////////////////////////////////////
                            SWAP FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Swap tokens
    /// @param amount0Out Amount of token0 to receive
    /// @param amount1Out Amount of token1 to receive
    /// @param to Recipient address
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) external nonReentrant {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutput();
        
        (uint112 _reserve0, uint112 _reserve1) = (reserve0, reserve1);
        
        if (amount0Out >= _reserve0 || amount1Out >= _reserve1) {
            revert InsufficientLiquidity();
        }
        if (to == token0 || to == token1) revert InvalidRecipient();

        // Optimistically transfer tokens
        if (amount0Out > 0) IERC20(token0).safeTransfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).safeTransfer(to, amount1Out);

        // Get actual balances after transfer (handles fee-on-transfer)
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // Calculate actual amounts received
        uint256 amount0In = balance0 > _reserve0 - amount0Out
            ? balance0 - (_reserve0 - amount0Out)
            : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out
            ? balance1 - (_reserve1 - amount1Out)
            : 0;

        if (amount0In == 0 && amount1In == 0) revert InsufficientInput();

        // Verify constant product formula with fees
        uint256 balance0Adjusted = (balance0 * BPS) - (amount0In * swapFeeBps);
        uint256 balance1Adjusted = (balance1 * BPS) - (amount1In * swapFeeBps);
        
        if (balance0Adjusted * balance1Adjusted < uint256(_reserve0) * _reserve1 * (BPS * BPS)) {
            revert KInvariantViolated();
        }

        _update(balance0, balance1, _reserve0, _reserve1);

        // Update kLast if protocol fee is on
        address feeTo = IFactory(factory).feeTo();
        if (feeTo != address(0)) {
            kLast = uint256(reserve0) * reserve1;
        } else if (kLast != 0) {
            kLast = 0;
        }

        emit Swap(msg.sender, to, amount0In, amount1In, amount0Out, amount1Out);
    }

    /*//////////////////////////////////////////////////////////////
                        SYNC & SKIM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Force balances to match reserves
    /// @param to Recipient of excess tokens
    function skim(address to) external nonReentrant {
        address _token0 = token0;
        address _token1 = token1;
        
        IERC20(_token0).safeTransfer(to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        IERC20(_token1).safeTransfer(to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    /// @notice Force reserves to match balances
    function sync() external nonReentrant {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Mint protocol fee if enabled
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

    /// @dev Update reserves and price accumulators
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
                // Fix: proper operator precedence for price accumulation
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
