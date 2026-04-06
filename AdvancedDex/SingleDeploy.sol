// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

// Replace this path with your combined one-file AMM source filename
import "../AMMSystem.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AMM Deployment Script
 * @notice Deploys the full AMM system from the single combined source file
 */
contract DeployAMM {
    using SafeERC20 for IERC20;

    struct DeploymentAddresses {
        address factory;
        address router;
        address flashLoanProvider;
        address weth;
        address feeToSetter;
        address treasury;
    }

    event Deployed(
        address indexed factory,
        address indexed router,
        address indexed flashLoanProvider,
        address weth,
        address feeToSetter,
        address treasury
    );

    event PairInitialized(
        address indexed pair,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB
    );

    event FlashLoanProviderFunded(
        address indexed provider,
        address indexed asset,
        uint256 amount
    );

    function deploy(
        address wethAddress,
        address feeToSetter,
        address treasury,
        uint16 flashLoanFeeBps
    ) external returns (DeploymentAddresses memory d) {
        require(wethAddress != address(0), "WETH required");
        require(feeToSetter != address(0), "feeToSetter required");
        require(treasury != address(0), "treasury required");

        AMMFactory factory = new AMMFactory(wethAddress, feeToSetter);
        AMMRouter router = new AMMRouter(address(factory), wethAddress);
        AMMFlashLoanProvider flashLoanProvider = new AMMFlashLoanProvider(
            treasury,
            flashLoanFeeBps
        );

        d = DeploymentAddresses({
            factory: address(factory),
            router: address(router),
            flashLoanProvider: address(flashLoanProvider),
            weth: wethAddress,
            feeToSetter: feeToSetter,
            treasury: treasury
        });

        emit Deployed(
            d.factory,
            d.router,
            d.flashLoanProvider,
            d.weth,
            d.feeToSetter,
            d.treasury
        );
    }

    function createPairWithLiquidity(
        address factory,
        address router,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint24 swapFeeBps
    ) external payable returns (address pair) {
        require(amountA > 0 && amountB > 0, "Zero liquidity");

        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);

        _approve(tokenA, router, amountA);
        _approve(tokenB, router, amountB);

        AMMRouter(router).addLiquidity{value: msg.value}(
            tokenA,
            tokenB,
            amountA,
            amountB,
            (amountA * 95) / 100,
            (amountB * 95) / 100,
            msg.sender,
            block.timestamp + 300,
            swapFeeBps
        );

        pair = AMMFactory(factory).getPair(tokenA, tokenB);

        emit PairInitialized(pair, tokenA, tokenB, amountA, amountB);
    }

    function fundFlashLoanProvider(
        address flashLoanProvider,
        address asset,
        uint256 amount
    ) external {
        require(flashLoanProvider != address(0), "provider required");
        require(asset != address(0), "asset required");
        require(amount > 0, "amount required");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        _approve(asset, flashLoanProvider, amount);
        IERC20(asset).safeTransfer(flashLoanProvider, amount);

        emit FlashLoanProviderFunded(flashLoanProvider, asset, amount);
    }

    function _approve(address token, address spender, uint256 amount) internal {
        IERC20(token).approve(spender, 0);
        IERC20(token).approve(spender, amount);
    }
}

/**
 * @title Deployment Configuration
 */
library DeploymentConfig {
    address constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant GOERLI_WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    address constant SEPOLIA_WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant ARBITRUM_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant OPTIMISM_WETH = 0x4200000000000000000000000000000000000006;
    address constant POLYGON_WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address constant BASE_WETH = 0x4200000000000000000000000000000000000006;

    uint24 constant DEFAULT_SWAP_FEE = 30;
    uint24 constant STABLE_SWAP_FEE = 4;
    uint24 constant EXOTIC_SWAP_FEE = 100;

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
 */
library DeploymentVerification {
    function verifyDeployment(
        address factory,
        address router,
        address flashLoanProvider,
        address weth
    ) internal view returns (bool) {
        if (AMMFactory(factory).weth() != weth) return false;
        if (AMMFactory(factory).feeToSetter() == address(0)) return false;

        if (AMMRouter(router).factory() != factory) return false;
        if (AMMRouter(router).weth() != weth) return false;

        if (AMMFlashLoanProvider(flashLoanProvider).treasury() == address(0)) return false;

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
