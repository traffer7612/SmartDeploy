// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract Proxy {
    uint256 public number;
    address public admin;
    address public implementation;
    

    constructor (address _logic) {
         admin = msg.sender;
         implementation = _logic;

    } 

    function updateLogic(address _newLogic) public {
        require(msg.sender == admin, "Not admin");
        implementation = _newLogic;
    }

    function getSelector(string calldata _func) public pure returns (bytes4) {
        return bytes4(keccak256(bytes(_func)));
    }

    fallback() external {
        require(msg.sender != admin, "Admin cannot delegated");
        (bool success, ) = implementation.delegatecall(msg.data);
        require(success, "DelegateCall failed");
    }
}

contract ImplementationV1 {
    uint256 public number;

    function increment() public {
        number += 1;
    }

    function double() public {
        number *= 2;
    }

     

}

