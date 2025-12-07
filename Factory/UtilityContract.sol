// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "./IUtilityContract.sol";

contract BigBoss is IUtilityContract {

    error AlreadyInitialized();

    modifier notInitialized(){
        require(!initialized, AlreadyInitialized());
        _;
    }

    uint256 public number;
    uint256 public constant MAX_NUMBER = 100;
    address public bigBoss;

    bool private initialized;

    function Initialize(bytes memory _initData) external notInitialized returns(bool) {
            
            (uint256 _number, address _bigBoss) = abi.decode(_initData, (uint256, address));
            initialized = true;
            number = _number;
            bigBoss = _bigBoss;
            return true;
        }

    function getInitData(uint256 _number, address _bigBoss ) external pure returns(bytes memory){
            return abi.encode(_number, _bigBoss);
    }

    function doSmth () external view returns(uint256, address){
            return (number, bigBoss);
    }
    
    


}