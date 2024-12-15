const SWAPPER_ADDRESS = "0x857F841e2cd3adE01FcC63F4c9AEeBdAB659ebCB";
const SWAPPER_ABI = [
  "function swap(bytes32 poolId, address tokenIn, uint256 amountIn) external",
];
const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) external view returns (uint256)",
];

document.getElementById("swapButton").addEventListener("click", async () => {
  const tokenIn = document.getElementById("tokenIn").value;
  const tokenOut = document.getElementById("tokenOut").value;
  const amountIn = document.getElementById("amountIn").value;

  if (!tokenIn || !tokenOut || !amountIn) {
    setStatus("Please fill in all fields");
    return;
  }

  try {
    const provider = new ethers.providers.Web3Provider(window.ethereum);
    await provider.send("eth_requestAccounts", []);
    const signer = provider.getSigner();

    // Step 1: Approve the token
    setStatus("Approving token...");
    await approveToken(tokenIn, signer, amountIn);

    // Step 2: Perform the swap
    const swapper = new ethers.Contract(SWAPPER_ADDRESS, SWAPPER_ABI, signer);
    const poolId = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(["address", "address"], [tokenIn, tokenOut])
    );

    setStatus("Processing swap...");
    const tx = await swapper.swap(poolId, tokenIn, ethers.utils.parseUnits(amountIn, 18));
    await tx.wait();
    setStatus("Swap successful!");
  } catch (error) {
    console.error(error);
    setStatus("Swap failed. Check the console for details.");
  }
});

async function approveToken(tokenAddress, signer, amount) {
  const erc20 = new ethers.Contract(tokenAddress, ERC20_ABI, signer);

  // Check current allowance
  const allowance = await erc20.allowance(await signer.getAddress(), SWAPPER_ADDRESS);
  const requiredAmount = ethers.utils.parseUnits(amount, 18);

  if (allowance.gte(requiredAmount)) {
    setStatus("Token already approved.");
    return;
  }

  // Approve the token
  const tx = await erc20.approve(SWAPPER_ADDRESS, requiredAmount);
  await tx.wait();
  setStatus("Token approved.");
}

function setStatus(message) {
  document.getElementById("status").textContent = message;
}
