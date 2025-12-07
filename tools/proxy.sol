// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
//["0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2","0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db","0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB"]
    //[30000000000000000000000,40000000000000000000000,30000000000000000000000]

/**
 * @title SimpleWallet
 * @dev Базовый контракт-кошелек, который будет клонироваться
 */
contract SimpleWallet is Ownable, ReentrancyGuard {
    // События
    constructor() Ownable (msg.sender) {}
    event Deposit(address indexed sender, uint256 amount);
    event Withdrawal(address indexed recipient, uint256 amount);
    event Initialized(address indexed owner);

    // Состояние
    bool private _initialized;
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;

    /**
     * @dev Инициализация вместо конструктора (для клонов)
     */
    function initialize(address owner_) external {
        require(!_initialized, "Already initialized");
        require(owner_ != address(0), "Invalid owner");
        
        _initialized = true;
        _transferOwnership(owner_);
        
        emit Initialized(owner_);
    }

    /**
     * @dev Получение средств
     */
    receive() external payable {
        totalDeposited += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Вывод средств (только владелец)
     */
    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "Insufficient balance");
        
        totalWithdrawn += amount;
        
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Withdrawal(owner(), amount);
    }

    /**
     * @dev Получение баланса
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Проверка инициализации
     */
    function isInitialized() external view returns (bool) {
        return _initialized;
    }
}