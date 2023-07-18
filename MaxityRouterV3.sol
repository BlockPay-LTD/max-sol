// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import './interface/IMintableToken.sol';
import './interface/ILPToken.sol';
import '../libraries/TransferHelper.sol';
import './interface/IGame.sol';
import './interface/IMPool.sol';
import './interface/IMBackup.sol';
import './impl/UTToken.sol';
import './impl/ReferencesStore.sol';
import './interface/IMasterChef.sol';
import './interface/IMRouter.sol';
import './interface/ILender.sol';
import './interface/IMaxity721Token.sol';
import './interface/IMaxityMarketPlaceV3.sol';
import './interface/IWMATIC.sol';

contract MaxityRouterV3 is Ownable,IMRouter,ReentrancyGuard{
    using SafeMath for uint256;
    address public market;
    address public wrappedNative;
    
    constructor(address _wrappedNative, address _market) {
        wrappedNative = _wrappedNative;
        market = _market;
    }

    function setWrappedNative (address _wrappedNative) public onlyOwner{
        wrappedNative = _wrappedNative;
    }

    function setMarket(address _market) public onlyOwner{
        market = _market;
    }

    //mint721
    function mintMax721(address _token,address designer, uint [] memory _futureRoyaltys,string []memory tokenURIOrigins,bytes calldata) external override returns (uint[] memory tokenids){
        require (IMaxity721Token(_token).inWhiteList(msg.sender),"Not owner");
        return IMaxity721Token(_token).mint(designer, msg.sender, _futureRoyaltys, tokenURIOrigins);
    }

    //mintAndSellMax721
    function mintAndSellMax721(
        address _token,
        address designer
        ,uint [] memory _futureRoyaltys,string []memory tokenURIOrigins
        ,uint [] memory unit_prices
        ,bytes calldata ) external override returns (uint[] memory tokenids){
        require (IMaxity721Token(_token).inWhiteList(msg.sender),"User is not whitelisted");

        require (_futureRoyaltys.length == unit_prices.length ,"Price length not equal to mint length");

        uint256 [] memory new_tokenids =  IMaxity721Token(_token).mint(designer, market,_futureRoyaltys, tokenURIOrigins);
        address ngoAddress=IMaxityMetadata(_token).ngowallet();
        IMaxityMarketPlaceV3(market).sellByFixPrice(_token,new_tokenids,unit_prices,ngoAddress);
        return new_tokenids;
    }

    //mintAndAuctionMax721
    function mintAndAuctionMax721(address _token,address designer
        ,uint [] memory _futureRoyaltys,string []memory tokenURIOrigins
        ,uint [] memory base_prices,uint [] memory incre_prices,uint [] memory starttimes,uint [] memory deadlines) external override returns (uint[] memory tokenids){
        
        require (IMaxity721Token(_token).inWhiteList(msg.sender),"User is not whitelisted");
        uint count = _futureRoyaltys.length;
        require (count == base_prices.length ,"base_prices length not equal to mint length");
        require (count == incre_prices.length ,"incre_prices length not equal to mint length");
        require (count == starttimes.length ,"starttimes length not equal to mint length");
        require (count == deadlines.length ,"deadlines length not equal to mint length");
        uint256 [] memory new_tokenids =  IMaxity721Token(_token).mint(designer, market, _futureRoyaltys, tokenURIOrigins);
        address ngoAddress=IMaxityMetadata(_token).ngowallet();
        IMaxityMarketPlaceV3(market).auctionMax721(_token,new_tokenids,base_prices,incre_prices,starttimes,deadlines,ngoAddress);
        return new_tokenids;
    }

    function buyNative(address _token,uint256 _tokenid,address token_to,address nativeSweep) public nonReentrant override payable {
        IWMATIC(wrappedNative).deposit{value: msg.value}();

        assert(IWMATIC(wrappedNative).approve(market, msg.value));
        // uint before_balance = IWMATIC(wrappedNative).balanceOf(address(this));
        IMaxityMarketPlaceV3(market).buy(_token,_tokenid,token_to);
        uint after_balance = IWMATIC(wrappedNative).balanceOf(address(this));
        if(after_balance>0)
        {
            IWMATIC(wrappedNative).transfer(nativeSweep, after_balance);
        }
    }

    function bidNative( address _token,uint256 _tokenid,address token_to,address nativeSweep) public nonReentrant override payable {
        IWMATIC(wrappedNative).deposit{value: msg.value}();
        assert(IWMATIC(wrappedNative).approve(market, msg.value));
        // uint before_balance = IWMATIC(wrappedNative).balanceOf(address(this));
        IMaxityMarketPlaceV3(market).bid(_token,_tokenid,msg.value,token_to);
        uint after_balance = IWMATIC(wrappedNative).balanceOf(address(this));
        if(after_balance>0)
        {
            IWMATIC(wrappedNative).transfer(nativeSweep, after_balance);
        }
    }
    function auctionOnFixPriceNative(address _token,uint _tokenid,address token_to,address nativeSweep,uint deadline)public nonReentrant override payable{
        IWMATIC(wrappedNative).deposit{value: msg.value}();

        assert(IWMATIC(wrappedNative).approve(market, msg.value));
        // uint before_balance = IWMATIC(wrappedNative).balanceOf(address(this));
        IMaxityMarketPlaceV3(market).auctionOnFixPrice(_token,_tokenid,msg.value,token_to,deadline);
        uint after_balance = IWMATIC(wrappedNative).balanceOf(address(this));
        if(after_balance>0)
        {
            IWMATIC(wrappedNative).transfer(nativeSweep, after_balance);
        }

    }


    function delist(address _token,uint256 _tokenid) public onlyOwner override{
        IMaxityMarketPlaceV3(market).delist(_token,_tokenid);
    }

    // function userLend(uint256 _pid,uint256 _lendAmount,address _lender) external override {
    //     require(maxityPool!=address(0x0),"maxityPool is zero address");
    //     IMPool(maxityPool).userLockFromRouter(msg.sender,_pid,_lendAmount,_lender);
    // }
    // function userPayFromRouter(address _lender,address _lpToken,uint256 _utAmount) external override {
    //     require(_lender!=address(0x0),"_lender is zero address");
    //     if(_utAmount>0){
    //         TransferHelper.safeTransferFrom(tokenU, msg.sender, _lender, _utAmount);
    //     }
    //     ILender(_lender).userPayFromRouter(msg.sender,_lpToken,_utAmount);
    // }

    function emergencyWithdraw(address _token) public onlyOwner {
        require(IERC20(_token).balanceOf(address(this)) > 0, "Insufficient contract balance");
        IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this)));
    }

      // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyNative(uint256 amount) public onlyOwner {
        TransferHelper.safeTransferNative(msg.sender,amount)  ;
    }
}
