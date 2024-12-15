let web3;
let contract;
let userAccount;

// Replace with your contract address and ABI
const contractAddress = '0x857F841e2cd3adE01FcC63F4c9AEeBdAB659ebCB';
const abi = [
    // Your contract ABI here (simplified for swap and getPoolId method)
    {
        "constant": true,
        "inputs": [
            { "name": "token0", "type": "address" },
            { "name": "token1", "type": "address" }
        ],
        "name": "getPoolId",
        "outputs": [
            { "name": "", "type": "bytes32" }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            { "name": "poolId", "type": "bytes32" },
            { "name": "tokenIn", "type": "address" },
            { "name": "amountIn", "type": "uint256" }
        ],
        "name": "swap",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    }
    // Add other ABI methods if needed
];

function connectWallet() {
    if (window.ethereum) {
        web3 = new Web3(window.ethereum);
        window.ethereum.request({ method: 'eth_requestAccounts' }).then(accounts => {
            userAccount = accounts[0]; // Store the user's wallet address
            console.log('Connected with account:', userAccount);
            contract = new web3.eth.Contract(abi, contractAddress);
        }).catch(error => {
            console.error('User denied account access:', error);
        });
    } else {
        alert('Please install MetaMask!');
    }
}

async function getPoolId(token0, token1) {
    try {
        const poolId = await contract.methods.getPoolId(token0, token1).call();
        return poolId;
    } catch (error) {
        console.error('Error getting pool ID:', error);
        alert('Error getting pool ID!');
        return null;
    }
}

async function approveToken(tokenAddress, amount) {
    const tokenContract = new web3.eth.Contract(ERC20_ABI, tokenAddress);
    try {
        const allowance = await tokenContract.methods.allowance(userAccount, contractAddress).call();
        if (allowance < amount) {
            await tokenContract.methods.approve(contractAddress, amount).send({ from: userAccount });
            console.log('Token approved');
        } else {
            console.log('Allowance already sufficient');
        }
    } catch (error) {
        console.error('Approval failed', error);
    }
}

async function swapTokens() {
    const token0 = document.getElementById('token0').value;
    const token1 = document.getElementById('token1').value;
    const amountIn = document.getElementById('amount').value;

    if (!web3.utils.isAddress(token0) || !web3.utils.isAddress(token1)) {
        alert('Invalid token addresses');
        return;
    }

    if (amountIn <= 0) {
        alert('Invalid amount');
        return;
    }

    const poolId = await getPoolId(token0, token1);
    if (!poolId) {
        alert('Pool does not exist!');
        return;
    }

    console.log('Swapping tokens in pool:', poolId);

    // Approve the token transfer before swapping
    await approveToken(token0, amountIn); // Approve token0 to be used by the contract

    // Call the swap function
    try {
        await contract.methods.swap(poolId, token0, amountIn).send({ from: userAccount });
        console.log(`Successfully swapped ${amountIn} of ${token0}`);
    } catch (error) {
        console.error('Swap failed:', error);
    }
}
