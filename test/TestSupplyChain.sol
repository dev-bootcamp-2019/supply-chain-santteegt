pragma solidity ^0.5.0;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/SupplyChain.sol";

// Proxy contract for testing throws
contract ThrowProxy {
  address public target;
  bytes data;

  constructor(address _target) public {
    target = _target;
  }

  //prime the data using the fallback function.
  // since it doesn’t have that function, the fallback function is triggered in its place
  function() external {
    data = msg.data;
  }

  function execute() public returns (bool success) {
    (success, ) = target.call(data);
  }
}

// Contract that represents a Seller entity
contract Seller {

    SupplyChain supplyChain;

    constructor() public {
        supplyChain = SupplyChain(DeployedAddresses.SupplyChain());
    }

    function addItem(string memory _itemName, uint _price) public {
        supplyChain.addItem(_itemName, _price);
    }

    function markItemShipped(uint _sku) public returns (bool success) {
        (success, ) =  address(supplyChain).call(abi.encodeWithSignature("shipItem(uint256)", _sku));
    }

    // If c is a contract, address(c) results in address payable only if c has a payable fallback function
    function() external payable {

    }
}

// Contract that represents a Buyer entity
contract Buyer {

    SupplyChain supplyChain;

    constructor() public {
        supplyChain = SupplyChain(DeployedAddresses.SupplyChain());
    }

    function createOffer(uint256 _sku, uint _price) public returns (bool success) {
        (success, ) = address(supplyChain).call.value(_price)(abi.encodeWithSignature("buyItem(uint256)", _sku));
    }

    // Failing condition
    function markItemShipped(uint _sku) public returns (bool success) {
        (success, ) =  address(supplyChain).call(abi.encodeWithSignature("shipItem(uint256)", _sku));
    }

    function markItemReceived(uint _sku) public returns (bool success) {
        (success, ) = address(supplyChain).call(abi.encodeWithSignature("receiveItem(uint256)", _sku));
    }

    // If c is a contract, address(c) results in address payable only if c has a payable fallback function
    function() external payable {

    }

}

