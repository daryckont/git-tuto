// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract MagicToken is ERC20 {

   string public _name = "MagicToken";
   string public _symbol = "MGCT";
   uint256 public _totalSupply = 10000;
   uint256 public _decimals = 18; 
   address public owner;

modifier onlyOwner {
    require(msg.sender == owner, "MagicToken: you are not the owner");
    _;
  }

   constructor() ERC20(_name, _symbol){
       uint256 initialSupply = _totalSupply * 10 ** 18;
        owner = msg.sender;
       _mint(msg.sender, initialSupply);
   }
  
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address currentOwner = _msgSender();
        _transfer(currentOwner, to, amount);

        console.log(
        "Transferring from %s to %s %s tokens",
        msg.sender,
        to,
        amount
    );
        return true;
    }  

    function mint(address _recipient, uint256 _amount) external onlyOwner{
         _mint(_recipient, _amount);
    } 

}