// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console2 as console} from "forge-std/Test.sol";
import {Univ3Deployer} from "../contracts/utils/UniV3Deployer.sol";
import {PoolAddress} from "../contracts/vendor/uni-v3/periphery/libraries/PoolAddress.sol";
import {IUniswapV3Pool} from "../contracts/vendor/uni-v3/core/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestToken} from "../contracts/utils/TestToken.sol";
import {TickMath} from "../contracts/vendor/uni-v3/core/libraries/TickMath.sol";
import {INonfungiblePositionManager} from "../contracts/vendor/uni-v3/periphery/interfaces/INonfungiblePositionManager.sol";

contract Univ3Deployer_test is Test, Univ3Deployer {

  IERC20 base;
  IERC20 quote;

  event PoolCreated(
    address indexed token0, address indexed token1, uint24 indexed fee, int24 tickSpacing, address pool
  );

  function _getPoolKey(address token0, address token1, uint24 fee)
    internal
    pure
    returns (PoolAddress.PoolKey memory poolKey)
  {
    poolKey = PoolAddress.getPoolKey(token0, token1, fee);
  }

  function _getPool(PoolAddress.PoolKey memory poolKey) internal view returns (IUniswapV3Pool pool) {
    return IUniswapV3Pool(PoolAddress.computeAddress(address(factory), poolKey));
  }

  function setUp() public {
    deployUniv3();

    base = weth9;
    quote = new TestToken("DAI", "DAI");
  }

  function test_position_manager() public {
    assertEq(positionManager.name(), "Uniswap V3 Positions NFT-V1");
    assertEq(positionManager.symbol(), "UNI-V3-POS");
    assertEq(positionManager.factory(), address(factory));
    assertEq(positionManager.totalSupply(), 0);
  }

  function test_factory() public {
    assertEq(factory.owner(), address(this));
    assertEq(factory.feeAmountTickSpacing(500), 10);
    assertEq(factory.feeAmountTickSpacing(3000), 60);
    assertEq(factory.feeAmountTickSpacing(10000), 200);
  }

  function test_create_pool() public {
    address token0 = base < quote ? address(base) : address(quote);
    address token1 = base < quote ? address(quote) : address(base);
    IUniswapV3Pool exepextedPool = _getPool(PoolAddress.getPoolKey(address(base), address(quote), 500));
    vm.expectEmit();
    emit PoolCreated(token0, token1, 500, 10, address(exepextedPool));
    address pool = factory.createPool(address(base), address(quote), 500);
    assertEq(pool, factory.getPool(address(base), address(quote), 500));
    assertEq(pool, address(exepextedPool));

    exepextedPool.initialize(TickMath.getSqrtRatioAtTick(0));

    assertEq(exepextedPool.token0(), token0);
    assertEq(exepextedPool.token1(), token1);
    assertEq(exepextedPool.fee(), 500);
    assertEq(exepextedPool.tickSpacing(), 10);
    (,,,,,, bool unlocked) = exepextedPool.slot0();
    assertTrue(unlocked);
  }

  function test_addLiquidity() public {
    address pool = factory.createPool(address(base), address(quote), 500);
    IUniswapV3Pool(pool).initialize(TickMath.getSqrtRatioAtTick(0));

    INonfungiblePositionManager.MintParams memory params;
    params.token0 = base < quote ? address(base) : address(quote);
    params.token1 = base < quote ? address(quote) : address(base);
    params.fee = 500;
    params.tickLower = -500;
    params.tickUpper = 500;
    params.deadline = block.timestamp + 1000;
    params.amount0Desired = 1000;
    params.amount1Desired = 1000;
    params.recipient = address(this);

    deal(address(base), address(this), params.amount0Desired);
    deal(address(quote), address(this), params.amount1Desired);

    base.approve(address(positionManager), params.amount0Desired);
    quote.approve(address(positionManager), params.amount1Desired);

    positionManager.mint(params);

    assertEq(positionManager.balanceOf(address(this)), 1);
  }
}