// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interface/IMaxityNGO.sol";

contract MaxitNGO is  Ownable,IMaxityNGO {

    
    address public token;
    address public wallet;

    string public name;
    string public email="aaa@aaa.com";
    string public org="org.test";
    string public orgNumber="orgNumber.test";
    string public contactAddress="contactAddress.test";
    string public phone="phone.test";
    string public website="website.test";
    string public ambassador="ambassador.test";
    string public category="orcategoryg.test";
    string public docs="docs.test";
    string public purpose="purpose.test";

    constructor(string memory _name,address _wallet) {
        name = _name;
        wallet = _wallet;
    }


}
