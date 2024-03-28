// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "./vendor/uni-v3/core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "./vendor/uni-v3/core/interfaces/callback/IUniswapV3SwapCallback.sol";
import {TransferLib, IERC20} from "./utils/TransferLib.sol";
import {IUniswapV2Callee} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

enum SwapType {
  UNI_V2,
  UNI_V3
}

contract Arbitrage is IUniswapV3SwapCallback, IUniswapV2Callee {
  uint160 internal constant MIN_SQRT_RATIO = 4295128739;
  uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

  address internal currentv3Pool;
  address internal currentv2Pair;

  struct SwapRoute {
    address fromToken;
    address toToken;
    uint256 amountIn;
    address pool;
    SwapType swapType;
  }

  modifier v3Swap(address pool) {
    address before = currentv3Pool;
    currentv3Pool = pool;
    _;
    currentv3Pool = before;
  }

  modifier v3Callback() {
    require(msg.sender == currentv3Pool, "Arbitrage: Invalid sender");
    _;
  }

  modifier v2Swap(address pair) {
    address before = currentv2Pair;
    currentv2Pair = pair;
    _;
    currentv2Pair = before;
  }

  modifier v2Callback(address sender) {
    require(msg.sender == currentv2Pair && sender == address(this), "Arbitrage: Invalid sender");
    _;
  }

  function swapOnUniswapV3(SwapRoute[] memory swapRoutes, uint256 step) internal v3Swap(swapRoutes[step].pool) {
    SwapRoute memory swapRoute = swapRoutes[step];
    bool zeroForOne = swapRoute.fromToken < swapRoute.toToken; // tokenIn < tokenOut
    IUniswapV3Pool(swapRoute.pool).swap(
      address(this),
      zeroForOne,
      int256(swapRoute.amountIn),
      zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1,
      abi.encode(swapRoutes, step)
    );
  }

  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
    external
    override
    v3Callback
  {
    // At this point we have received the tokens from the pool
    // We need to transfer the tokens we owe to the pool by the end of the call
    (SwapRoute[] memory swapRoutes, uint256 step) = abi.decode(data, (SwapRoute[], uint256));
    handleRoute(swapRoutes, step + 1);
    uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
    TransferLib.transferToken(IERC20(swapRoutes[step].fromToken), msg.sender, amountToPay);
  }

  function getAmountOutUniV2(uint256 amountIn, address pair, bool zeroForOne) internal view returns (uint256 amountOut) {
    (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();
    uint256 reserveIn = zeroForOne ? reserve0 : reserve1;
    uint256 reserveOut = zeroForOne ? reserve1 : reserve0;
    require(amountIn > 0, "Arbitrage: INSUFFICIENT_INPUT_AMOUNT");
    require(reserveIn > 0 && reserveOut > 0, "Arbitrage: INSUFFICIENT_LIQUIDITY");
    uint256 amountInWithFee = amountIn * 997;
    uint256 numerator = amountInWithFee * reserveOut;
    uint256 denominator = reserveIn * 1000 + amountInWithFee;
    amountOut = numerator / denominator;
  }

  function swapOnUniswapV2(SwapRoute[] memory swapRoutes, uint256 step) internal v2Swap(swapRoutes[step].pool) {
    SwapRoute memory swapRoute = swapRoutes[step];
    bool zeroForOne = swapRoute.fromToken < swapRoute.toToken; // tokenIn < tokenOut
    uint256 amountOut = getAmountOutUniV2(swapRoute.amountIn, swapRoute.pool, zeroForOne);
    IUniswapV2Pair(swapRoute.pool).swap(
      zeroForOne ? 0 : amountOut, zeroForOne ? amountOut : 0, address(this), abi.encode(swapRoutes, step)
    );
  }

  function uniswapV2Call(address sender, uint256, uint256, bytes calldata data) external override v2Callback(sender) {
    // At this point we have received the tokens from the pool
    // We need to transfer the tokens we owe to the pool by the end of the call
    (SwapRoute[] memory swapRoutes, uint256 step) = abi.decode(data, (SwapRoute[], uint256));
    handleRoute(swapRoutes, step + 1);
    TransferLib.transferToken(IERC20(swapRoutes[step].fromToken), sender, swapRoutes[step].amountIn);
  }

  function handleRoute(SwapRoute[] memory swapRoutes, uint256 step) internal {
    if (step >= swapRoutes.length) {
      return;
    }
    if (swapRoutes[step].amountIn == 0) {
      require(step > 0, "Arbitrage: Invalid amountIn");
      // default to amount in balance
      swapRoutes[step].amountIn = IERC20(swapRoutes[step - 1].toToken).balanceOf(address(this));
    }
    if (swapRoutes[step].swapType == SwapType.UNI_V2) {
      swapOnUniswapV2(swapRoutes, step);
    } else {
      swapOnUniswapV3(swapRoutes, step);
    }
  }

  function startArbitrage(SwapRoute[] memory swapRoutes, IERC20[] calldata tokenToWithdraw) external {
    handleRoute(swapRoutes, 0);
    for (uint256 i = 0; i < tokenToWithdraw.length; i++) {
      if (IERC20(tokenToWithdraw[i]).balanceOf(address(this)) == 0) {
        continue;
      }
      TransferLib.transferToken(tokenToWithdraw[i], msg.sender, tokenToWithdraw[i].balanceOf(address(this)));
    }
  }

  function callDataEfficientArbitrage(SwapRoute[] memory swapRoutes) external {
    handleRoute(swapRoutes, 0);
    for (uint256 i = 0; i < swapRoutes.length; i++) {
      if (IERC20(swapRoutes[i].fromToken).balanceOf(address(this)) > 0) {
        TransferLib.transferToken(
          IERC20(swapRoutes[i].fromToken), msg.sender, IERC20(swapRoutes[i].fromToken).balanceOf(address(this))
        );
      }
      if (IERC20(swapRoutes[i].toToken).balanceOf(address(this)) > 0) {
        TransferLib.transferToken(
          IERC20(swapRoutes[i].toToken), msg.sender, IERC20(swapRoutes[i].toToken).balanceOf(address(this))
        );
      }
    }
  }
}
