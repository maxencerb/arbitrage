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

contract Univ3Deployer {
  IUniswapV3Factory public factory;
  IWETH9 public weth9;
  INonfungibleTokenPositionDescriptor public tokenDescriptor;
  INonfungiblePositionManager public positionManager;

  function deployFactory() private {
    string memory content = vm.readFile("script/uni-out/UniswapV3Factory.txt");
    bytes memory bytecode = vm.parseBytes(content);
    factory = IUniswapV3Factory(ContractDeployer.deployFromBytecode(bytecode));
  }

  function deployeWETH9() private {
    weth9 = new WETH();
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
    bytes memory args = abi.encode(address(factory), address(weth9), address(tokenDescriptor));
    positionManager = INonfungiblePositionManager(ContractDeployer.deployBytecodeWithArgs(bytecode, args));
  }

  function deployUniv3() public {
    deployFactory();
    deployeWETH9();
    deployTokenDescriptor();
    deployPositionManager();
  }
}
