// Проверяем, что MetaMask подключен
if (typeof window.ethereum !== 'undefined') {
    console.log('MetaMask is installed!');
}

let provider = new ethers.providers.Web3Provider(window.ethereum);
let signer = provider.getSigner();

// Адрес контракта Swapper по умолчанию
const swapperAddress = '0x857F841e2cd3adE01FcC63F4c9AEeBdAB659ebCB';  // Замените на реальный адрес контракта Swapper

// ABI для ERC20 токенов (для approve)
const erc20ABI = [
    "function approve(address spender, uint256 amount) public returns (bool)"
];

// ABI для контракта Swapper
const swapperABI = [
    "function swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 minAmountOut) external",
    "function getSwapAmount(address tokenIn, uint256 amountIn, address tokenOut) external view returns (uint256)"
];

// Функция для получения значений из формы
function getFormData() {
    const tokenIn = document.getElementById('tokenIn').value; // Адрес токена для ввода
    const tokenOut = document.getElementById('tokenOut').value; // Адрес токена для обмена
    const amountIn = ethers.utils.parseUnits(document.getElementById('amountIn').value, 18); // Сумма токенов для обмена
    const minAmountOut = ethers.utils.parseUnits(document.getElementById('minAmountOut').value, 18); // Минимум для обмена
    return { tokenIn, tokenOut, amountIn, minAmountOut };
}

// Функция для approve токенов
async function approveTokens(tokenAddress, spender, amount) {
    const tokenContract = new ethers.Contract(tokenAddress, erc20ABI, signer);
    
    try {
        const tx = await tokenContract.approve(spender, amount);
        await tx.wait();
        console.log(`Approved ${amount} tokens for ${spender}`);
    } catch (error) {
        console.error('Approve failed', error);
    }
}

// Функция для обмена токенов
async function swapTokens(tokenIn, amountIn, tokenOut, minAmountOut) {
    const swapperContract = new ethers.Contract(swapperAddress, swapperABI, signer);
    
    try {
        const tx = await swapperContract.swap(tokenIn, amountIn, tokenOut, minAmountOut);
        await tx.wait();
        console.log(`Swapped ${amountIn} tokens from ${tokenIn} to ${tokenOut}`);
    } catch (error) {
        console.error('Swap failed', error);
    }
}

// Обработчик нажатия кнопки для выполнения транзакции
async function handleSwap() {
    const { tokenIn, tokenOut, amountIn, minAmountOut } = getFormData();

    // Получаем аккаунт пользователя
    const userAddress = await signer.getAddress();
    console.log(`User Address: ${userAddress}`);

    // Утверждаем токены для контракта Swapper
    await approveTokens(tokenIn, swapperAddress, amountIn);

    // Выполняем обмен токенов
    await swapTokens(tokenIn, amountIn, tokenOut, minAmountOut);
}

// Вешаем обработчик на кнопку
document.getElementById('swapButton').addEventListener('click', handleSwap);
