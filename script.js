const customRpcUrl = 'https://pub1.aplocoin.com'; // Замените на URL вашего RPC
const expectedChainId = 28282; // Укажите Chain ID вашей кастомной сети
const swapperContractAddress = '0x857F841e2cd3adE01FcC63F4c9AEeBdAB659ebCB'; // Адрес вашего контракта swap

// Подключаемся к кастомной сети через ethers.js
const provider = new ethers.providers.JsonRpcProvider(customRpcUrl);

// Подключение с MetaMask
async function connectWallet() {
    if (window.ethereum) {
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        const signer = provider.getSigner();
        return { signer, accounts };
    } else {
        alert("MetaMask not detected. Please install MetaMask.");
        return null;
    }
}

// Функция для проверки сети
async function checkNetwork() {
    const network = await provider.getNetwork();
    if (network.chainId !== expectedChainId) {
        alert(network.chainId);
        alert(expectedChainId);
        alert("You are connected to the wrong network! Please switch to the correct network.");
        return false;
    }
    return true;
}

// Функция для approve токенов
async function approveToken(tokenAddress, spenderAddress, amount) {
    const { signer, accounts } = await connectWallet();
    if (!signer) return;

    const tokenABI = [
        "function approve(address spender, uint256 amount) public returns (bool)"
    ];

    const tokenContract = new ethers.Contract(tokenAddress, tokenABI, signer);

    try {
        const isNetworkValid = await checkNetwork();
        if (!isNetworkValid) return;

        const parsedAmount = ethers.utils.parseUnits(amount.toString(), 18); // 18 десятичных знаков

        // Отправляем approve транзакцию
        const tx = await tokenContract.approve(spenderAddress, parsedAmount);
        document.getElementById('status').textContent = "Approval sent, waiting for confirmation...";

        await tx.wait(); // Ожидаем завершения транзакции

        document.getElementById('status').textContent = "Approval successful!";
    } catch (error) {
        console.error("Approval failed:", error);
        document.getElementById('status').textContent = "Approval failed. Check the console for details.";
    }
}

// Функция для обмена токенов через Swapper контракт
async function swapTokens(poolId, tokenA, tokenB, amountIn) {
    const { signer, accounts } = await connectWallet();
    if (!signer) return;

    const swapperABI = [
        "function swap(bytes32 poolId, address tokenIn, uint256 amountIn) public"
    ];

    const swapperContract = new ethers.Contract(swapperContractAddress, swapperABI, signer);

    try {
        const isNetworkValid = await checkNetwork();
        if (!isNetworkValid) return;

        const parsedAmount = ethers.utils.parseUnits(amountIn.toString(), 18); // 18 десятичных знаков

        // Сначала делаем approve для контракта swap
        await approveToken(tokenA, swapperContractAddress, parsedAmount);

        // Выполняем обмен
        const tx = await swapperContract.swap(poolId, tokenA, parsedAmount);
        document.getElementById('status').textContent = "Swap in progress...";

        await tx.wait(); // Ожидаем завершения транзакции

        document.getElementById('status').textContent = "Swap successful!";
    } catch (error) {
        console.error("Swap failed:", error);
        document.getElementById('status').textContent = "Swap failed. Check the console for details.";
    }
}

// Обработчик события кнопки swap
document.getElementById('swapButton').addEventListener('click', () => {
    const tokenAddressA = document.getElementById('tokenAddressA').value;
    const tokenAddressB = document.getElementById('tokenAddressB').value;
    const amountIn = document.getElementById('amountIn').value;
    const poolId = document.getElementById('poolId').value;

    if (!tokenAddressA || !tokenAddressB || !amountIn || !poolId) {
        alert("Please fill all fields.");
        return;
    }

    swapTokens(poolId, tokenAddressA, tokenAddressB, amountIn);
});
