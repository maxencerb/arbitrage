// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungibleTokenPositionDescriptor} from
  "../vendor/uni-v3/periphery/interfaces/INonfungibleTokenPositionDescriptor.sol";
import {INonfungiblePositionManager} from "../vendor/uni-v3/periphery/interfaces/INonfungiblePositionManager.sol";
import {IWETH9} from "../interfaces/IWETH9.sol";
import {ContractDeployer} from "../utils/ContractDeployer.sol";
import {WETH} from "./WETH.sol";

address constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
Vm constant vm = Vm(VM_ADDRESS);

contract UniV3Deployer {
  IUniswapV3Factory public v3Factory;
  IWETH9 private weth9;
  INonfungibleTokenPositionDescriptor public tokenDescriptor;
  INonfungiblePositionManager public positionManager;

  constructor(IWETH9 _weth9) {
    weth9 = _weth9;
  }

  function deployFactory() private {
    string memory content = vm.readFile("script/uni-out/UniswapV3Factory.txt");
    bytes memory bytecode = vm.parseBytes(content);
    v3Factory = IUniswapV3Factory(ContractDeployer.deployFromBytecode(bytecode));
  }

  function deployTokenDescriptor() private {
    string memory content = vm.readFile("script/uni-out/NonfungibleTokenPositionDescriptor.txt");
    bytes memory bytecode = vm.parseBytes(content);
    bytes32 nativeCurrencyLabel = "ETH";
    bytes memory args = abi.encode(address(weth9), nativeCurrencyLabel);
    tokenDescriptor = INonfungibleTokenPositionDescriptor(ContractDeployer.deployBytecodeWithArgs(bytecode, args));
  }

  function deployPositionManager() private {
    string memory content = vm.readFile("script/uni-out/NonfungiblePositionManager.txt");
    bytes memory bytecode = vm.parseBytes(content);
    bytes memory args = abi.encode(address(v3Factory), address(weth9), address(tokenDescriptor));
    positionManager = INonfungiblePositionManager(ContractDeployer.deployBytecodeWithArgs(bytecode, args));
  }

  function deployUniV3() public {
    deployFactory();
    deployTokenDescriptor();
    deployPositionManager();
  }
}
