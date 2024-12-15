let provider;
let signer;
let contract;
let userAccount;

// Replace with your contract address and ABI
const contractAddress = '0x857F841e2cd3adE01FcC63F4c9AEeBdAB659ebCB';
const abi = [
    // Add your ABI here (same as before)
];

async function connectWallet() {
    if (window.ethereum) {
        provider = new ethers.providers.Web3Provider(window.ethereum);
        await window.ethereum.request({ method: 'eth_requestAccounts' });
        signer = provider.getSigner();
        userAccount = await signer.getAddress();
        
        console.log('Connected with account:', userAccount);
        contract = new ethers.Contract(contractAddress, abi, signer);
    } else {
        alert('Please install MetaMask!');
    }
}

async function getPoolId(token0, token1) {
    try {
        const poolId = await contract.getPoolId(token0, token1);
        return poolId;
    } catch (error) {
        console.error('Error getting pool ID:', error);
        alert('Error getting pool ID!');
        return null;
    }
}

async function approveToken(tokenAddress, amount) {
    const tokenContract = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
    try {
        const allowance = await tokenContract.allowance(userAccount, contractAddress);
        if (allowance < amount) {
            const tx = await tokenContract.approve(contractAddress, amount);
            await tx.wait(); // Wait for the transaction to be mined
            console.log('Token approved');
        } else {
            console.log('Allowance already sufficient');
        }
    } catch (error) {
        console.error('Approval failed', error);
        alert('Token approval failed.');
    }
}

async function swapTokens() {
    const token0 = document.getElementById('token0').value;
    const token1 = document.getElementById('token1').value;
    const amountIn = document.getElementById('amount').value;

    if (!ethers.utils.isAddress(token0) || !ethers.utils.isAddress(token1)) {
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
        const tx = await contract.swap(poolId, token0, amountIn);
        await tx.wait(); // Wait for the transaction to be mined
        console.log(`Successfully swapped ${amountIn} of ${token0}`);
    } catch (error) {
        console.error('Swap failed:', error);
        alert('Swap failed.');
    }
}
