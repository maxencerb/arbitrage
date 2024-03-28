// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Test.sol";
import {IWETH9} from "../interfaces/IWETH9.sol";
import {ContractDeployer} from "../utils/ContractDeployer.sol";
import {WETH} from "./WETH.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

address constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
Vm constant vm = Vm(VM_ADDRESS);

contract UniV2Deployer {
  IWETH9 private weth9;
  IUniswapV2Factory public v2Factory;
  IUniswapV2Router02 public v2Router;

  constructor(IWETH9 _weth9) {
    weth9 = _weth9;
  }

  function deployV2Factory() private {
    string memory content = vm.readFile("script/uni-out/UniswapV2Factory.txt");
    bytes memory bytecode = vm.parseBytes(content);
    v2Factory = IUniswapV2Factory(ContractDeployer.deployBytecodeWithArgs(bytecode, abi.encode(address(this))));
  }

  function deployRouter() private {
    string memory content = vm.readFile("script/uni-out/UniswapV2Router02.txt");
    bytes memory bytecode = vm.parseBytes(content);
    v2Router = IUniswapV2Router02(ContractDeployer.deployBytecodeWithArgs(bytecode, abi.encode(address(v2Factory), address(weth9))));
  }

  function deployUniV2() public {
    deployV2Factory();
    deployRouter();
  }
}