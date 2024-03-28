// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "./vendor/uni-v3/core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "./vendor/uni-v3/core/interfaces/callback/IUniswapV3SwapCallback.sol";
import {TransferLib, IERC20} from "./utils/TransferLib.sol";

contract Arbitrage is IUniswapV3SwapCallback {
  uint160 internal constant MIN_SQRT_RATIO = 4295128739;
  uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

  address internal currentv3Pool;

  modifier v3Swap(address pool) {
    address before = currentv3Pool;
    currentv3Pool = pool;
    _;
    currentv3Pool = before;
  }

  function swapOnUniswapV3(address fromToken, address toToken, uint256 fromAmount, address pool) internal v3Swap(pool) {
    bool zeroForOne = fromToken < toToken; // tokenIn < tokenOut
    IUniswapV3Pool(pool).swap(
      address(this),
      zeroForOne,
      int256(fromAmount),
      zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1,
      abi.encode(fromToken)
    );
  }

  function uniswapV3SwapCallbackVerifier(address origin) public view virtual returns (bool) {
    return origin == currentv3Pool;
  }

  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
    require(uniswapV3SwapCallbackVerifier(msg.sender), "Arbitrage: Invalid sender");
    address tokenToTransfer = abi.decode(data, (address));
    uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
    TransferLib.transferToken(IERC20(tokenToTransfer), msg.sender, amountToPay);
  }
}
