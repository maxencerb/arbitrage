// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console2 as console} from "forge-std/Test.sol";
import {UniV2Deployer} from "../contracts/utils/UniV2Deployer.sol";
import {PoolAddress} from "../contracts/vendor/uni-v3/periphery/libraries/PoolAddress.sol";
import {IUniswapV3Pool} from "../contracts/vendor/uni-v3/core/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestToken} from "../contracts/utils/TestToken.sol";
import {TickMath} from "../contracts/vendor/uni-v3/core/libraries/TickMath.sol";
import {INonfungiblePositionManager} from
  "../contracts/vendor/uni-v3/periphery/interfaces/INonfungiblePositionManager.sol";
import {WETH} from "../contracts/utils/WETH.sol";

contract Univ2Deployer_test is Test, UniV2Deployer {
  IERC20 base;
  IERC20 quote;
  address token0;
  address token1;
  WETH weth9 = new WETH();

  constructor() UniV2Deployer(weth9) {}

  event PairCreated(address indexed token0, address indexed token1, address pair, uint);

  function setUp() public {
    deployUniV2();

    base = weth9;
    quote = new TestToken("DAI", "DAI");
    token0 = base < quote ? address(base) : address(quote);
    token1 = base < quote ? address(quote) : address(base);
  }

  function test_factory() public view {
    assertEq(v2Factory.feeToSetter(), address(this));
    assertEq(v2Factory.allPairsLength(), 0);
  }

  function test_router() public view {
    assertEq(v2Router.factory(), address(v2Factory));
    assertEq(v2Router.WETH(), address(weth9));
  }

  function test_create_pair() public {
    assertEq(v2Factory.getPair(address(base), address(quote)), address(0));
    vm.expectEmit(true, true, true, false, address(v2Factory));
    emit PairCreated(token0, token1, address(0), 1);
    v2Factory.createPair(address(base), address(quote));
    assertEq(v2Factory.allPairsLength(), 1);
  }

  function test_add_liquidity() public {
    address pair = v2Factory.createPair(address(base), address(quote));
    deal(address(base), address(this), 1 ether);
    deal(address(quote), address(this), 1 ether);
    base.approve(address(v2Router), 1 ether);
    quote.approve(address(v2Router), 1 ether);
    v2Router.addLiquidity(
      address(base),
      address(quote),
      1 ether,
      1 ether,
      0,
      0,
      address(this),
      block.timestamp + 1000
    );

    assertEq(base.balanceOf(address(this)), 0);
    assertEq(quote.balanceOf(address(this)), 0);
    assertGt(IERC20(pair).balanceOf(address(this)), 0);
  }
}
