// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MaxityToken is ERC20, Ownable {

    using SafeMath for uint256;

    
    uint256 private constant preMineSupply = 20000000 * 1e18; 
    uint256 private constant maxSupply =    100000000 * 1e18;     // the total supply

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _minters;

    mapping(address => uint256)  minterMaxSupply;
    mapping(address => uint256)  minterAlreadyMint;


    constructor(string memory name,string memory symbol) public ERC20(name, symbol){
        _mint(msg.sender, preMineSupply);
    }


    // mint with max supply
    function mint(address _to, uint256 _amount) external onlyMinter  returns (bool) {
        require (_amount.add(totalSupply()) <= maxSupply) ;
        if(minterMaxSupply[msg.sender]>0){
            require(_amount.add(minterAlreadyMint[msg.sender])<=minterMaxSupply[msg.sender],'minter max limit');
            minterAlreadyMint[msg.sender] = minterAlreadyMint[msg.sender].add(_amount);
        }
        
        _mint(_to, _amount);
        return true;
    }

    function addMinter(address _addMinter,uint256 _maxMint) public onlyOwner returns (bool) {
        require(_addMinter != address(0), "_addMinter is the zero address");
        // if(_maxMint>0){
        minterMaxSupply [_addMinter] = _maxMint;
        // }
        return EnumerableSet.add(_minters, _addMinter);
    }


    function delMinter(address _delMinter) public onlyOwner returns (bool) {
        require(_delMinter != address(0), "_delMinter is the zero address");
        return EnumerableSet.remove(_minters, _delMinter);
    }

    function getMinterLength() public view returns (uint256) {
        return EnumerableSet.length(_minters);
    }

    function isMinter(address account) public view returns (bool) {
        return EnumerableSet.contains(_minters, account);
    }

    function getMinter(uint256 _index) public view onlyOwner returns (address){
        require(_index <= getMinterLength() - 1, "Index out of bounds");
        return EnumerableSet.at(_minters, _index);
    }

    // modifier for mint function
    modifier onlyMinter() {
        require(isMinter(msg.sender), "Caller is not the minter");
        _;
    }

}
