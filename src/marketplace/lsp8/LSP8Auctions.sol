// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ILSP8IdentifiableDigitalAsset} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/ILSP8IdentifiableDigitalAsset.sol";
import {Points} from "../../common/Points.sol";
import {Module} from "../common/Module.sol";
import {ILSP8Listings, LSP8Listing} from "./ILSP8Listings.sol";
import {ILSP8Auctions, LSP8Auction, LSP8Bid} from "./ILSP8Auctions.sol";

contract LSP8Auctions is ILSP8Auctions, Module {
    error NotIssued(uint256 listingId);
    error InsufficientAuthorization(address account, bytes32 tokenId);
    error InvalidAuctionTime(uint256 time);
    error UnathorizedSeller(address account);
    error NotOffered(uint256 listingId, address buyer);
    error Unpaid(uint256 listingId, address buyer, uint256 amount);
    error InactiveAuction(uint256 listingId);
    error InsufficientOfferAmount(uint256 listingId, address buyer, uint256 minimumPrice, uint256 offeredAmount);
    error HighestOfferPending(uint256 listingId, address buyer);

    ILSP8Listings public listings;
    uint32 public minBidDetlaPoints;
    uint256 public bidTimeExtension;
    // listing id -> auction
    mapping(uint256 => LSP8Auction) private _auctions;
    // listing id -> buyer -> bid
    mapping(uint256 => mapping(address => LSP8Bid)) private _bids;
    // listing id -> buyer
    mapping(uint256 => address) private _highestBidder;

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_, ILSP8Listings listings_) external initializer {
        Module._initialize(newOwner_);
        listings = listings_;
        bidTimeExtension = 5 minutes;
    }

    function setMinBidDetlaPoints(uint32 newMinBidDetlaPoints) external onlyOwner {
        require(Points.isValid(newMinBidDetlaPoints));
        minBidDetlaPoints = newMinBidDetlaPoints;
    }

    function setBidTimeExtension(uint256 newBidTimeExtension) external onlyOwner {
        bidTimeExtension = newBidTimeExtension;
    }

    function isIssued(uint256 listingId) public view override returns (bool) {
        return _auctions[listingId].seller != address(0);
    }

    function isActiveAuction(uint256 listingId) public view override returns (bool) {
        LSP8Auction memory auction = _auctions[listingId];
        return (block.timestamp >= auction.startTime) && (block.timestamp < auction.endTime);
    }

    function getAuction(uint256 listingId) public view override returns (LSP8Auction memory) {
        if (!isIssued(listingId)) {
            revert NotIssued(listingId);
        }
        return _auctions[listingId];
    }

    function issue(address asset, bytes32 tokenId, uint256 startPrice, uint256 startTime, uint256 secondsUntilEndTime)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address seller = msg.sender;
        address owner = ILSP8IdentifiableDigitalAsset(asset).tokenOwnerOf(tokenId);
        bool isOperator = ILSP8IdentifiableDigitalAsset(asset).isOperatorFor(seller, tokenId);
        if (!isOperator) {
            revert InsufficientAuthorization(seller, tokenId);
        }
        uint256 listingId = listings.list(asset, tokenId, startPrice, startTime, 0);
        uint256 endTime = startTime + secondsUntilEndTime;
        if (secondsUntilEndTime < 1 hours) {
            revert InvalidAuctionTime(endTime);
        }
        _auctions[listingId] =
            LSP8Auction({seller: seller, startPrice: startPrice, startTime: startTime, endTime: endTime});
        emit Issued(listingId, seller, owner, tokenId, startPrice, startTime, endTime);
        return listingId;
    }

    function cancel(uint256 listingId) external override whenNotPaused nonReentrant {
        LSP8Auction memory auction = getAuction(listingId);
        if (auction.seller != msg.sender) {
            revert UnathorizedSeller(msg.sender);
        }
        LSP8Listing memory listing = listings.getListing(listingId);
        delete _auctions[listingId];
        delete _highestBidder[listingId];
        listings.delist(listingId);
        emit Canceled(listingId, auction.seller, listing.owner, listing.tokenId);
    }

    function settle(uint256 listingId) external override whenNotPaused nonReentrant onlyMarketplace {
        LSP8Auction memory auction = getAuction(listingId);
        LSP8Bid memory bid = getBid(listingId, _highestBidder[listingId]);
        LSP8Listing memory listing = listings.getListing(listingId);
        delete _auctions[listingId];
        delete _highestBidder[listingId];
        delete _bids[listingId][bid.buyer];
        listings.unlist(listingId);
        (bool success,) = msg.sender.call{value: bid.totalPaid}("");
        if (!success) {
            revert Unpaid(listingId, msg.sender, bid.totalPaid);
        }
        emit Settled(listingId, auction.seller, listing.owner, listing.tokenId, bid.buyer, bid.totalPaid);
    }

    function getBid(uint256 listingId, address buyer) public view override returns (LSP8Bid memory) {
        LSP8Bid memory bid = _bids[listingId][buyer];
        if (buyer == address(0) || bid.buyer != buyer) {
            revert NotOffered(listingId, buyer);
        }
        return bid;
    }

    function hasBids(uint256 listingId) external view override returns (bool) {
        return _highestBidder[listingId] != address(0);
    }

    function getHighestBid(uint256 listingId) external view returns (LSP8Bid memory) {
        return getBid(listingId, _highestBidder[listingId]);
    }

    function offer(uint256 listingId) external payable override whenNotPaused nonReentrant {
        if (!isActiveAuction(listingId)) {
            revert InactiveAuction(listingId);
        }
        address buyer = msg.sender;
        LSP8Listing memory listing = listings.getListing(listingId);
        LSP8Auction memory auction = getAuction(listingId);
        LSP8Bid memory lastBid = _bids[listingId][buyer];
        uint256 totalPaid = msg.value + lastBid.totalPaid;
        LSP8Bid memory highestBid = _bids[listingId][_highestBidder[listingId]];
        if (highestBid.buyer == address(0)) {
            // first bid
            if (totalPaid < auction.startPrice) {
                revert InsufficientOfferAmount(listingId, buyer, auction.startPrice, totalPaid);
            }
        } else {
            uint256 deltaAmount = Points.realize(highestBid.totalPaid, minBidDetlaPoints);
            if (totalPaid < highestBid.totalPaid + deltaAmount) {
                revert InsufficientOfferAmount(listingId, buyer, highestBid.totalPaid + deltaAmount, totalPaid);
            }
        }
        _bids[listingId][buyer] = LSP8Bid({buyer: buyer, totalPaid: totalPaid});
        _highestBidder[listingId] = buyer;
        if (block.timestamp + bidTimeExtension > auction.endTime) {
            _auctions[listingId].endTime = auction.endTime + bidTimeExtension;
        }
        emit Offered(listingId, auction.seller, listing.owner, listing.tokenId, buyer, totalPaid);
    }

    function retract(uint256 listingId) external override whenNotPaused nonReentrant {
        address buyer = msg.sender;
        if (isIssued(listingId)) {
            LSP8Auction memory auction = getAuction(listingId);
            // highest bidder needs to wait before retracting the offer
            if (_highestBidder[listingId] == buyer) {
                if (block.timestamp < auction.endTime + 24 hours) {
                    revert HighestOfferPending(listingId, buyer);
                }
                delete _highestBidder[listingId];
            }
        }
        LSP8Bid memory bid = getBid(listingId, buyer);
        delete _bids[listingId][buyer];
        (bool success,) = buyer.call{value: bid.totalPaid}("");
        if (!success) {
            revert Unpaid(listingId, buyer, bid.totalPaid);
        }
        emit Retracted(listingId, buyer, bid.totalPaid);
    }
}
