// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

//0x5B38Da6a701c568545dCfcB03FcB875f56beddC4
//0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2
//0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db

//0xcc0e0440d2784bb1fb6dc059fd3371abc91bde89fe88dd1c8504e83b8f7ecf23 merkle
//0xdD870fA1b7C4700F2BD7f44238821C26f7392148 treasury



contract ERC20Claimer {
    
    IERC20 public token;
    bytes32 public merkleRoot;
    address public treasury;

    mapping(address => bool) public hasClaimed;

    event TokenClaimed(address claimer, uint256 amount, uint256 timestamp);
    error AlreadyClaimed();
    error InvalidProof();
    error TransferFailed();

    constructor(address _tokenAddress, bytes32 _merkleRoot, address _treasury) {
        token = IERC20(_tokenAddress);
        merkleRoot = _merkleRoot;
        treasury = _treasury;
    }

    function claim(uint256 _amount, bytes32[] calldata _proof) external {
        require(!hasClaimed[msg.sender], AlreadyClaimed());

        bytes32 leaf = keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(msg.sender, _amount)
                )
            )
        );

        bool valid = MerkleProof.verify(_proof, merkleRoot, leaf);

        require(valid, InvalidProof());

        hasClaimed[msg.sender] = true;

        require(token.transferFrom(treasury, msg.sender, _amount), TransferFailed());
        emit TokenClaimed(msg.sender, _amount, block.timestamp);
    }

    //Внедрить totalClaimed
    //Верификация без клейма canClaim() view
    //Добавить возможность установить временные рамки клейма
    //Добавить функцию recoverUnclaimed, чтобы склеймить все оставшиеся средства на аккаунт овнера
}

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MyToken is ERC20, ERC20Permit {
    constructor(address recipient)
        ERC20("MyToken", "MTK")
        ERC20Permit("MyToken")
    {
        _mint(recipient, 10000 * 10 ** decimals());
    }
}