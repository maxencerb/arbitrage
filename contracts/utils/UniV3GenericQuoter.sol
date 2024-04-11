// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// import {IUniswapV3Pool} from "../vendor/uni-v3/core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "../vendor/uni-v3/core/interfaces/callback/IUniswapV3SwapCallback.sol";
import "../vendor/uni-v3/periphery/libraries/Path.sol";
import "../vendor/uni-v3/periphery/libraries/PoolAddress.sol";
import "../vendor/uni-v3/core/libraries/TickMath.sol";
import "../vendor/uni-v3/periphery/libraries/PoolTicksCounter.sol";

contract UniV3QuoterGeneric is IUniswapV3SwapCallback {
    using Path for bytes;
    using PoolTicksCounter for IUniswapV3Pool;

    /// @dev Transient storage variable used to check a safety condition in exact output swaps.
    uint256 private amountOutCached;

    struct QuoteExactInputSingleParams {
        address factory;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    struct QuoteExactOutputSingleParams {
        address factory;
        address tokenIn;
        address tokenOut;
        uint256 amount;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    struct HeapVars {
      address factory;
      address tokenOut;
      address tokenIn;
      uint24 fee;
    }

    constructor() {}

    function getPool(
        address factory,
        address tokenA,
        address tokenB,
        uint24 fee
    ) private pure returns (IUniswapV3Pool) {
        return IUniswapV3Pool(PoolAddress.computeAddress(factory, PoolAddress.getPoolKey(tokenA, tokenB, fee)));
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory path
    ) external view override {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        (address factory, address tokenIn, address tokenOut, uint24 fee) = path.decodeFirstPool();

        // disable callback validation as it's only used in offchain pricing
        // CallbackValidation.verifyCallback(factory, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) =
            amount0Delta > 0
                ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
                : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        IUniswapV3Pool pool = getPool(factory, tokenIn, tokenOut, fee);
        (uint160 sqrtPriceX96After, int24 tickAfter, , , , , ) = pool.slot0();

        if (isExactInput) {
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amountReceived)
                mstore(add(ptr, 0x20), sqrtPriceX96After)
                mstore(add(ptr, 0x40), tickAfter)
                revert(ptr, 96)
            }
        } else {
            // if the cache has been populated, ensure that the full output amount has been received
            if (amountOutCached != 0) require(amountReceived == amountOutCached);
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amountToPay)
                mstore(add(ptr, 0x20), sqrtPriceX96After)
                mstore(add(ptr, 0x40), tickAfter)
                revert(ptr, 96)
            }
        }
    }

    /// @dev Parses a revert reason that should contain the numeric quote
    function parseRevertReason(bytes memory reason)
        private
        pure
        returns (
            uint256 amount,
            uint160 sqrtPriceX96After,
            int24 tickAfter
        )
    {
        if (reason.length != 96) {
            if (reason.length < 68) revert('Unexpected error');
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256, uint160, int24));
    }

    function handleRevert(
        bytes memory reason,
        IUniswapV3Pool pool,
        uint256 gasEstimate
    )
        private
        view
        returns (
            uint256 amount,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256
        )
    {
        int24 tickBefore;
        int24 tickAfter;
        (, tickBefore, , , , , ) = pool.slot0();
        (amount, sqrtPriceX96After, tickAfter) = parseRevertReason(reason);

        initializedTicksCrossed = pool.countInitializedTicksCrossed(tickBefore, tickAfter);

        return (amount, sqrtPriceX96After, initializedTicksCrossed, gasEstimate);
    }

    struct HeapVarsQuoteExactInputSingle {
      bool zeroForOne;
      IUniswapV3Pool pool;
      uint256 gasBefore;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        public
        returns (
            uint256 amountOut,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        )
    {

        HeapVarsQuoteExactInputSingle memory vars;

        vars.zeroForOne = params.tokenIn < params.tokenOut;
        vars.pool = getPool(params.factory, params.tokenIn, params.tokenOut, params.fee);

        uint256 gasBefore = gasleft();
        try
            vars.pool.swap(
                address(this), // address(0) might cause issues with some tokens
                vars.zeroForOne,
                int256(params.amountIn),
                params.sqrtPriceLimitX96 == 0
                    ? (vars.zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : params.sqrtPriceLimitX96,
                abi.encodePacked(params.factory, params.tokenIn, params.fee, params.tokenOut)
            )
        {} catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            return handleRevert(reason, vars.pool, gasEstimate);
        }
    }

    function quoteExactInput(bytes memory path, uint256 amountIn)
        public
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        sqrtPriceX96AfterList = new uint160[](path.numPools());
        initializedTicksCrossedList = new uint32[](path.numPools());

        uint256 i = 0;
        while (true) {

            HeapVars memory vars;
            (vars.factory, vars.tokenIn, vars.tokenOut, vars.fee) = path.decodeFirstPool();

            // the outputs of prior swaps become the inputs to subsequent ones
            (uint256 _amountOut, uint160 _sqrtPriceX96After, uint32 _initializedTicksCrossed, uint256 _gasEstimate) =
                quoteExactInputSingle(
                    QuoteExactInputSingleParams({
                        factory: vars.factory,
                        tokenIn: vars.tokenIn,
                        tokenOut: vars.tokenOut,
                        fee: vars.fee,
                        amountIn: amountIn,
                        sqrtPriceLimitX96: 0
                    })
                );

            sqrtPriceX96AfterList[i] = _sqrtPriceX96After;
            initializedTicksCrossedList[i] = _initializedTicksCrossed;
            amountIn = _amountOut;
            gasEstimate += _gasEstimate;
            i++;

            // decide whether to continue or terminate
            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                return (amountIn, sqrtPriceX96AfterList, initializedTicksCrossedList, gasEstimate);
            }
        }
    }

    struct HeapVarsQuoteExactOutputSingle {
      bool zeroForOne;
      IUniswapV3Pool pool;
      uint256 gasBefore;
    }

    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        public
        returns (
            uint256 amountIn,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        )
    {

        HeapVarsQuoteExactOutputSingle memory vars;
        vars.zeroForOne = params.tokenIn < params.tokenOut;
        vars.pool = getPool(params.factory, params.tokenIn, params.tokenOut, params.fee);

        // if no price limit has been specified, cache the output amount for comparison in the swap callback
        if (params.sqrtPriceLimitX96 == 0) amountOutCached = params.amount;
        vars.gasBefore = gasleft();
        try
            vars.pool.swap(
                address(this), // address(0) might cause issues with some tokens
                vars.zeroForOne,
                -int256(params.amount),
                params.sqrtPriceLimitX96 == 0
                    ? (vars.zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : params.sqrtPriceLimitX96,
                abi.encodePacked(params.factory, params.tokenOut, params.fee, params.tokenIn)
            )
        {} catch (bytes memory reason) {
            gasEstimate = vars.gasBefore - gasleft();
            if (params.sqrtPriceLimitX96 == 0) delete amountOutCached; // clear cache
            return handleRevert(reason, vars.pool, gasEstimate);
        }
    }



    function quoteExactOutput(bytes memory path, uint256 amountOut)
        public
        returns (
            uint256 amountIn,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        sqrtPriceX96AfterList = new uint160[](path.numPools());
        initializedTicksCrossedList = new uint32[](path.numPools());

        uint256 i = 0;

        HeapVars memory vars;
        while (true) {
            (vars.factory, vars.tokenOut, vars.tokenIn, vars.fee) = path.decodeFirstPool();

            // the inputs of prior swaps become the outputs of subsequent ones
            (uint256 _amountIn, uint160 _sqrtPriceX96After, uint32 _initializedTicksCrossed, uint256 _gasEstimate) =
                quoteExactOutputSingle(
                    QuoteExactOutputSingleParams({
                        factory: vars.factory,
                        tokenIn: vars.tokenIn,
                        tokenOut: vars.tokenOut,
                        amount: amountOut,
                        fee: vars.fee,
                        sqrtPriceLimitX96: 0
                    })
                );

            sqrtPriceX96AfterList[i] = _sqrtPriceX96After;
            initializedTicksCrossedList[i] = _initializedTicksCrossed;
            amountOut = _amountIn;
            gasEstimate += _gasEstimate;
            i++;

            // decide whether to continue or terminate
            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                return (amountOut, sqrtPriceX96AfterList, initializedTicksCrossedList, gasEstimate);
            }
        }
    }
}
