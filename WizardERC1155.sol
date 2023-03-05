// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "hardhat/console.sol";

contract WizardERC1155 is ERC1155 {

    uint public constant Jade = 0;
    uint public constant Ruby = 1;
    uint public constant RoyalNecklace = 2;
    uint public initialSupply = 10000;

    address public owner;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this method!");
        _;
    }

    constructor() ERC1155("") {
        owner = msg.sender; 
        _mint(msg.sender, RoyalNecklace, initialSupply, "");  
                    
    }
  
   function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _safeTransferFrom(from, to, id, amount, data);
        
       console.log(
        "Transferring from %s to %s %s tokens",
        from,
        to, 
        amount                
    );
    }

    function mintTokens(address to, uint256 id, uint256 amount, bytes calldata data) external onlyOwner {
        data;
        _mint(to, id, amount, "");
    }
}