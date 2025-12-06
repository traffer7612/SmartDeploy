// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

contract WalletLogicA {
    address public owner;
    address public logicContract; // Добавить для совпадения storage layout

    function initialize(address _owner) external {
        require(owner == address(0), "Already initialized");
        owner = _owner;
    }

    function sendEther(address payable _to, uint256 _amount) external {
        require(msg.sender == owner, "Only owner can transfer");
        require(address(this).balance >= _amount, "Insufficient balance");
        _to.transfer(_amount);
    }
}

contract Wallet {
    address public owner;
    address public logicContract;

    constructor(address _logicContract) {
        require(_logicContract != address(0), "Invalid logic contract");
        logicContract = _logicContract;
        
        (bool success, ) = logicContract.delegatecall(
            abi.encodeWithSignature("initialize(address)", msg.sender)
        );
        require(success, "Initialization failed");
        
        owner = msg.sender; // Явно устанавливаем владельца
    }

    // ИСПРАВЛЕНО: Добавлена проверка владельца
    function setLogicContract(address _logicContract) external {
        require(msg.sender == owner, "Only owner");
        require(_logicContract != address(0), "Invalid address");
        logicContract = _logicContract;
    }

    // ИСПРАВЛЕНО: Переименована функция и добавлены проверки
    function sendEth(address payable _to, uint256 _amount) external {
        require(msg.sender == owner, "Only owner");
        
        (bool success, ) = logicContract.delegatecall(
            abi.encodeWithSignature("sendEther(address,uint256)", _to, _amount)
        );
        require(success, "Send ether failed");
    }

    function deposit() external payable {}
    
    receive() external payable {}
}