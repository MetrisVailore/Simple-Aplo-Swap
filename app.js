const web3 = new Web3(window.ethereum);
const contractAddress = "0x857F841e2cd3adE01FcC63F4c9AEeBdAB659ebCB"; // Замените на ваш контракт
const contractABI = const contractABI = [
    // Functions for swapping
    {
        "inputs": [
            {
                "internalType": "bytes32",
                "name": "poolId",
                "type": "bytes32"
            },
            {
                "internalType": "address",
                "name": "tokenIn",
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
                "internalType": "bytes32",
                "name": "poolId",
                "type": "bytes32"
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
    // Functions for removing liquidity
    {
        "inputs": [
            {
                "internalType": "bytes32",
                "name": "poolId",
                "type": "bytes32"
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
            },
            {
                "internalType": "uint256",
                "name": "swapFee",
                "type": "uint256"
            }
        ],
        "name": "createPool",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    // Functions for setting swap fee
    {
        "inputs": [
            {
                "internalType": "bytes32",
                "name": "poolId",
                "type": "bytes32"
            },
            {
                "internalType": "uint256",
                "name": "newSwapFee",
                "type": "uint256"
            }
        ],
        "name": "setPoolSwapFee",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    // Functions for adding a token to the allowed list
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
    },
    // Functions for setting minimum liquidity
    {
        "inputs": [
            {
                "internalType": "uint256",
                "name": "newMinimumLiquidity",
                "type": "uint256"
            }
        ],
        "name": "setMinimumLiquidity",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    // Functions for setting max swap fee
    {
        "inputs": [
            {
                "internalType": "uint256",
                "name": "newMaxSwapFee",
                "type": "uint256"
            }
        ],
        "name": "setMaxSwapFee",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    }
];

const contract = new web3.eth.Contract(contractABI, contractAddress);

const tokenInSelect = document.getElementById('tokenIn');
const tokenOutSelect = document.getElementById('tokenOut');
const tokenInAmount = document.getElementById('tokenInAmount');
const tokenOutAmount = document.getElementById('tokenOutAmount');
const swapFeeElement = document.getElementById('swapFee');
const liquidityInfo = document.getElementById('liquidityInfo');
const swapBtn = document.getElementById('swapBtn');

// Данные токенов для выбора (пример)
const tokens = [
    { name: 'Token1', address: '0xToken1Address' },
    { name: 'Token2', address: '0xToken2Address' },
];

// Инициализация интерфейса
async function init() {
    // Заполняем выпадающие списки токенов
    tokens.forEach(token => {
        const optionIn = document.createElement('option');
        optionIn.value = token.address;
        optionIn.textContent = token.name;
        tokenInSelect.appendChild(optionIn);

        const optionOut = document.createElement('option');
        optionOut.value = token.address;
        optionOut.textContent = token.name;
        tokenOutSelect.appendChild(optionOut);
    });

    // Получаем данные по пулу
    const poolId = web3.utils.soliditySha3(tokens[0].address, tokens[1].address);
    const pool = await contract.methods.pools(poolId).call();

    // Отображаем информацию о ликвидности
    liquidityInfo.textContent = `Token0: ${pool.token0Reserve}, Token1: ${pool.token1Reserve}`;
    swapFeeElement.textContent = `${pool.swapFee / 100}%`;

    // Обработчик ввода количества для обмена
    tokenInAmount.addEventListener('input', async () => {
        const amountIn = tokenInAmount.value;
        const pool = await contract.methods.pools(poolId).call();
        const amountOut = await contract.methods.getSwapAmount(amountIn, pool.token0Reserve, pool.token1Reserve, pool.swapFee).call();
        tokenOutAmount.value = amountOut;
    });

    // Обработчик обмена
    swapBtn.addEventListener('click', async () => {
        const tokenIn = tokenInSelect.value;
        const tokenOut = tokenOutSelect.value;
        const amountIn = tokenInAmount.value;

        if (tokenIn && tokenOut && amountIn) {
            // Выполнение обмена через контракт
            await contract.methods.swap(poolId, tokenIn, amountIn).send({ from: ethereum.selectedAddress });
        }
    });
}

window.onload = init;
