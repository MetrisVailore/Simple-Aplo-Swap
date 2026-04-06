// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

/**
 * @title AMM Deployment Script
 * @notice Deploy script for the complete AMM system
 * @dev Use with Hardhat or Foundry
 */

import "../AMMFactory.sol";
import "../AMMRouter.sol";
import "../AMMPair.sol";

contract DeployAMM {
    struct DeploymentAddresses {
        address factory;
        address router;
        address weth;
        address feeToSetter;
    }

    event Deployed(
        address indexed factory,
        address indexed router,
        address indexed weth
    );

    /**
     * @notice Deploy the complete AMM system
     * @param wethAddress WETH9 contract address
     * @param feeToSetter Initial fee admin address
     * @return addresses Struct containing all deployed addresses
     */
    function deploy(address wethAddress, address feeToSetter)
        external
        returns (DeploymentAddresses memory addresses)
    {
        require(wethAddress != address(0), "WETH address required");
        require(feeToSetter != address(0), "Fee setter required");

        // Deploy Factory
        AMMFactory factory = new AMMFactory(wethAddress, feeToSetter);

        // Deploy Router
        AMMRouter router = new AMMRouter(address(factory), wethAddress);

        // Package addresses
        addresses = DeploymentAddresses({
            factory: address(factory),
            router: address(router),
            weth: wethAddress,
            feeToSetter: feeToSetter
        });

        emit Deployed(address(factory), address(router), wethAddress);

        return addresses;
    }

    /**
     * @notice Create initial trading pairs with liquidity
     * @param factory Factory contract address
     * @param router Router contract address
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param amountA Amount of token A
     * @param amountB Amount of token B
     * @param swapFeeBps Swap fee in basis points
     */
    function createPairWithLiquidity(
        address factory,
        address router,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint24 swapFeeBps
    ) external returns (address pair) {
        // Approve router
        IERC20(tokenA).approve(router, amountA);
        IERC20(tokenB).approve(router, amountB);

        // Add liquidity (this will create pair if needed)
        AMMRouter(router).addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            amountA * 95 / 100, // 5% slippage
            amountB * 95 / 100,
            msg.sender,
            block.timestamp + 300,
            swapFeeBps
        );

        // Return pair address
        return AMMFactory(factory).getPair(tokenA, tokenB);
    }
}

/**
 * @title Deployment Configuration
 * @notice Configuration constants for different networks
 */
library DeploymentConfig {
    // Mainnet
    address constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Goerli
    address constant GOERLI_WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

    // Sepolia
    address constant SEPOLIA_WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;

    // Arbitrum
    address constant ARBITRUM_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // Optimism
    address constant OPTIMISM_WETH = 0x4200000000000000000000000000000000000006;

    // Polygon
    address constant POLYGON_WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;

    // Base
    address constant BASE_WETH = 0x4200000000000000000000000000000000000006;

    // Default fees
    uint24 constant DEFAULT_SWAP_FEE = 30; // 0.30%
    uint24 constant STABLE_SWAP_FEE = 4;   // 0.04%
    uint24 constant EXOTIC_SWAP_FEE = 100; // 1.00%

    function getWETH(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return MAINNET_WETH;
        if (chainId == 5) return GOERLI_WETH;
        if (chainId == 11155111) return SEPOLIA_WETH;
        if (chainId == 42161) return ARBITRUM_WETH;
        if (chainId == 10) return OPTIMISM_WETH;
        if (chainId == 137) return POLYGON_WETH;
        if (chainId == 8453) return BASE_WETH;
        revert("Unsupported chain");
    }
}

/**
 * @title Post-Deployment Verification
 * @notice Verify deployment was successful
 */
library DeploymentVerification {
    function verifyDeployment(address factory, address router, address weth)
        internal
        view
        returns (bool)
    {
        // Check factory
        if (AMMFactory(factory).weth() != weth) return false;
        if (AMMFactory(factory).feeToSetter() == address(0)) return false;

        // Check router
        if (AMMRouter(router).factory() != factory) return false;
        if (AMMRouter(router).weth() != weth) return false;

        return true;
    }

    function getDeploymentInfo(address factory, address router)
        internal
        view
        returns (
            address weth,
            address feeToSetter,
            address feeTo,
            uint256 pairCount
        )
    {
        AMMFactory f = AMMFactory(factory);
        weth = f.weth();
        feeToSetter = f.feeToSetter();
        feeTo = f.feeTo();
        pairCount = f.allPairsLength();
    }
}
