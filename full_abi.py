abi = [
  {
    "type": "constructor",
    "stateMutability": "nonpayable",
    "inputs": [
      {
        "internalType": "address",
        "name": "wethAddress",
        "type": "address"
      },
      {
        "internalType": "uint256",
        "name": "initialMinimumLiquidity",
        "type": "uint256"
      },
      {
        "internalType": "uint256",
        "name": "initialMaxSwapFee",
        "type": "uint256"
      }
    ]
  },
  {
    "type": "function",
    "name": "setMinimumLiquidity",
    "stateMutability": "nonpayable",
    "inputs": [
      {
        "internalType": "uint256",
        "name": "newMinimumLiquidity",
        "type": "uint256"
      }
    ],
    "outputs": []
  },
  {
    "type": "event",
    "name": "Swap",
    "anonymous": false,
    "inputs": [
      {
        "indexed": true,
        "internalType": "address",
        "name": "sender",
        "type": "address"
      },
      {
        "indexed": true,
        "internalType": "bytes32",
        "name": "poolId",
        "type": "bytes32"
      },
      {
        "indexed": false,
        "internalType": "address",
        "name": "tokenIn",
        "type": "address"
      },
      {
        "indexed": false,
        "internalType": "uint256",
        "name": "amountIn",
        "type": "uint256"
      },
      {
        "indexed": false,
        "internalType": "address",
        "name": "tokenOut",
        "type": "address"
      },
      {
        "indexed": false,
        "internalType": "uint256",
        "name": "amountOut",
        "type": "uint256"
      }
    ]
  }
]
