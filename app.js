const web3 = new Web3(window.ethereum);
const contractAddress = "0xYourContractAddress"; // Замените на ваш контракт
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

async function init() {
    // Получить список токенов из контракта
    const tokenInSelect = document.getElementById('tokenIn');
    const tokenOutSelect = document.getElementById('tokenOut');

    // Замените на реальные данные ваших токенов
    const tokens = [
        { name: 'Token1', address: '0xToken1Address' },
        { name: 'Token2', address: '0xToken2Address' }
    ];

    // Заполнение селектов
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

    // Получение ликвидности пула
    const poolId = web3.utils.soliditySha3(tokens[0].address, tokens[1].address);
    const pool = await contract.methods.pools(poolId).call();

    // Отображение информации о ликвидности
    document.getElementById('liquidityInfo').textContent = `Token0: ${pool.token0Reserve}, Token1: ${pool.token1Reserve}`;

    // Обработка обмена
    document.getElementById('swapBtn').addEventListener('click', async () => {
        const tokenIn = tokenInSelect.value;
        const tokenOut = tokenOutSelect.value;
        const amountIn = document.getElementById('amountIn').value;

        if (tokenIn && tokenOut && amountIn) {
            // Получение суммы для обмена (с расчетом комиссии)
            const amountOut = await contract.methods.getSwapAmount(amountIn, pool.token0Reserve, pool.token1Reserve, pool.swapFee).call();
            document.getElementById('amountOut').value = amountOut;

            // Выполнение обмена
            await contract.methods.swap(poolId, tokenIn, amountIn).send({ from: ethereum.selectedAddress });
        }
    });
}

window.onload = init;
