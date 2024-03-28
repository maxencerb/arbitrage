// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UniV3Deployer, IUniswapV3Factory} from "../contracts/utils/UniV3Deployer.sol";
import {UniV2Deployer} from "../contracts/utils/UniV2Deployer.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {WETH} from "../contracts/utils/WETH.sol";
import {TestToken} from "../contracts/utils/TestToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "../contracts/vendor/uni-v3/core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "../contracts/vendor/uni-v3/core/libraries/TickMath.sol";
import {INonfungiblePositionManager} from "../contracts/vendor/uni-v3/periphery/interfaces/INonfungiblePositionManager.sol";
import {Arbitrage, TransferLib} from "../contracts/Arbitrage.sol";

contract Arbitrage_test is Test {
  WETH weth9 = new WETH();
  IERC20 dai = new TestToken("DAI", "DAI");
  IERC20 usdc = new TestToken("USDC", "USDC");
  IERC20 wbtc = new TestToken("WBTC", "WBTC");

  UniV3Deployer v3Market0 = new UniV3Deployer(weth9);
  UniV3Deployer v3Market1 = new UniV3Deployer(weth9);

  UniV2Deployer v2Market0 = new UniV2Deployer(weth9);
  UniV2Deployer v2Market1 = new UniV2Deployer(weth9);

  function setUp() public {
    v3Market0.deployUniV3();
    v3Market1.deployUniV3();

    v2Market0.deployUniV2();
    v2Market1.deployUniV2();
  }

  function LPV3(address token0, address token1, uint160 price, UniV3Deployer market) internal {
    INonfungiblePositionManager positionManager = market.positionManager();
    
    int24 tick = TickMath.getTickAtSqrtRatio(price);

    INonfungiblePositionManager.MintParams memory params;
    params.token0 = token0;
    params.token1 = token1;
    params.fee = 500;
    params.tickLower = tick-500;
    params.tickUpper = tick+500;
    params.deadline = block.timestamp + 1000;
    params.amount0Desired = 1 ether;
    params.amount1Desired = 1 ether;
    params.recipient = address(this);

    deal(address(token0), address(this), params.amount0Desired);
    deal(address(token1), address(this), params.amount1Desired);

    TransferLib.approveToken(IERC20(token0), address(positionManager), params.amount0Desired);
    TransferLib.approveToken(IERC20(token1), address(positionManager), params.amount1Desired);

    positionManager.mint(params);
  }

  function initAndLPV3AtPrice(UniV3Deployer market, address token0, address token1, uint160 price) internal {
    // get pool
    IUniswapV3Factory factory = market.v3Factory();
    address pool = factory.getPool(token0, token1, 500);
    require(pool == address(0), "Pool already exists"); 
    pool = factory.createPool(token0, token1, 500);
    // sqrtPriceX96 = sqrt(price) * 2 ** 96
    IUniswapV3Pool(pool).initialize(price);

    // mint multiple LP
  }


}
