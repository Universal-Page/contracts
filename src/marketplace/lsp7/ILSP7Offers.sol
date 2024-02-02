// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

struct LSP7Offer {
    uint256 itemCount;
    uint256 totalPrice;
    uint256 expirationTime;
}

interface ILSP7Offers {
    /// an offer was made for a listing by a buyer
    event Placed(
        uint256 indexed listingId, address indexed buyer, uint256 itemCount, uint256 totalPrice, uint256 expirationTime
    );
    /// a buyer canceled an offer
    event Canceled(uint256 indexed listingId, address indexed buyer, uint256 itemCount, uint256 totalPrice);
    /// a seller accepted an offer
    event Accepted(uint256 indexed listingId, address indexed buyer, uint256 itemCount, uint256 totalPrice);

    /// confirms an offer has been placed by a buyer
    /// @param listingId listing id
    /// @param buyer buyer
    function isPlacedOffer(uint256 listingId, address buyer) external view returns (bool);

    /// confirms a listing with id is placed and wasn't canceled
    /// @param listingId listing id
    /// @param buyer buyer
    function isActiveOffer(uint256 listingId, address buyer) external view returns (bool);

    /// retrieves an offer for a listing made by a buyer or reverts if not placed
    /// @param listingId listing id
    /// @param buyer buyer
    function getOffer(uint256 listingId, address buyer) external view returns (LSP7Offer memory);

    /// place an offer with a fixed price, number of items and seconds until the offer is expired.
    /// @param listingId listing id
    /// @param itemCount number of items
    /// @param totalPrice total price
    /// @param secondsUntilExpiration time in seconds until offer is expired
    function place(uint256 listingId, uint256 itemCount, uint256 totalPrice, uint256 secondsUntilExpiration)
        external
        payable;

    /// cancel an offer by a buyer being a sender.
    /// @param listingId listing id
    function cancel(uint256 listingId) external;

    /// accept an offer.
    /// @param listingId listing id
    /// @param buyer buyer
    function accept(uint256 listingId, address buyer) external;
}
