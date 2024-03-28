// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IWETH9} from "../interfaces/IWETH9.sol";

contract WETH is ERC20, IWETH9 {
  constructor() ERC20("Wrapped Ether", "WETH") {}

  function deposit() external payable override {
    _mint(msg.sender, msg.value);
  }

  function withdraw(uint256 amount) external override {
    require(balanceOf(msg.sender) >= amount, "WETH: insufficient balance");
    _burn(msg.sender, amount);
    payable(msg.sender).transfer(amount);
  }
}
