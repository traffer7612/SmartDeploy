// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract CallerContract {

    address public lotteryContract;
    event Response(bool, bytes);
    constructor (address _lotteryContract) {
        lotteryContract = _lotteryContract;
    }

    function registerToLottery(uint256 _number) external {
       (bool success, bytes memory data) = lotteryContract.call(abi.encodeWithSignature("registerUser(uint256)", _number)); 
        emit Response(success, data);
        require(success, "registration failed");
            
        }

         function paidRegisterToLottery(uint256 _number) external payable {
       (bool success, bytes memory data) = lotteryContract.call{value:msg.value}(abi.encodeWithSignature("registerUser(uint256)", _number)); 
        emit Response(success, data);
        require(success, "registration failed");
            
        }
    }

contract Lottery {

    mapping(address => uint256) public registeredUsers;
    mapping(address => uint256) public payments;

    event UserRegistered(address, uint256, uint256);
    
function registerUser(uint256 _number) external payable{
    require(registeredUsers[msg.sender] == 0, "User already registered");
    registeredUsers[msg.sender] = _number;
    payments[msg.sender] = msg.value;
    emit UserRegistered(msg.sender, _number, msg.value);
}
}