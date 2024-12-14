// Ethereum setup using ethers.js
let provider;
let signer;
let contract;

const contractAddress = "0x92f29B1c684DEdF33e3104BC8A58531aA833d31c"; // Replace with actual contract address
const contractABI = [
    // Functions for swapping
    {
        "inputs": [
            {
                "internalType": "address",
                "name": "tokenIn",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "tokenOut",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "amountIn",
                "type": "uint256"
            }
        ],
        "name": "swap",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    // Functions for adding liquidity
    {
        "inputs": [
            {
                "internalType": "address",
                "name": "token0",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "token1",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "amount0",
                "type": "uint256"
            },
            {
                "internalType": "uint256",
                "name": "amount1",
                "type": "uint256"
            }
        ],
        "name": "addLiquidity",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    // Functions for creating a pool
    {
        "inputs": [
            {
                "internalType": "address",
                "name": "token0",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "token1",
                "type": "address"
            }
        ],
        "name": "createPool",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    // Functions for removing liquidity
    {
        "inputs": [
            {
                "internalType": "address",
                "name": "token0",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "token1",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "amount0",
                "type": "uint256"
            },
            {
                "internalType": "uint256",
                "name": "amount1",
                "type": "uint256"
            }
        ],
        "name": "removeLiquidity",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    // Function for checking swap amount
    {
        "inputs": [
            {
                "internalType": "uint256",
                "name": "inputAmount",
                "type": "uint256"
            },
            {
                "internalType": "uint256",
                "name": "inputReserve",
                "type": "uint256"
            },
            {
                "internalType": "uint256",
                "name": "outputReserve",
                "type": "uint256"
            }
        ],
        "name": "getSwapAmount",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "stateMutability": "pure",
        "type": "function"
    },
    // Function for getting pool ID
    {
        "inputs": [
            {
                "internalType": "address",
                "name": "token0",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "token1",
                "type": "address"
            }
        ],
        "name": "getPoolId",
        "outputs": [
            {
                "internalType": "bytes32",
                "name": "",
                "type": "bytes32"
            }
        ],
        "stateMutability": "pure",
        "type": "function"
    },
    // Function for adding a token to the allowed list
    {
        "inputs": [
            {
                "internalType": "address",
                "name": "tokenAddress",
                "type": "address"
            }
        ],
        "name": "addToken",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    }
];


async function connectWallet() {
    if (window.ethereum) {
        provider = new ethers.providers.Web3Provider(window.ethereum);
        await provider.send("eth_requestAccounts", []);
        signer = provider.getSigner();
        const address = await signer.getAddress();
        document.getElementById("walletAddress").innerText = address;
        contract = new ethers.Contract(contractAddress, contractABI, signer);
    } else {
        alert("Please install MetaMask!");
    }
}

async function swapTokens() {
    const token0 = document.getElementById("token0").value;
    const token1 = document.getElementById("token1").value;
    const amount0 = document.getElementById("amount0").value;

    if (!token0 || !token1 || !amount0) {
        alert("Please fill all the fields!");
        return;
    }

    const tx = await contract.swap(
        token0,
        token1,
        ethers.utils.parseUnits(amount0, 18) // Adjust decimals if needed
    );
    await tx.wait();
    alert("Swap successful!");
}

async function addLiquidity() {
    const token0 = document.getElementById("addToken0").value;
    const token1 = document.getElementById("addToken1").value;
    const amount0 = document.getElementById("amountAdd0").value;
    const amount1 = document.getElementById("amountAdd1").value;

    if (!token0 || !token1 || !amount0 || !amount1) {
        alert("Please fill all the fields!");
        return;
    }

    const tx = await contract.addLiquidity(
        token0,
        token1,
        ethers.utils.parseUnits(amount0, 18), // Adjust decimals if needed
        ethers.utils.parseUnits(amount1, 18)  // Adjust decimals if needed
    );
    await tx.wait();
    alert("Liquidity added successfully!");
}

document.getElementById("connectWalletBtn").addEventListener("click", connectWallet);
document.getElementById("swapBtn").addEventListener("click", swapTokens);
document.getElementById("addLiquidityBtn").addEventListener("click", addLiquidity);
