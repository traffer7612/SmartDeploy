// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SecureTreasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Custom Errors ============
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientETHBalance(uint256 requested, uint256 available);
    error InsufficientTokenBalance(address token, uint256 requested, uint256 available);
    error ETHTransferFailed();

    // ============ Events ============
    event ETHDeposited(address indexed from, uint256 amount);
    event TokenDeposited(address indexed token, address indexed from, uint256 amount);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);

    // ============ Constructor ============
    constructor(address initialOwner) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
    }

    // ============ Receive & Fallback ============
    receive() external payable {
        emit ETHDeposited(msg.sender, msg.value);
    }

    fallback() external payable {
        emit ETHDeposited(msg.sender, msg.value);
    }

    // ============ Deposit Functions ============
    function depositETH() external payable {
        if (msg.value == 0) revert ZeroAmount();
        emit ETHDeposited(msg.sender, msg.value);
    }

    function depositToken(address token, uint256 amount) external {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit TokenDeposited(token, msg.sender, amount);
    }

    // ============ Withdraw Functions (Owner Only) ============
    function withdrawETH(address payable to, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 balance = address(this).balance;
        if (amount > balance) {
            revert InsufficientETHBalance(amount, balance);
        }

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        emit ETHWithdrawn(to, amount);
    }

    function withdrawAllETH(address payable to)
        external
        onlyOwner
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();

        uint256 balance = address(this).balance;
        if (balance == 0) revert ZeroAmount();

        (bool success, ) = to.call{value: balance}("");
        if (!success) revert ETHTransferFailed();

        emit ETHWithdrawn(to, balance);
    }

    function withdrawToken(address token, address to, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        if (token == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (amount > balance) {
            revert InsufficientTokenBalance(token, amount, balance);
        }

        IERC20(token).safeTransfer(to, amount);
        emit TokenWithdrawn(token, to, amount);
    }

    function withdrawAllTokens(address token, address to)
        external
        onlyOwner
        nonReentrant
    {
        if (token == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert ZeroAmount();

        IERC20(token).safeTransfer(to, balance);
        emit TokenWithdrawn(token, to, balance);
    }

    // ============ View Functions ============
    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getTokenBalance(address token) external view returns (uint256) {
        if (token == address(0)) revert ZeroAddress();
        return IERC20(token).balanceOf(address(this));
    }
}