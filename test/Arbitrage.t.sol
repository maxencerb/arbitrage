// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UniV3Deployer, IUniswapV3Factory} from "../contracts/utils/UniV3Deployer.sol";
import {UniV2Deployer, IUniswapV2Factory} from "../contracts/utils/UniV2Deployer.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {WETH} from "../contracts/utils/WETH.sol";
import {TestToken} from "../contracts/utils/TestToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "../contracts/vendor/uni-v3/core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "../contracts/vendor/uni-v3/core/libraries/TickMath.sol";
import {INonfungiblePositionManager} from
  "../contracts/vendor/uni-v3/periphery/interfaces/INonfungiblePositionManager.sol";
import {Arbitrage, TransferLib, SwapType} from "../contracts/Arbitrage.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract Arbitrage_test is Test {
  WETH weth9 = new WETH();
  IERC20 dai = new TestToken("DAI", "DAI");
  IERC20 usdc = new TestToken("USDC", "USDC");
  IERC20 wbtc = new TestToken("WBTC", "WBTC");

  UniV3Deployer v3Market0 = new UniV3Deployer(weth9);
  UniV3Deployer v3Market1 = new UniV3Deployer(weth9);

  UniV2Deployer v2Market0 = new UniV2Deployer(weth9);
  UniV2Deployer v2Market1 = new UniV2Deployer(weth9);
  Arbitrage arb;

  function setUp() public {
    v3Market0.deployUniV3();
    v3Market1.deployUniV3();

    v2Market0.deployUniV2();
    v2Market1.deployUniV2();

    arb = new Arbitrage();
  }

  function LPV3(
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    uint160 price,
    int24 difflower,
    int24 diffUpper,
    UniV3Deployer market
  ) internal {
    INonfungiblePositionManager positionManager = market.positionManager();

    int24 tick = TickMath.getTickAtSqrtRatio(price);

    INonfungiblePositionManager.MintParams memory params;
    params.token0 = token0;
    params.token1 = token1;
    params.fee = 500;
    params.tickLower = tick + difflower;
    params.tickUpper = tick + diffUpper;
    params.deadline = block.timestamp + 1000;
    params.amount0Desired = amount0;
    params.amount1Desired = amount1;
    params.recipient = address(this);

    deal(address(token0), address(this), params.amount0Desired);
    deal(address(token1), address(this), params.amount1Desired);

    TransferLib.approveToken(IERC20(token0), address(positionManager), params.amount0Desired);
    TransferLib.approveToken(IERC20(token1), address(positionManager), params.amount1Desired);

    positionManager.mint(params);
  }

  function sqrt(uint256 x) internal pure returns (uint256 y) {
    uint256 z = (x + 1) / 2;
    y = x;
    while (z < y) {
      y = z;
      z = (x / z + z) / 2;
    }
  }

  function initAndLPV3AtPrice(UniV3Deployer market, address token0, address token1, uint256 amount0, uint256 amount1)
    internal
  {
    require(token0 < token1, "token0 must be less than token1");
    // get pool
    IUniswapV3Factory factory = market.v3Factory();
    address pool = factory.getPool(token0, token1, 500);
    require(pool == address(0), "Pool already exists");
    pool = factory.createPool(token0, token1, 500);
    // sqrtPriceX96 = sqrt(price) * 2 ** 96
    // price = amount1/amount0
    console.log(amount1 * 2 ** 96 / amount0);
    uint160 price = uint160(sqrt(amount1 * 2 ** 96 / amount0));

    IUniswapV3Pool(pool).initialize(price);

    // mint multiple LP
    LPV3(token0, token1, amount0, amount1, price, -500, 500, market);
    LPV3(token0, token1, amount0, amount1, price, -500, 500, market);
    LPV3(token0, token1, amount0, amount1, price, -1000, 1000, market);
    LPV3(token0, token1, amount0, amount1, price, -400, 2000, market);
    LPV3(token0, token1, amount0, amount1, price, -2000, 4000, market);
  }

  function LPV2(address token0, address token1, uint256 amount0, uint256 amount1, UniV2Deployer market) internal {
    deal(token0, address(this), amount0);
    deal(token1, address(this), amount1);

    TransferLib.approveToken(IERC20(token0), address(market.v2Router()), amount0);
    TransferLib.approveToken(IERC20(token1), address(market.v2Router()), amount1);

    market.v2Router().addLiquidity(token0, token1, amount0, amount1, 0, 0, address(this), block.timestamp + 1000);
  }

  function initAndLPV2AtPrice(UniV2Deployer market, address token0, address token1, uint256 amount0, uint256 amount1)
    internal
  {
    require(token0 < token1, "token0 must be less than token1");
    market.v2Factory().createPair(token0, token1);
    LPV2(token0, token1, amount0, amount1, market);
  }

  function prepareArb2TokensV2V2(address token0, address token1)
    internal
    view
    returns (Arbitrage.ArbMulticallData[] memory params)
  {
    address pair0 = v2Market0.v2Factory().getPair(token0, token1);
    address pair1 = v2Market1.v2Factory().getPair(token0, token1);
    SwapType swapType = SwapType.UNI_V2;

    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = IERC20(token0);
    tokens[1] = IERC20(token1);

    params = new Arbitrage.ArbMulticallData[](4);

    params[0].swapRoutes = new Arbitrage.SwapRoute[](2);
    params[0].swapRoutes[0] = Arbitrage.SwapRoute(token0, token1, 10, pair0, swapType);
    params[0].swapRoutes[1] = Arbitrage.SwapRoute(token1, token0, 10, pair1, swapType);

    params[0].tokenToWithdraw = tokens;

    params[1].swapRoutes = new Arbitrage.SwapRoute[](2);
    params[1].swapRoutes[0] = Arbitrage.SwapRoute(token0, token1, 10, pair1, swapType);
    params[1].swapRoutes[1] = Arbitrage.SwapRoute(token1, token0, 10, pair0, swapType);

    params[1].tokenToWithdraw = tokens;

    params[2].swapRoutes = new Arbitrage.SwapRoute[](2);
    params[2].swapRoutes[0] = Arbitrage.SwapRoute(token1, token0, 10, pair0, swapType);
    params[2].swapRoutes[1] = Arbitrage.SwapRoute(token0, token1, 10, pair1, swapType);

    params[2].tokenToWithdraw = tokens;

    params[3].swapRoutes = new Arbitrage.SwapRoute[](2);
    params[3].swapRoutes[0] = Arbitrage.SwapRoute(token1, token0, 10, pair1, swapType);
    params[3].swapRoutes[1] = Arbitrage.SwapRoute(token0, token1, 10, pair0, swapType);

    params[3].tokenToWithdraw = tokens;
  }

  function marketAtAmounts(uint16 _amount00, uint16 _amount01, uint16 _amount10, uint16 _amount11)
    internal
    returns (uint256 amount00, uint256 amount01, uint256 amount10, uint256 amount11, address token0, address token1)
  {
    vm.assume(_amount00 > 0 && _amount01 > 0 && _amount10 > 0 && _amount11 > 0);
    amount00 = uint256(_amount00) * 10 ** 18;
    amount01 = uint256(_amount01) * 10 ** 18;
    amount10 = uint256(_amount10) * 10 ** 18;
    amount11 = uint256(_amount11) * 10 ** 18;

    token0 = weth9 < dai ? address(weth9) : address(dai);
    token1 = weth9 < dai ? address(dai) : address(weth9);

    initAndLPV3AtPrice(v3Market0, token0, token1, amount00, amount01);
    initAndLPV3AtPrice(v3Market1, token0, token1, amount10, amount11);
    initAndLPV2AtPrice(v2Market0, token0, token1, amount00, amount01);
    initAndLPV2AtPrice(v2Market1, token0, token1, amount10, amount11);
  }

  function testFuzz_arb(uint16 _amount00, uint16 _amount01, uint16 _amount10, uint16 _amount11) public {
    (,,,, address token0, address token1) = marketAtAmounts(_amount00, _amount01, _amount10, _amount11);
    arb.multicallArbCall(prepareArb2TokensV2V2(token0, token1));
  }
}
