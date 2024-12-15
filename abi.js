const tokenABI = [
    {
        "inputs": [
            { "internalType": "string", "name": "name_", "type": "string" },
            { "internalType": "string", "name": "symbol_", "type": "string" },
            { "internalType": "uint256", "name": "totalSupply_", "type": "uint256" },
            { "internalType": "address", "name": "recipient_", "type": "address" }
        ],
        "stateMutability": "nonpayable",
        "type": "constructor"
    },
    {
        "inputs": [],
        "name": "name",
        "outputs": [{ "internalType": "string", "name": "", "type": "string" }],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "symbol",
        "outputs": [{ "internalType": "string", "name": "", "type": "string" }],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            { "internalType": "address", "name": "account", "type": "address" }
        ],
        "name": "balanceOf",
        "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
        "stateMutability": "view",
        "type": "function"
    }
];

const swapperABI = [
    {
        "inputs": [
            { "internalType": "uint256", "name": "initialMinimumLiquidity", "type": "uint256" },
            { "internalType": "uint256", "name": "initialMaxSwapFee", "type": "uint256" }
        ],
        "stateMutability": "nonpayable",
        "type": "constructor"
    },
    {
        "inputs": [{ "internalType": "uint256", "name": "newMinimumLiquidity", "type": "uint256" }],
        "name": "setMinimumLiquidity",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [{ "internalType": "uint256", "name": "newMaxSwapFee", "type": "uint256" }],
        "name": "setMaxSwapFee",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [{ "internalType": "address", "name": "tokenAddress", "type": "address" }],
        "name": "addToken",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            { "internalType": "address", "name": "token0", "type": "address" },
            { "internalType": "address", "name": "token1", "type": "address" },
            { "internalType": "uint256", "name": "amount0", "type": "uint256" },
            { "internalType": "uint256", "name": "amount1", "type": "uint256" },
            { "internalType": "uint256", "name": "swapFee", "type": "uint256" }
        ],
        "name": "createPool",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            { "internalType": "bytes32", "name": "poolId", "type": "bytes32" },
            { "internalType": "uint256", "name": "newSwapFee", "type": "uint256" }
        ],
        "name": "setPoolSwapFee",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            { "internalType": "bytes32", "name": "poolId", "type": "bytes32" },
            { "internalType": "uint256", "name": "amount0", "type": "uint256" },
            { "internalType": "uint256", "name": "amount1", "type": "uint256" }
        ],
        "name": "addLiquidity",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            { "internalType": "bytes32", "name": "poolId", "type": "bytes32" },
            { "internalType": "uint256", "name": "amount0", "type": "uint256" },
            { "internalType": "uint256", "name": "amount1", "type": "uint256" }
        ],
        "name": "removeLiquidity",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            { "internalType": "bytes32", "name": "poolId", "type": "bytes32" },
            { "internalType": "address", "name": "tokenIn", "type": "address" },
            { "internalType": "uint256", "name": "amountIn", "type": "uint256" }
        ],
        "name": "swap",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            { "internalType": "uint256", "name": "inputAmount", "type": "uint256" },
            { "internalType": "uint256", "name": "inputReserve", "type": "uint256" },
            { "internalType": "uint256", "name": "outputReserve", "type": "uint256" },
            { "internalType": "uint256", "name": "swapFee", "type": "uint256" }
        ],
        "name": "getSwapAmount",
        "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
        "stateMutability": "pure",
        "type": "function"
    },
    {
        "inputs": [
            { "internalType": "address", "name": "token0", "type": "address" },
            { "internalType": "address", "name": "token1", "type": "address" }
        ],
        "name": "getPoolId",
        "outputs": [{ "internalType": "bytes32", "name": "", "type": "bytes32" }],
        "stateMutability": "pure",
        "type": "function"
    }
];
