//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "tools/ERC20Airdropper.sol";

contract ERC20AirdroperDeployer is Ownable {

    uint256 public deployFee;

    mapping(address => address[]) public deployedContracts;
    
    

    event Deployed(address deployer, address erc20Airdroper, uint256 fees, address _tokenAddress, uint256 _airdropAmount, uint256 timestamp);
    event FeeUpdated(uint256 newFee);

    constructor(uint256 _deployFee) Ownable(msg.sender) {
        deployFee = _deployFee;
    }


    function setDeployFee(uint256 _fee) external onlyOwner {
        deployFee = _fee;

        emit FeeUpdated(_fee);
    }

    function deployErc20Airdroper(address _tokenAddress, uint256 _airdropAmount) external payable returns(address) {
        require(msg.value >= deployFee, "insufficent funds");
        require(_tokenAddress != address(0), "cant be address zero");

        ERC20Airdroper airdroper = new ERC20Airdroper(_tokenAddress, _airdropAmount);

        _safeTransfer(owner(), msg.value);

        deployedContracts[msg.sender].push(address(airdroper));

        emit Deployed(msg.sender, address (airdroper), msg.value, _tokenAddress, _airdropAmount, block.timestamp);

        return address(airdroper);
    }

    function _safeTransfer(address _to, uint256 _amount) internal {
        (bool success, ) = payable(_to).call{value: _amount}("");
        require(success, "transfer error");
    }

    function getContractsDeployedByUser(address _deployer) external view returns(address[] memory) {
        return deployedContracts[_deployer];
    }

}