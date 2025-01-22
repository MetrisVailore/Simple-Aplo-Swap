import ast
import json

from web3 import Web3
import matplotlib.pyplot as plt
import pandas as pd

# Подключение к RPC-узлу
RPC_URL = "https://pub1.aplocoin.com"
web3 = Web3(Web3.HTTPProvider(RPC_URL))

# Адрес контракта и ABI
SWAPPER_ADDRESS = "0x3845B5B026aD933956A0D5dA19FF21b3c4520BD4"  # Замените на адрес контракта Swapper
SWAPPER_ABI = [
    {
        "inputs": [
            {"internalType": "address", "name": "wethAddress", "type": "address"},
            {"internalType": "uint256", "name": "initialMinimumLiquidity", "type": "uint256"},
            {"internalType": "uint256", "name": "initialMaxSwapFee", "type": "uint256"}
        ],
        "stateMutability": "nonpayable",
        "type": "constructor"
    },
    {
        "inputs": [{"internalType": "uint256", "name": "newMinimumLiquidity", "type": "uint256"}],
        "name": "setMinimumLiquidity",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "uint256", "name": "newMaxSwapFee", "type": "uint256"}],
        "name": "setMaxSwapFee",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "address", "name": "token0", "type": "address"},
            {"internalType": "address", "name": "token1", "type": "address"},
            {"internalType": "uint256", "name": "amount0", "type": "uint256"},
            {"internalType": "uint256", "name": "amount1", "type": "uint256"},
            {"internalType": "uint256", "name": "swapFee", "type": "uint256"}
        ],
        "name": "createPool",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "bytes32", "name": "poolId", "type": "bytes32"},
            {"internalType": "uint256", "name": "newSwapFee", "type": "uint256"}
        ],
        "name": "setPoolSwapFee",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "bytes32", "name": "poolId", "type": "bytes32"},
            {"internalType": "uint256", "name": "amount0", "type": "uint256"},
            {"internalType": "uint256", "name": "amount1", "type": "uint256"}
        ],
        "name": "addLiquidity",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "bytes32", "name": "poolId", "type": "bytes32"},
            {"internalType": "uint256", "name": "amount0", "type": "uint256"},
            {"internalType": "uint256", "name": "amount1", "type": "uint256"}
        ],
        "name": "removeLiquidity",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "bytes32", "name": "poolId", "type": "bytes32"},
            {"internalType": "address", "name": "tokenIn", "type": "address"},
            {"internalType": "uint256", "name": "amountIn", "type": "uint256"}
        ],
        "name": "swap",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "uint256", "name": "inputAmount", "type": "uint256"},
            {"internalType": "uint256", "name": "inputReserve", "type": "uint256"},
            {"internalType": "uint256", "name": "outputReserve", "type": "uint256"},
            {"internalType": "uint256", "name": "swapFee", "type": "uint256"}
        ],
        "name": "getSwapAmount",
        "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
        "stateMutability": "pure",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "address", "name": "token0", "type": "address"},
            {"internalType": "address", "name": "token1", "type": "address"}
        ],
        "name": "getPoolId",
        "outputs": [{"internalType": "bytes32", "name": "", "type": "bytes32"}],
        "stateMutability": "pure",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "address", "name": "owner", "type": "address"}],
        "name": "getPoolsByOwner",
        "outputs": [{"internalType": "bytes32[]", "name": "", "type": "bytes32[]"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "stateMutability": "payable",
        "type": "receive"
    },
    {
        "inputs": [{"internalType": "bytes32", "name": "poolId", "type": "bytes32"}],
        "name": "pools",
        "outputs": [
            {"internalType": "uint256", "name": "token0Reserve", "type": "uint256"},
            {"internalType": "uint256", "name": "token1Reserve", "type": "uint256"},
            {"internalType": "address", "name": "token0", "type": "address"},
            {"internalType": "address", "name": "token1", "type": "address"},
            {"internalType": "address", "name": "owner", "type": "address"},
            {"internalType": "uint256", "name": "swapFee", "type": "uint256"}
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "internalType": "address", "name": "sender", "type": "address"},
            {"indexed": True, "internalType": "bytes32", "name": "poolId", "type": "bytes32"},
            {"indexed": False, "internalType": "address", "name": "tokenIn", "type": "address"},
            {"indexed": False, "internalType": "uint256", "name": "amountIn", "type": "uint256"},
            {"indexed": False, "internalType": "address", "name": "tokenOut", "type": "address"},
            {"indexed": False, "internalType": "uint256", "name": "amountOut", "type": "uint256"}
        ],
        "name": "Swap",
        "type": "event"
    }

]

# ABI контракта Swapper
swapper = web3.eth.contract(address=SWAPPER_ADDRESS, abi=SWAPPER_ABI)

# Параметры события
SWAP_EVENT_SIGNATURE = '0x' + web3.keccak(text="Swap(address,bytes32,address,uint256,address,uint256)").hex()

print("SWAP_EVENT_SIGNATURE: ", SWAP_EVENT_SIGNATURE)


def fetch_events():
    """Получает события Swap из блокчейна."""
    latest_block = web3.eth.block_number
    events = []

    # Запрос событий за последние 10 000 блоков (можно изменить диапазон)
    try:
        logs = web3.eth.get_logs({
            "fromBlock": latest_block - 10000,
            "toBlock": latest_block,
            "address": SWAPPER_ADDRESS,  # Адрес контракта
            "topics": [SWAP_EVENT_SIGNATURE]  # Сигнатура события
        })
        # print(logs)
    except Exception as e:
        print(f"Ошибка запроса логов: {str(e)}")
        return []

    for log in logs:
        try:
            log = str(log).replace('AttributeDict', '').replace('(', '').replace(')', '').replace('HexBytes', '')
            log_dict = ast.literal_eval(log)
            log_dict['topics'] = [bytes.fromhex(topic[2:]) for topic in log_dict['topics']]
            log_dict['data'] = bytes.fromhex(log_dict['data'][2:])
            log_dict['transactionHash'] = bytes.fromhex(log_dict['transactionHash'][2:])
            log_dict['blockHash'] = bytes.fromhex(log_dict['blockHash'][2:])
            # sender = "0x" + topics[1][26:].hex()
            # event_signature = log_dict['topics'][0].hex()
            sender = "0x" + log_dict['topics'][1].hex()[-40:]  # Адрес — последние 20 байт
            # tx_hash = log_dict['topics'][2].hex()  # txHash — 32 байта
            data = log_dict['data']

            receiver = "0x" + data[12:32].hex()  # Адрес — последние 20 байт в 32 байтах
            amount = int.from_bytes(data[32:64], "big")  # uint256 — 32 байта
            token = "0x" + data[64 + 12:64 + 32].hex()  # Адрес — последние 20 байт
            timestamp = int.from_bytes(data[96:128], "big")  # uint256 — 32 байта

            print(f"Pool Address: {log_dict['address']}")
            print(f"Sender: {sender}")
            print(f"Token in: {receiver}")
            print(f"Token out: {token}")
            print(f"Amount: {amount}")
            print(f"Timestamp: {timestamp}")
            # print(f"Data: {log_dict['data']}")
            print(f"Block Number: {log_dict['blockNumber']}")
            print(f"Transaction Hash: {log_dict['transactionHash'].hex()}")
            print(f"Log Index: {log_dict['logIndex']}")
        except Exception as e:
            print(f"Error processing log: {log} - {str(e)}")
