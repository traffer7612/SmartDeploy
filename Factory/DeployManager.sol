// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./IUtilityContract.sol";

contract DeployManager is Ownable { 

    event NewContractAdded(address _ContractAddress, uint256 _fee, bool _isActive, uint256 _timestamp);
    event ContractFeeUpdated(address _ContractAddress, uint256 _oldFee, uint256 _newFee, uint256 _timestamp);
    event ContractStatusUpdated(address _ContractAddress, bool _isActive, uint256 _timestamp);
    event NewDeployment(address _deployer, address _ContractAddress,  uint256 _fee, uint256 _timestamp);

    constructor() Ownable (msg.sender) {

        }

    struct ContractInfo {
        uint256 fee;
        bool isActive;
        uint256 registeredAt;

    }

    mapping(address => address[]) public deploymentContracts;
    mapping(address => ContractInfo) public contractsData;
    

    error ContractNotActive();
    error NotEnoughtFunds();
    error ContractDoesNotRegistered();
    error InitializationFailed();
     

    function deploy(address _utilityContract, bytes calldata _initData) external payable returns(address){
         ContractInfo memory info = contractsData[_utilityContract];
         require(info.isActive, ContractNotActive());
         require(msg.value >= info.fee, NotEnoughtFunds());
         require(info.registeredAt > 0, ContractDoesNotRegistered());

         address clone = Clones.clone(_utilityContract);
         require(IUtilityContract(clone).Initialize(_initData), InitializationFailed());
         payable(owner()).transfer(msg.value);
         deploymentContracts[msg.sender].push(clone);
         emit NewDeployment(msg.sender, clone, msg.value, block.timestamp);
         return clone;
    }

    function addNewContract(address _contractAddress, uint256 _fee, bool _isActive) external onlyOwner{
         contractsData[_contractAddress] = ContractInfo({
            fee: _fee,
            isActive : _isActive,
            registeredAt: block.timestamp
         });

         emit NewContractAdded(_contractAddress, _fee, _isActive, block.timestamp);
    }

    function updateFee(address _contractAddress, uint256 _newFee) external onlyOwner{
        require(contractsData[_contractAddress].registeredAt > 0, ContractDoesNotRegistered());
        require(contractsData[_contractAddress].isActive, ContractNotActive());
        uint256 _oldFee = contractsData[_contractAddress].fee;
        contractsData[_contractAddress].fee = _newFee;
        emit ContractFeeUpdated(_contractAddress, _oldFee, _newFee, block.timestamp);
    }

    function deactivateContract(address _contractAddress) external onlyOwner{
        require(contractsData[_contractAddress].registeredAt > 0, ContractDoesNotRegistered());
        contractsData[_contractAddress].isActive = false;
        emit ContractStatusUpdated(_contractAddress, false, block.timestamp);
    }

    function activateContract(address _contractAddress) external onlyOwner{
        require(contractsData[_contractAddress].registeredAt > 0, ContractDoesNotRegistered());
         contractsData[_contractAddress].isActive = true;

         emit ContractStatusUpdated(_contractAddress, true, block.timestamp);
    }

    



}