// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "forge-std/Test.sol";
import "../AMMFactory.sol";
import "../AMMRouter.sol";
import "../AMMPair.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mock ERC20 Token
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title Mock Fee-on-Transfer Token
contract MockFeeToken is ERC20 {
    uint256 public feePercentage = 1; // 1% fee
    
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercentage) / 100;
        uint256 amountAfterFee = amount - fee;
        
        super.transfer(to, amountAfterFee);
        super.transfer(address(0xdead), fee); // Burn fee
        
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercentage) / 100;
        uint256 amountAfterFee = amount - fee;
        
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amountAfterFee);
        _transfer(from, address(0xdead), fee);
        
        return true;
    }
}

/// @title Mock WETH
contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}
    
    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
    
    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
    
    receive() external payable {
        deposit();
    }
}

/// @title AMM Test Suite
/// @notice Comprehensive tests for all AMM functionality
contract AMMTest is Test {
    AMMFactory factory;
    AMMRouter router;
    MockWETH weth;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockFeeToken feeToken;
    
    address alice = address(0x1);
    address bob = address(0x2);
    address carol = address(0x3);
    
    uint24 constant DEFAULT_FEE = 30; // 0.3%
    
    event LiquidityAdded(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity,
        address indexed to
    );
    
    function setUp() public {
        // Deploy contracts
        weth = new MockWETH();
        factory = new AMMFactory(address(weth), address(this));
        router = new AMMRouter(address(factory), address(weth));
        
        // Deploy test tokens
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        feeToken = new MockFeeToken("Fee Token", "FEE");
        
        // Setup test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        
        tokenA.transfer(alice, 100000 * 10**18);
        tokenA.transfer(bob, 100000 * 10**18);
        tokenB.transfer(alice, 100000 * 10**18);
        tokenB.transfer(bob, 100000 * 10**18);
        feeToken.transfer(alice, 100000 * 10**18);
    }
    
    /*//////////////////////////////////////////////////////////////
                        FACTORY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testCreatePair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB), DEFAULT_FEE);
        
        assertTrue(pair != address(0), "Pair should be created");
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
        assertEq(factory.allPairsLength(), 1);
    }
    
    function testCannotCreateDuplicatePair() public {
        factory.createPair(address(tokenA), address(tokenB), DEFAULT_FEE);
        
        vm.expectRevert(AMMFactory.PairExists.selector);
        factory.createPair(address(tokenA), address(tokenB), DEFAULT_FEE);
    }
    
    function testCannotCreatePairWithIdenticalTokens() public {
        vm.expectRevert(AMMFactory.IdenticalTokens.selector);
        factory.createPair(address(tokenA), address(tokenA), DEFAULT_FEE);
    }
    
    function testCannotCreatePairWithInvalidFee() public {
        vm.expectRevert(AMMFactory.InvalidFee.selector);
        factory.createPair(address(tokenA), address(tokenB), 10001);
    }
    
    function testSetFeeTo() public {
        factory.setFeeTo(alice);
        assertEq(factory.feeTo(), alice);
    }
    
    function testOnlyFeeSetterCanSetFeeTo() public {
        vm.prank(alice);
        vm.expectRevert(AMMFactory.Forbidden.selector);
        factory.setFeeTo(bob);
    }
    
    /*//////////////////////////////////////////////////////////////
                        PAIR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testInitialLiquidityWithMinimumEnforcement() public {
        address pair = factory.createPair(address(tokenA), address(tokenB), DEFAULT_FEE);
        
        vm.startPrank(alice);
        
        // Try to add liquidity below minimum
        tokenA.approve(address(router), 500);
        tokenB.approve(address(router), 500);
        
        vm.expectRevert(); // Should revert due to minimum not met
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            500,
            500,
            500,
            500,
            alice,
            block.timestamp + 300,
            DEFAULT_FEE
        );
        
        // Add liquidity above minimum
        tokenA.approve(address(router), 10000 * 10**18);
        tokenB.approve(address(router), 10000 * 10**18);
        
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10000 * 10**18,
            10000 * 10**18,
            9000 * 10**18,
            9000 * 10**18,
            alice,
            block.timestamp + 300,
            DEFAULT_FEE
        );
        
        assertTrue(IERC20(pair).balanceOf(alice) > 0);
        
        vm.stopPrank();
    }
    
    function testSwapExactTokensForTokens() public {
        // Setup liquidity
        _addInitialLiquidity();
        
        vm.startPrank(bob);
        
        uint256 amountIn = 1000 * 10**18;
        tokenA.approve(address(router), amountIn);
        
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        uint256[] memory expectedAmounts = router.getAmountsOut(amountIn, path);
        uint256 balanceBefore = tokenB.balanceOf(bob);
        
        router.swapExactTokensForTokens(
            amountIn,
            expectedAmounts[1] * 95 / 100, // 5% slippage
            path,
            bob,
            block.timestamp + 300
        );
        
        uint256 balanceAfter = tokenB.balanceOf(bob);
        assertTrue(balanceAfter > balanceBefore);
        
        vm.stopPrank();
    }
    
    function testSwapRevertsOnExpiredDeadline() public {
        _addInitialLiquidity();
        
        vm.startPrank(bob);
        
        tokenA.approve(address(router), 1000 * 10**18);
        
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        vm.warp(block.timestamp + 400);
        
        vm.expectRevert(AMMRouter.TransactionExpired.selector);
        router.swapExactTokensForTokens(
            1000 * 10**18,
            0,
            path,
            bob,
            block.timestamp - 100 // Expired deadline
        );
        
        vm.stopPrank();
    }
    
    function testSwapRevertsOnSlippageExceeded() public {
        _addInitialLiquidity();
        
        vm.startPrank(bob);
        
        uint256 amountIn = 1000 * 10**18;
        tokenA.approve(address(router), amountIn);
        
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        uint256[] memory expectedAmounts = router.getAmountsOut(amountIn, path);
        
        vm.expectRevert(AMMRouter.SlippageExceeded.selector);
        router.swapExactTokensForTokens(
            amountIn,
            expectedAmounts[1] * 2, // Impossible slippage
            path,
            bob,
            block.timestamp + 300
        );
        
        vm.stopPrank();
    }
    
    function testFeeOnTransferTokenSupport() public {
        // Create pair with fee token
        factory.createPair(address(feeToken), address(tokenB), DEFAULT_FEE);
        
        vm.startPrank(alice);
        
        uint256 depositAmount = 10000 * 10**18;
        feeToken.approve(address(router), depositAmount);
        tokenB.approve(address(router), depositAmount);
        
        // The actual amount received will be less due to transfer fee
        router.addLiquidity(
            address(feeToken),
            address(tokenB),
            depositAmount,
            depositAmount,
            0, // Accept any amount
            depositAmount * 95 / 100,
            alice,
            block.timestamp + 300,
            DEFAULT_FEE
        );
        
        // Verify liquidity was added successfully
        address pair = factory.getPair(address(feeToken), address(tokenB));
        assertTrue(IERC20(pair).balanceOf(alice) > 0);
        
        vm.stopPrank();
    }
    
    function testRemoveLiquidity() public {
        _addInitialLiquidity();
        
        vm.startPrank(alice);
        
        address pair = factory.getPair(address(tokenA), address(tokenB));
        uint256 liquidity = IERC20(pair).balanceOf(alice);
        
        uint256 balanceABefore = tokenA.balanceOf(alice);
        uint256 balanceBBefore = tokenB.balanceOf(alice);
        
        IERC20(pair).approve(address(router), liquidity);
        
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            0,
            0,
            alice,
            block.timestamp + 300
        );
        
        uint256 balanceAAfter = tokenA.balanceOf(alice);
        uint256 balanceBAfter = tokenB.balanceOf(alice);
        
        assertTrue(balanceAAfter > balanceABefore);
        assertTrue(balanceBAfter > balanceBBefore);
        
        vm.stopPrank();
    }
    
    function testSwapFeeMismatchReverts() public {
        // Create pair with specific fee
        factory.createPair(address(tokenA), address(tokenB), 30);
        
        vm.startPrank(alice);
        
        tokenA.approve(address(router), 10000 * 10**18);
        tokenB.approve(address(router), 10000 * 10**18);
        
        // Try to add liquidity with different fee
        vm.expectRevert(AMMRouter.SwapFeeMismatch.selector);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10000 * 10**18,
            10000 * 10**18,
            9000 * 10**18,
            9000 * 10**18,
            alice,
            block.timestamp + 300,
            50 // Different fee!
        );
        
        vm.stopPrank();
    }
    
    function testPriceOracleAccuracy() public {
        address pair = factory.createPair(address(tokenA), address(tokenB), DEFAULT_FEE);
        
        _addInitialLiquidity();
        
        // Get initial price
        (uint256 price0Before, uint256 price1Before, ) = 
            AMMPair(pair).currentCumulativePrices();
        
        // Wait some time
        vm.warp(block.timestamp + 3600);
        
        // Get price after time elapsed
        (uint256 price0After, uint256 price1After, ) = 
            AMMPair(pair).currentCumulativePrices();
        
        // Prices should have accumulated
        assertTrue(price0After > price0Before);
        assertTrue(price1After > price1Before);
    }
    
    function testMultiHopSwap() public {
        // Create pairs: A-B and B-WETH
        factory.createPair(address(tokenA), address(tokenB), DEFAULT_FEE);
        factory.createPair(address(tokenB), address(weth), DEFAULT_FEE);
        
        // Add liquidity to both pairs
        vm.startPrank(alice);
        
        // A-B pair
        tokenA.approve(address(router), 20000 * 10**18);
        tokenB.approve(address(router), 20000 * 10**18);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10000 * 10**18,
            10000 * 10**18,
            0, 0,
            alice,
            block.timestamp + 300,
            DEFAULT_FEE
        );
        
        // B-WETH pair
        weth.deposit{value: 10 ether}();
        weth.approve(address(router), 10 ether);
        router.addLiquidity(
            address(tokenB),
            address(weth),
            10000 * 10**18,
            10 ether,
            0, 0,
            alice,
            block.timestamp + 300,
            DEFAULT_FEE
        );
        
        vm.stopPrank();
        
        // Multi-hop swap: A -> B -> WETH
        vm.startPrank(bob);
        
        uint256 amountIn = 100 * 10**18;
        tokenA.approve(address(router), amountIn);
        
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(weth);
        
        uint256 wethBefore = weth.balanceOf(bob);
        
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            bob,
            block.timestamp + 300
        );
        
        uint256 wethAfter = weth.balanceOf(bob);
        assertTrue(wethAfter > wethBefore);
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _addInitialLiquidity() internal {
        vm.startPrank(alice);
        
        tokenA.approve(address(router), 10000 * 10**18);
        tokenB.approve(address(router), 10000 * 10**18);
        
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10000 * 10**18,
            10000 * 10**18,
            0,
            0,
            alice,
            block.timestamp + 300,
            DEFAULT_FEE
        );
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_SwapAmounts(uint256 amountIn) public {
        vm.assume(amountIn > 1000 && amountIn < 1000 * 10**18);
        
        _addInitialLiquidity();
        
        vm.startPrank(bob);
        
        tokenA.approve(address(router), amountIn);
        
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        
        if (amounts[1] > 0) {
            router.swapExactTokensForTokens(
                amountIn,
                0,
                path,
                bob,
                block.timestamp + 300
            );
        }
        
        vm.stopPrank();
    }
    
    function testFuzz_AddRemoveLiquidity(uint256 amountA, uint256 amountB) public {
        vm.assume(amountA >= 1000 && amountA <= 10000 * 10**18);
        vm.assume(amountB >= 1000 && amountB <= 10000 * 10**18);
        
        address pair = factory.createPair(address(tokenA), address(tokenB), DEFAULT_FEE);
        
        vm.startPrank(alice);
        
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);
        
        (,, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0, 0,
            alice,
            block.timestamp + 300,
            DEFAULT_FEE
        );
        
        if (liquidity > 0) {
            IERC20(pair).approve(address(router), liquidity);
            
            router.removeLiquidity(
                address(tokenA),
                address(tokenB),
                liquidity,
                0, 0,
                alice,
                block.timestamp + 300
            );
        }
        
        vm.stopPrank();
    }
}
