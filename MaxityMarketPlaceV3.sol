// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import  '../../libraries/TransferHelper.sol';

import "../interface/IMaxityMarketPlaceV3.sol";
import "../interface/IMaxityMarketPlace.sol";
import "../interface/IMaxity721Token.sol";
import "../interface/IMaxityMetadata.sol";

contract MaxityMarketPlaceV3 is OwnableUpgradeable, PausableUpgradeable ,IMaxityMarketPlaceV3,IERC721ReceiverUpgradeable,ReentrancyGuardUpgradeable{
    using SafeMath for uint256;

    event TokenIdOnSale(address indexed _token,uint256 indexed _tokenid,address indexed seller,uint256 fixprice,uint256 sold_count);

    event TokenIdOnAuctionByPrice(address indexed _token,uint256 indexed _tokenid,address indexed buyer,uint256 price,uint price_idx,uint256 fixprice,uint deadline);
    event OnAuctionByPriceCanceled(address indexed _token,uint256 indexed _tokenid,address indexed token_to,uint price_idx);
    event OnAuctionByPriceAccepted(address indexed _token,uint256 indexed _tokenid,address indexed token_to,uint256 price,uint price_idx);

    event TokenIdDelist(address indexed _token,uint256 indexed _tokenid,address indexed seller);

    event TokenIdOnAuction(address indexed _token,uint256 indexed _tokenid,address indexed seller,uint base_price,uint incre_price,uint deadline,uint starttime);

    event BidOnTokenId(address indexed _token,uint256 indexed _tokenid,address indexed buyer,uint bid_price);

    enum TradeMode{
        FIX_PRICE ,
        BID_PRICE,
        AUCTION_ON_FIX_PRICE,
        UNKNOW
    }

    event TokenIdSaled(address indexed _token,uint256 indexed _tokenid,address  buyer,address  seller,uint256 price,uint sold_count,TradeMode mode);

    struct SaleInfo{
        bool isAuction;
        uint256 fixprice;
        uint base_price;
        uint incre_price;
        uint starttime;
        uint deadline;
        uint cur_bid_price;
        address price_offer;
        address seller;
        // bool firstSell;
        uint current_offer_idx ;
    }

   

    mapping(address=>mapping(uint => SaleInfo))  public marketUnits;

    struct OfferInfo{
        uint deadline;
        uint cur_bid_price;
        uint prev_idx;
        address price_offer;
        bool isCancel;
        uint  price_debt;
    }

    mapping(address=>mapping(uint => mapping(uint => OfferInfo)))  public bidOffers;

    using Counters for Counters.Counter;

    Counters.Counter private _bidOfferCounter;


    mapping(address=>mapping(uint=>uint)) public soldCount;
    mapping(address=>mapping(uint=>uint)) public offerCount;
    address public ut;
    address public feeTo;
    uint public MAX_OFFER_COUNT;
    address public router;
    uint public r_FirstSold_toNgo;
    uint public r_SecodeSold_toNgo;
    uint public feePercentage;

    function __MaxityMarketPlaceV3_init(address _ut,address _feeTo) external initializer {
        __Ownable_init_unchained();
        // __Pausable_init();
        __ReentrancyGuard_init();
        __MaxityMarketPlaceV3_init_unchained(_ut, _feeTo);
    }

    function __MaxityMarketPlaceV3_init_unchained(address _ut,address _feeTo) internal onlyInitializing {
        ut = _ut;
        feeTo = _feeTo;
        MAX_OFFER_COUNT=10;
        r_FirstSold_toNgo =  91836735;//div 1e8,,=90/98*100 * 1e8
        r_SecodeSold_toNgo = 80000000;//div 1e8,,=80/100*100   * 1e8
        feePercentage      =  2000000;//div 1e8 = 2/100 * 100 * 1e8
    }

    function pauseOrUnpause() onlyOwner public { 
        if(paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    function setUTToken(address _ut) onlyOwner public{ 
        ut = _ut;
    }

    function setFeeTo(address _feeTo) onlyOwner public{ 
        feeTo = _feeTo;
    }

    function setRouter(address _router) onlyOwner public{ 
        router = _router;
    }

    function setOfferCount(uint _count) onlyOwner public{ 
        MAX_OFFER_COUNT = _count;
    }

    

    function sellByFixPrice(address _token,uint256[] memory _tokenids,uint [] memory _prices,address _seller) whenNotPaused nonReentrant external  returns (uint) {
            
        uint256 length = _tokenids.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            uint256 _tokenid=_tokenids[pid];
            require(marketUnits[_token][_tokenid].seller==address(0x0),"Token already on the marketplace");
            SaleInfo storage saleInfo = marketUnits[_token][_tokenid];
            if(IERC721(_token).ownerOf(_tokenid)!=address(this)){//first mint
                IERC721(_token).transferFrom(msg.sender, address(this), _tokenid);
            }
            saleInfo.seller = _seller;
            // 
            saleInfo.isAuction = false;
            saleInfo.fixprice = _prices[pid];

            emit TokenIdOnSale(_token,_tokenid,saleInfo.seller,_prices[pid],soldCount[_token][_tokenid]);
        }
        return length;
    }

    function onERC721Received( address , address , uint256 , bytes calldata  ) public override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function auctionMax721(address _token,uint256[] memory _tokenids,uint[] memory base_prices,uint [] memory incre_prices,uint[] memory starttimes,uint[] memory deadlines,address _seller) external 
    whenNotPaused nonReentrant returns (uint amountU){
        uint256 length = _tokenids.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            uint256 _tokenid=_tokenids[pid];
            require(marketUnits[_token][_tokenid].seller==address(0x0),"Token already on the marketplace");
            SaleInfo storage saleInfo = marketUnits[_token][_tokenid];
             if(IERC721(_token).ownerOf(_tokenid)!=address(this)){//first mint
                IERC721(_token).safeTransferFrom(msg.sender, address(this), _tokenid);                
            }
            saleInfo.seller = _seller;
            // 
            saleInfo.isAuction = true;
            saleInfo.base_price = base_prices[pid];
            saleInfo.incre_price = incre_prices[pid];
            saleInfo.starttime = starttimes[pid];
            saleInfo.deadline = deadlines[pid];
            saleInfo.cur_bid_price = base_prices[pid];
            emit TokenIdOnAuction(_token,_tokenid,saleInfo.seller,base_prices[pid],incre_prices[pid],deadlines[pid],starttimes[pid]);
        }
        return length;
    }

    function buy(address _token,uint256 _tokenid,address to) public whenNotPaused nonReentrant  {
        SaleInfo storage saleInfo = marketUnits[_token][_tokenid];
        require(saleInfo.seller!=address(0x0),"This token is not for sale");
        require(IERC721(_token).ownerOf(_tokenid)==address(this),"This token is not on the marketplace");
        require(!saleInfo.isAuction,"This token is on auction");
        TransferHelper.safeTransferFrom(ut, msg.sender, address(this), saleInfo.fixprice);
        offerCount[_token][_tokenid]=0;

        tradeDone(_token,_tokenid,saleInfo.fixprice,to,TradeMode.FIX_PRICE);
    }


    function getValidOfferOnFixPrice(address _token,uint _tokenid,uint _offeridx) public view returns (OfferInfo memory){
        OfferInfo memory offerInfo = bidOffers[_token][_tokenid][_offeridx];
        require(offerInfo.deadline>block.timestamp && !offerInfo.isCancel,"offer info is not valid");
        return offerInfo;
    }

    function auctionOnFixPrice(address _token,uint _tokenid,uint _price,address price_offer,uint deadline) public whenNotPaused nonReentrant  override returns (uint){
        SaleInfo storage saleInfo = marketUnits[_token][_tokenid];
        require(saleInfo.seller!=address(0x0),"This token is not for sale");
        require(IERC721(_token).ownerOf(_tokenid)==address(this),"This token is not on the marketplace");
        require(!saleInfo.isAuction,"This token is on auction");
        require(_price > 0,"price is 0");
        require(block.timestamp < deadline,'bid deadline exceed block.timestamp');
        
        uint _offerCount=offerCount[_token][_tokenid];
        require(_offerCount<=MAX_OFFER_COUNT,"bid 10 times at most");

        TransferHelper.safeTransferFrom(ut, msg.sender, address(this), _price);
        _bidOfferCounter.increment();
        uint offer_idx  = _bidOfferCounter.current();
        OfferInfo storage offerInfo = bidOffers[_token][_tokenid][offer_idx];
        offerInfo.deadline = deadline;
        offerInfo.isCancel = false;
        offerInfo.price_offer = price_offer;
        offerInfo.cur_bid_price = _price;
    
        offerCount[_token][_tokenid] =  _offerCount + 1;

        emit TokenIdOnAuctionByPrice(_token,_tokenid,price_offer,_price,offer_idx,saleInfo.fixprice,offerInfo.deadline);
        return offer_idx;
    }

    function cancelOrWithdrawAuctionOnFixPrice(address _token,uint _tokenid,uint _offer_idx,address _token_to) public whenNotPaused nonReentrant  {

        OfferInfo storage offerInfo = bidOffers[_token][_tokenid][_offer_idx];
        require(offerInfo.price_offer==msg.sender || owner() == _msgSender() ,"Only offerer or owner can cancel or withdraw");
        require(!offerInfo.isCancel,"offer already canceled");
        
        require(offerInfo.price_debt==0,"offer already withdrawed");
        offerInfo.price_debt = offerInfo.cur_bid_price;
        offerInfo.isCancel = true;
        TransferHelper.safeTransfer(ut,_token_to, offerInfo.cur_bid_price);

        emit OnAuctionByPriceCanceled(_token,_tokenid,_token_to,_offer_idx);

    }


    function agreeAuctionOnFixPrice(address _token,uint _tokenid,uint _offeridx) public whenNotPaused nonReentrant  override {
        SaleInfo memory saleInfo = marketUnits[_token][_tokenid];
        require(saleInfo.seller!=address(0x0),"This token is not for sale");
        require(IERC721(_token).ownerOf(_tokenid)==address(this),"This token is not on the marketplace");
        require(!saleInfo.isAuction,"This token is on auction");
        require(saleInfo.seller==msg.sender || owner() == _msgSender(),"Only seller or owner can make agreement");

        OfferInfo memory offerInfo =  getValidOfferOnFixPrice(_token,_tokenid,_offeridx); 
        offerInfo.price_debt = offerInfo.cur_bid_price;
        offerInfo.isCancel = true;
        offerCount[_token][_tokenid]=0;
        bidOffers[_token][_tokenid][_offeridx] = offerInfo;
        tradeDone(_token, _tokenid, offerInfo.cur_bid_price, offerInfo.price_offer,TradeMode.AUCTION_ON_FIX_PRICE);

        emit OnAuctionByPriceAccepted(_token,_tokenid,offerInfo.price_offer,offerInfo.cur_bid_price,_offeridx);
        
    }


    function delistV2(address _token,uint256 _tokenid,address _to) public nonReentrant {
        SaleInfo storage saleInfo = marketUnits[_token][_tokenid];
        require(saleInfo.seller!=address(0x0),"This token is not for sale");
        require(IERC721(_token).ownerOf(_tokenid)==address(this),"This token is not on the marketplace");
        require(saleInfo.seller==msg.sender || _msgSender() == router || owner() == _msgSender(),"Only seller, router or owner can make delist");
        
        if(saleInfo.isAuction){
            require(block.timestamp < saleInfo.starttime || block.timestamp > saleInfo.deadline,"In the bidding");
        }
        if(saleInfo.price_offer!=address(0x0) && saleInfo.cur_bid_price >0){
            TransferHelper.safeTransfer(ut, saleInfo.price_offer,saleInfo.cur_bid_price);
        }

        IERC721(_token).transferFrom(address(this), _to , _tokenid);
        delete marketUnits[_token][_tokenid];
        emit TokenIdDelist(_token,_tokenid,msg.sender);

    }

   function delist(address _token,uint256 _tokenid) public nonReentrant override {
        SaleInfo storage saleInfo = marketUnits[_token][_tokenid];
        require(saleInfo.seller!=address(0x0),"This token is not for sale");
        require(IERC721(_token).ownerOf(_tokenid)==address(this),"This token is not on the marketplace");
        require(saleInfo.seller==msg.sender || _msgSender() == router || owner() == _msgSender() ,"Only seller, router or owner can make delist");
        
        if(saleInfo.isAuction){
            require(block.timestamp < saleInfo.starttime || block.timestamp > saleInfo.deadline,"In the bidding");
        }
        offerCount[_token][_tokenid]=0;

        IERC721(_token).transferFrom(address(this), saleInfo.seller, _tokenid);
        delete marketUnits[_token][_tokenid];
        emit TokenIdDelist(_token,_tokenid,msg.sender);
    }

    function bid(address _token,uint256 _tokenid,uint256 amount,address to) public whenNotPaused nonReentrant {
        SaleInfo storage saleInfo = marketUnits[_token][_tokenid];
        require(saleInfo.seller!=address(0x0),"This token is not for sale");
        require(IERC721(_token).ownerOf(_tokenid)==address(this),"This token is not on the marketplace");
        require(saleInfo.isAuction,"This token is not on auction");
        require(block.timestamp <= saleInfo.deadline,"Auction have ended");
        require(block.timestamp >= saleInfo.starttime,"Auction have not started");
        
        require(!checkAuctionDone(_token,_tokenid),"auction is done");
    
        uint256 nextbidPrice = saleInfo.cur_bid_price.add(saleInfo.incre_price);
        uint256 feeAmount = amount.mul(feePercentage).div(1e8+feePercentage);
        uint256 priceOffer = amount.sub(feeAmount);
        require(priceOffer>=nextbidPrice, "bid amount not valid");
        TransferHelper.safeTransferFrom(ut, msg.sender, address(this), amount);

        if(saleInfo.price_offer!=address(0x0)){
            TransferHelper.safeTransfer(ut, saleInfo.price_offer, saleInfo.cur_bid_price.mul(1e8+feePercentage).div(1e8));
        }
        saleInfo.price_offer = to;
        saleInfo.cur_bid_price = priceOffer;
        emit BidOnTokenId(_token,_tokenid,to,priceOffer);
         
    }

    function setFeeAndSoldPercentage(uint _feePercentage,uint _r_FirstSold_toNgo,uint _r_SecodeSold_toNgo) onlyOwner public{
        feePercentage = _feePercentage;
        r_FirstSold_toNgo = _r_FirstSold_toNgo;
        r_SecodeSold_toNgo = _r_SecodeSold_toNgo;
    }


    function tradeDone(address _token,uint256 _tokenid,uint total_amount,address buyer,TradeMode mode) internal {
        SaleInfo storage saleInfo = marketUnits[_token][_tokenid];
        uint256 amount;
        uint256 feeAmount = total_amount.mul(feePercentage).div(1e8);
        TransferHelper.safeTransfer(ut, feeTo, feeAmount);
        amount = total_amount.sub(feeAmount);
        
        uint _soldCount = soldCount[_token][_tokenid];
        
        if(checkMethodExist(_token)) {
            if(_soldCount==0){//first sell
                if(IMaxityMetadata(_token).disigner(_tokenid)==address(0x0)){
                    TransferHelper.safeTransfer(ut, saleInfo.seller,amount);
                }else{//ngo has no designer ability

                    uint amount_2_ngo = amount.mul(r_FirstSold_toNgo).div(1e8);
                    TransferHelper.safeTransfer(ut, saleInfo.seller,amount_2_ngo );//to ngo
                    TransferHelper.safeTransfer(ut, IMaxityMetadata(_token).disigner(_tokenid), amount.sub(amount_2_ngo));//to designer
                }
                soldCount[_token][_tokenid] = 1;
            }else{//2nd saled
                uint256 futureSaleAmount = amount.mul(IMaxityMetadata(_token).futureRoyalty(_tokenid)).div(1e8);
                uint256 remainAmount = amount.sub(futureSaleAmount);
                if(IMaxityMetadata(_token).disigner(_tokenid)==address(0x0)){ //ngo has no ability to design nft
                    TransferHelper.safeTransfer(ut, IMaxityMetadata(_token).ngowallet(),futureSaleAmount);
                }else{//ngo has  designer ability
                    uint amount_2_ngo = futureSaleAmount.mul(r_SecodeSold_toNgo).div(1e8);
                    TransferHelper.safeTransfer(ut, IMaxityMetadata(_token).ngowallet(), amount_2_ngo);//to ngo
                    TransferHelper.safeTransfer(ut, IMaxityMetadata(_token).disigner(_tokenid), futureSaleAmount.sub(amount_2_ngo));//to designer
                }
                TransferHelper.safeTransfer(ut, saleInfo.seller,remainAmount);
                soldCount[_token][_tokenid] =  soldCount[_token][_tokenid] + 1;
            } 
        } else {
            TransferHelper.safeTransfer(ut, saleInfo.seller,amount);
        }
        IERC721(_token).transferFrom(address(this), buyer, _tokenid);
        emit TokenIdSaled(_token,_tokenid, buyer,saleInfo.seller,amount, _soldCount,mode);
        delete marketUnits[_token][_tokenid];
    }


    function checkAuctionDone(address _token,uint256 _tokenid) public whenNotPaused returns(bool){
        SaleInfo storage saleInfo = marketUnits[_token][_tokenid];
        require(saleInfo.seller!=address(0x0),"This token is not for sale");
        require(IERC721(_token).ownerOf(_tokenid)==address(this),"This token is not on the marketplace");
        require(saleInfo.isAuction,"This token is not on auction");
        if(saleInfo.deadline < block.timestamp){
            if(saleInfo.price_offer!=address(0x0))
            {
                TransferHelper.safeTransfer(ut, feeTo, saleInfo.cur_bid_price.mul(feePercentage).div(1e8));
                tradeDone(_token,_tokenid,saleInfo.cur_bid_price,saleInfo.price_offer,TradeMode.BID_PRICE);
            }
            return true;
        }
        return false;
        
    }


    function emergencyWithdraw(address token,address to) external  onlyOwner {
        uint amount = IERC20(token).balanceOf(address(this));
        if(amount>0){
            TransferHelper.safeTransfer(token,to, amount);
        }

    }

    function emergencyWithdrawNFT(address token,uint256 tokenId,address to) external  onlyOwner {
        uint amount = IERC20(token).balanceOf(address(this));
        if(amount>0){
            IERC721(token).safeTransferFrom(address(this), to, tokenId);
        }

    }

    function checkMethodExist(address token) view internal returns(bool) {
        (bool success, ) = token.staticcall(abi.encodeWithSelector(0x9b1879bc));
        return success;
    }

    uint256[50] private __gap;

}
