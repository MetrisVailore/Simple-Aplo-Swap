abi = [
  {'inputs': [
    {'internalType': 'address', 'name': 'wethAddress', 'type': 'address'}, 
    {'internalType': 'uint256', 'name': 'initialMinimumLiquidity', 'type': 'uint256'}, 
    {'internalType': 'uint256', 'name': 'initialMaxSwapFee', 'type': 'uint256'}
  ], 
   'stateMutability': 'nonpayable', 'type': 'constructor'}, 
  {'inputs': [
    {'internalType': 'uint256', 'name': 'newMinimumLiquidity', 'type': 'uint256'}
  ], 
   'name': 'setMinimumLiquidity', 'outputs': [], 'stateMutability': 'nonpayable', 'type': 'function'}, 
  {'anonymous': False, 'inputs': 
   [{'indexed': True, 'internalType': 'address', 'name': 'sender', 'type': 'address'}, 
    {'indexed': True, 'internalType': 'bytes32', 'name': 'poolId', 'type': 'bytes32'}, 
    {'indexed': False, 'internalType': 'address', 'name': 'tokenIn', 'type': 'address'}, 
    {'indexed': False, 'internalType': 'uint256', 'name': 'amountIn', 'type': 'uint256'}, {'indexed': False, 'internalType': 'address', 'name': 'tokenOut', 'type': 'address'}, {'indexed': False, 'internalType': 'uint256', 'name': 'amountOut', 'type': 'uint256'}], 'name': 'Swap', 'type': 'event'}]
