const swapperABI = [
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
            { "internalType": "address", "name": "token0", "type": "address" },
            { "internalType": "address", "name": "token1", "type": "address" }
        ],
        "name": "getPoolId",
        "outputs": [
            { "internalType": "bytes32", "name": "", "type": "bytes32" }
        ],
        "stateMutability": "view",
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
            { "internalType": "address", "name": "tokenIn", "type": "address" },
            { "internalType": "address", "name": "spender", "type": "address" },
            { "internalType": "uint256", "name": "amount", "type": "uint256" }
        ],
        "name": "approve",
        "outputs": [
            { "internalType": "bool", "name": "", "type": "bool" }
        ],
        "stateMutability": "nonpayable",
        "type": "function"
    }
];


const provider = new ethers.BrowserProvider(window.ethereum);
let signer;
let swapperContract;

async function connectWallet() {
    if (window.ethereum) {
        await window.ethereum.request({ method: 'eth_requestAccounts' });
        signer = await provider.getSigner();
        console.log('Connected wallet address:', await signer.getAddress());
    } else {
        alert('Please install MetaMask!');
    }
}

async function initContract() {
    const swapperAddress = '0x857F841e2cd3adE01FcC63F4c9AEeBdAB659ebCB';  // Replace with your contract address
    swapperContract = new ethers.Contract(swapperAddress, swapperABI, signer);
}

async function createPool(token0Address, token1Address, amount0, amount1, swapFee) {
    try {
        const tx = await swapperContract.createPool(
            token0Address, 
            token1Address, 
            ethers.utils.parseUnits(amount0, 18), // Assume 18 decimals for token0
            ethers.utils.parseUnits(amount1, 18), // Assume 18 decimals for token1
            swapFee
        );
        console.log('Pool created!', tx);
        await tx.wait();
    } catch (error) {
        console.error('Error creating pool:', error);
    }
}

async function swapTokens(tokenInAddress, amountIn, token0Address, token1Address) {
    try {
        if (!window.ethereum) {
            alert('Please install MetaMask!');
            return;
        }

        // Request account access if needed
        await ethereum.request({ method: 'eth_requestAccounts' });

        // Create a Web3 provider using MetaMask's injected provider
        const provider = new ethers.providers.Web3Provider(window.ethereum);
        const signer = provider.getSigner();

        const swapperContractAddress = '0x857F841e2cd3adE01FcC63F4c9AEeBdAB659ebCB'; // Add your Swapper contract address here
        const swapperAbi = [
            // Add your contract ABI here
        ];

        const swapperContract = new ethers.Contract(swapperContractAddress, swapperAbi, signer);

        // Get the poolId for the swap
        const poolId = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(
            ["address", "address"],
            [token0Address, token1Address]
        ));

        // Approve tokens before swapping
        const tokenIn = new ethers.Contract(tokenInAddress, ['function approve(address spender, uint256 amount) public returns (bool)'], signer);
        const amount = ethers.utils.parseUnits(amountIn, 18); // Assuming 18 decimals

        // Approve the contract to spend the input tokens
        const approval = await tokenIn.approve(swapperContractAddress, amount);
        await approval.wait();

        // Perform the swap
        const swapTx = await swapperContract.swap(poolId, tokenInAddress, amount);
        await swapTx.wait();

        alert('Swap successful!');
    } catch (error) {
        console.error('Error swapping tokens:', error);
        alert('Error: ' + error.message);
    }
}


async function getPoolId(token0Address, token1Address) {
    try {
        const poolId = await swapperContract.getPoolId(token0Address, token1Address);
        console.log('Pool ID:', poolId);
        return poolId;
    } catch (error) {
        console.error('Error getting pool ID:', error);
    }
}

// Connect the wallet and initialize the contract
document.getElementById('connectWalletBtn').addEventListener('click', async () => {
    await connectWallet();
    await initContract();
});

// Example usage for creating a pool and swapping tokens
document.getElementById('createPoolBtn').addEventListener('click', async () => {
    const token0 = document.getElementById('token0Address').value;
    const token1 = document.getElementById('token1Address').value;
    const amount0 = document.getElementById('amount0').value;
    const amount1 = document.getElementById('amount1').value;
    const swapFee = document.getElementById('swapFee').value;

    await createPool(token0, token1, amount0, amount1, swapFee);
});

document.getElementById('swapBtn').addEventListener('click', async () => {
    const tokenInAddress = document.getElementById('tokenInAddress').value;
    const amountIn = document.getElementById('amountIn').value;
    const token0Address = document.getElementById('token0AddressSwap').value;
    const token1Address = document.getElementById('token1AddressSwap').value;

    await swapTokens(tokenInAddress, amountIn, token0Address, token1Address);
});