contract TestSupplyChain {

    uint public initialBalance = 10 ether;

    SupplyChain supplyChain;

    ThrowProxy throwProxy;

    // entities that represent a buyer and a seller on the supply chain
    Seller seller;
    Buyer buyer;

    // item properties
    string name;
    uint sku;
    uint price;
    uint state;
    address sellerAddress;
    address buyerAddress;

    // Test for failing conditions in this contracts
    // test that every modifier is working

    function beforeAll() public {
        supplyChain = SupplyChain(DeployedAddresses.SupplyChain());
        throwProxy = new ThrowProxy(address(supplyChain));
        seller = new Seller();
        buyer = new Buyer();
    }

    // Test Creating an Item for Sale
    function testCreateItemForSale() public {
        string memory itemName = "Test Item";
        uint itemValue = 5;
        
        seller.addItem(itemName, itemValue);
        // check details
        (name, sku, price, state, sellerAddress, buyerAddress) = supplyChain.fetchItem(0);
        // (string memory name, sku, price, state, seller) = supplyChain.fetchItem(0);

        Assert.equal(itemName, name, 'Wrong Item name');
        Assert.equal(itemValue, price, 'Wrong ItemPrice');
        Assert.equal(sellerAddress, address(seller), 'Wrong Seller address');
        Assert.equal(0, state, 'Wrong Item State (not ForSale)');
    }

    // Test Seller can't ship an item that is not sold
    function testItemNotSoldForShipment() public {
        bool result = seller.markItemShipped(0);
        Assert.isFalse(result, "revert() failed. Item should not be able to me marked for shipment");

        result = buyer.markItemShipped(0);
        Assert.isFalse(result, "revert() failed. Buyer should not be able to mark this item for shipment");
    }

    // Alternative test using ThrowProxy contract
    function testItemNotSoldWithProxyContract() public {
        //prime the proxy.
        SupplyChain(address(throwProxy)).shipItem(0);

        // Since the throw would use up all the gas, the rest of the tests would legitimately OOG, 
        // so we restrict the gas sent through when calling the execute() method. 
        bool r = throwProxy.execute.gas(200000)();
        Assert.isFalse(r, "Should be false, as it should throw");
    }

    // buyItem

    // test for failure if user does not send enough funds
    // test for purchasing an item that is not for Sale

    // Test Buyer trying to Purchase the Item for too little
    function testBuyNotEnoughCash() public {
        // add some funds to the buyer 
        address(buyer).transfer(10);
        // try to purchase for price-1
        bool result = buyer.createOffer(0, price-1);
        // check details
        Assert.isFalse(result, "Not enough cash failed to revert");
        
        // check details
        (name, sku, price, state, sellerAddress, buyerAddress) = supplyChain.fetchItem(0);

        Assert.equal(0, state, 'State should still be 0 (ForSale)');
        Assert.equal(address(0), address(buyerAddress), 'Buyer should still be empty');
    }

    // Test Buyer Purchase with sufficient offer
    function testBuyItem() public {
        string memory itemName = "Test Item";
        uint itemValue = 5;

        bool result = buyer.createOffer(0, itemValue);
        Assert.isTrue(result, "buyItem threw an exception");
        
        // check details
        (name, sku, price, state, sellerAddress, buyerAddress) = supplyChain.fetchItem(0);

        Assert.equal(itemName, name, 'Wrong Item name');
        Assert.equal(buyerAddress, address(buyer), 'Wrong Buyer address');
        Assert.equal(1, state, 'Wrong State (not Sold)');
    }

    // Test trying to purchase an item that is not for Sale (already sold)
    function testItemAlreadySold() public {
        bool result = buyer.createOffer(0, 5);   // Sku 0 already purchased
        Assert.isFalse(result, "revert() failed. Item should not be available for selling");
    }

    // shipItem

    // test for calls that are made by not the seller
    // test for trying to ship an item that is not marked Sold

    // Test non-buyer trying to mark a shipped Item as received
    function testNotSellerMarkItemShipped() public {
        (bool result, ) = address(supplyChain).call(abi.encodeWithSignature("shipItem(uint256)", 0));
        Assert.isFalse(result, "revert() failed. Item should not be able to be marked for Shipment");
    }

    function testItemNotShipped() public {
        bool result = buyer.markItemReceived(0);
        Assert.isFalse(result, "revert() failed. Item should not be able to be marked as Received");
    }

    // Test that Seller can mark a sold Items only as shipped
    function testShipItem() public {
        bool result = seller.markItemShipped(0);
        Assert.isTrue(result, "shipItem threw an exception");
        
        // check details
        (name, sku, price, state, sellerAddress, buyerAddress) = supplyChain.fetchItem(0);

        Assert.equal(2, state, 'Wrong State (not Shipped)');

        // Test with a new item
        seller.addItem("Item 1", 10);
        result = seller.markItemShipped(1);
        Assert.isFalse(result, "Item should not be able to be marked for shipment");
    }

    // receiveItem

    // test calling the function from an address that is not the buyer
    // test calling the function on an item not marked Shipped

    // Test non-buyer trying to mark a shipped Item as received
    function testNotBuyerMarkItemReceived() public {
        (bool result, ) = address(supplyChain).call(abi.encodeWithSignature("receiveItem(uint256)", 0));
        Assert.isFalse(result, "revert() failed. Item should not be able to mark as Received");
    }

    // Test that Buyer can mark a shipped Item received
    function testReceiveItem() public {
        bool result = buyer.markItemReceived(0);
        Assert.isTrue(result, "shipItem threw an exception");
        
        // check details
        (name, sku, price, state, sellerAddress, buyerAddress) = supplyChain.fetchItem(0);
        Assert.equal(3, state, 'Wrong State (not Received)');

        // Test with not purchased item
        result = buyer.markItemReceived(1);
        Assert.isFalse(result, "Item should not be able to be marked as received");
    }
}
