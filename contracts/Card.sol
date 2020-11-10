// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "./interfaces/IToken.sol";

contract Card is VRFConsumerBaseV2, ConfirmedOwner {
    
    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256[] randomWords;
        bytes32 cardId;
        uint256 tokenAmount;
    }
    
    struct CardInfo {
        uint256 timestamp;
        uint256 cardPower;
        bool forSale;
        uint256 cardPrice;
    }

    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event Created(address indexed from, bytes32 cardId, uint256 amount);
    event Banished(address indexed to, bytes32 cardId, uint256 amount);
    event Listed(address indexed from, bytes32 cardId, uint256 cardPrice);
    event Purchased(address indexed from, address indexed to, bytes32 cardId, uint256 cardPrice);

    uint8[4] public symbols = [0, 2, 4, 7];
    uint8[3] public colors = [1, 2, 3];

    IToken public token;
    mapping(bytes32 => CardInfo) private cards;
    /// @dev The users can have more than once. This is a mapping from address to index
    mapping(address => uint256) private cardCount;
    mapping(uint256 => RequestStatus) public s_requests; /* requestId --> requestStatus */
    VRFCoordinatorV2Interface immutable COORDINATOR;

    // Your subscription ID.
    uint64 immutable s_subscriptionId;

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    // Goerli 30 gwei Key Hash
    bytes32 immutable keyHash;

    // Have to calculate something in callback function so set it 1M
    uint32 callbackGasLimit = 1_000_000;

    uint16 requestConfirmations = 3;

    uint32 numWords = 4;

    /**
     * COORDINATOR Address FOR GOERLI: 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D
     */
    constructor(uint64 _subscriptionId, address _coordinatorAddress, bytes32 _keyHash, address _token)
        VRFConsumerBaseV2(_coordinatorAddress)
        ConfirmedOwner(msg.sender)
    {
        token = IToken(_token);
        COORDINATOR = VRFCoordinatorV2Interface(_coordinatorAddress);
        s_subscriptionId = _subscriptionId;
        keyHash = _keyHash;
    }

    /// @dev Assumes the subscription is funded sufficiently.
    function createCard(uint256 _amount)
        external
        returns (uint256 requestId)
    {
        require(_amount > 0, "Amount must be greater than 0");

        bytes32 cardId = nextCardIdForHolder(msg.sender);
        // Will revert if subscription is not set and funded.
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false,
            cardId: cardId,
            tokenAmount: _amount
        });
        requestIds.push(requestId);
        lastRequestId = requestId;

        uint256 currentLockCount = cardCount[msg.sender];
        cardCount[msg.sender] = currentLockCount + 1;

        token.transferFrom(msg.sender, address(this), _amount);

        emit Created(msg.sender, cardId, _amount);
        return requestId;
    }

    function banishCard(uint256 _index) external {
        bytes32 cardId = cardIdForAddressAndIndex(msg.sender, _index);
        CardInfo storage cardInfo = cards[cardId];
        require(cardInfo.cardPower > 0, "This card does not exist");
        
        uint256 amount = cardInfo.cardPower * 100 * ((block.timestamp - cardInfo.timestamp) / 1 days + 1);

        require(token.balanceOf(address(this)) >= amount, "Insufficient token amount");

        token.transfer(msg.sender, amount);
        
        delete cards[cardId];

        emit Banished(msg.sender, cardId, amount);
    }

    /**
     * @dev Lists a card on the third-party marketplace
     */
    function listCard(uint256 _index, uint256 _cardPrice) external {
        bytes32 cardId = cardIdForAddressAndIndex(msg.sender, _index);
        CardInfo storage cardInfo = cards[cardId];
        require(cardInfo.cardPower > 0, "This card does not exist");

        cardInfo.forSale = true;
        cardInfo.cardPrice = _cardPrice;

        emit Listed(msg.sender, cardId, _cardPrice);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        bytes32 cardId = s_requests[_requestId].cardId;
        uint256 tokenAmount = s_requests[_requestId].tokenAmount;
        uint256 evolution = _randomWords[3] % 100 + 1; // pick a random number between 1 and 100
        uint256 tierNumber = _randomWords[2] % 5 + 1; // pick a random number between 1 and 5

        cards[cardId] = CardInfo(
            uint64(block.timestamp),
            evolution * (tokenAmount * (tierNumber + colors[_randomWords[0] % 3] + symbols[_randomWords[1] % 4])) / 100,
            false,
            0
        );
        emit RequestFulfilled(_requestId, _randomWords);
    }

    function getRequestStatus(uint256 _requestId)
        external
        view
        returns (bool fulfilled, uint256[] memory randomWords)
    {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }

    function getCardPower(uint256 _index) external view returns (uint256) {
        bytes32 cardId = cardIdForAddressAndIndex(msg.sender, _index);
        return cards[cardId].cardPower;
    }

    /**
     * @dev Computes the next card identifier for a given user address.
     */
    function nextCardIdForHolder(address _user) public view returns(bytes32) {
        return cardIdForAddressAndIndex(
            _user,
            cardCount[_user]
        );
    }
    /**
     * @dev Computes the card identifier for an address and an index.
     */
    function cardIdForAddressAndIndex(
        address _user,
        uint256 _index
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_user, _index));
    }
}
