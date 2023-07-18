// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "../../libraries/TransferHelper.sol";
import "../interface/IMaxityMetadata.sol";
import "../interface/IMaxity721Token.sol";

contract Maxity721Token is Ownable,Pausable ,ERC721Enumerable,IMaxityMetadata,IMaxity721Token{

    using SafeMath for uint256;
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    using Strings for uint256;

    // Optional mapping for token URIs

    event TokenMint(uint256 indexed tokenid,address indexed designer, address indexed to,string uri);


    event TokenBurn(uint256 indexed tokenid);

    address public ngo;
    string public did;
    address public ngowallet;
    address public gasToken;
    uint    public gasFee;

    address    public gasCollector;

    mapping(uint=>uint) public futureRoyalty;
    EnumerableSet.AddressSet private _freeGasList;

    mapping(uint256 => string) private _tokenURIs;


    constructor(string memory name,string memory symbol,address _ngo,address _ngowallet,string memory _did) ERC721(name, symbol) {
        ngo = _ngo;
        ngowallet = _ngowallet;
        did=_did;

    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, IERC165) returns (bool) {
        return interfaceId == 0x6fd73a1d ||
            interfaceId == 0x80ac58cd ||
            interfaceId == 0x5b5e139f ||
            super.supportsInterface(interfaceId);
    }

    function setNgo(address _ngo) public onlyOwner{
        ngo = _ngo;
    }

    function setGasConfig(address _gasToken,uint _gasFee) public onlyOwner{
        gasToken = _gasToken;
        gasFee = _gasFee;
    }
    
    function setNgoWallet(address _ngowallet) public onlyOwner{
        ngowallet = _ngowallet;
    }

    function setFutureRoyalty(uint256 _tokenid,uint _futureRoyalty) public onlyOwner{
        futureRoyalty[_tokenid] = _futureRoyalty;
    }

    using EnumerableSet for EnumerableSet.AddressSet;
 
    EnumerableSet.AddressSet private _whitelists;

    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;


    uint public mintMax = 100 ;


    // mapping(uint256 => address) _disigners;
    EnumerableMap.UintToAddressMap private _disigners;

    function setMintMax(uint256 newMintMax) public onlyOwner {
        mintMax = newMintMax;
    }


    function mint(address designer,address to,uint [] memory _futureRoyaltys,string [] memory uris) external override onlyWhiteList whenNotPaused returns (uint256[] memory tokenids)  {
                
        uint count = _futureRoyaltys.length;
        require(count < mintMax, "Maximum allowed mints for tx exceeded");
        require(count > 0, "MintCount cannot be zero");
        require(count==uris.length,"Length not equal");

        uint256 []memory new_tokenids = new uint256 [](count) ;
        for(uint256 i; i < count; i++) {
            _tokenIdCounter.increment();
            uint256 newItemId = _tokenIdCounter.current();
            _mint(to, newItemId);
            _setTokenURI(newItemId, uris[i]);
            _disigners.set(newItemId, designer);
            new_tokenids[i]=newItemId;
            futureRoyalty[newItemId] = _futureRoyaltys[i];
            emit TokenMint(newItemId,designer,to,uris[i]);
        }
        return new_tokenids;
    }

/**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721URIStorage: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.tokenURI(tokenId);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721URIStorage: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    function disigner(uint256 _tokenid) external view returns (address)
    {
        return _disigners.get(_tokenid,"Token not found");
    }

    function _beforeBurn(uint256 tokenId) internal virtual {
        
    }

    function burn(uint256 tokenId) public onlyWhiteList whenNotPaused {
        _beforeBurn(tokenId);
        super._burn(tokenId);
        _disigners.remove(tokenId);
        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }
        emit TokenBurn(tokenId);
    }

    function pause() public onlyOwner {
       super. _pause();
    }

    function unpause() public onlyOwner {
       super._unpause();
    }

    function _beforeTokenTransfer(address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize)
        internal
        whenNotPaused
        override
    {
        if(!_freeGasList.contains(msg.sender) && gasFee>0&&gasToken!=address(0x0)){
            TransferHelper.safeTransferFrom(gasToken, from, gasCollector, gasFee);
        }
        
        super._beforeTokenTransfer(from, to, firstTokenId,batchSize);
    }
     
    function addWhiteList(address _addWhitelist) public onlyOwner returns (bool) {
        require(_addWhitelist != address(0), "_addMinter is zero address");
        return EnumerableSet.add(_whitelists, _addWhitelist);
    }
    function delWhiteList(address _delWhiteList) public onlyOwner returns (bool) {
        require(_delWhiteList != address(0), "_delMinter is zero address");
        return EnumerableSet.remove(_whitelists, _delWhiteList);
    }
    function getWhiteListLength() public view returns (uint256) {
        return EnumerableSet.length(_whitelists);
    }
    function inWhiteList(address account) public override view returns (bool) {
        return EnumerableSet.contains(_whitelists, account);
    }
    function getWhiteList(uint256 _index) public view onlyOwner returns (address){
        return EnumerableSet.at(_whitelists, _index);
    }


    function addFreeGasList(address _addWho) public onlyOwner returns (bool) {
        require(_addWho != address(0), "_addMinter is zero address");
        return EnumerableSet.add(_freeGasList, _addWho);
    }
    function delFreeGasList(address _delWho) public onlyOwner returns (bool) {
        require(_delWho != address(0), "_delMinter is zero address");
        return EnumerableSet.remove(_freeGasList, _delWho);
    }
    function getFreeGasLength() public view returns (uint256) {
        return EnumerableSet.length(_freeGasList);
    }
    function inFreeGasList(address account) public  view returns (bool) {
        return EnumerableSet.contains(_freeGasList, account);
    }
    function getFreeGas(uint256 _index) public view onlyOwner returns (address){
        return EnumerableSet.at(_freeGasList, _index);
    }

        // modifier for mint function
    modifier onlyWhiteList() {
        require(inWhiteList(msg.sender), "Caller is not whitelisted");
        _;
    }

    function emergencyWithdraw(address _token) public onlyOwner {
        require(IERC20(_token).balanceOf(address(this)) > 0, "Insufficient contract balance");
        IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this)));
    }

      // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyNative(uint256 amount) public onlyOwner {
        TransferHelper.safeTransferNative(msg.sender,amount)  ;
    }
}
