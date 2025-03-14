// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title DonationMatcher
 * @dev Contract that matches donations 1:1 for approved recipients
 */
contract DonationMatcher {
    address public owner;
    uint256 public matchingPoolBalance;
    
    // Struct to store recipient information (1 of the 5 donation addresses)
    struct Recipient {
        string name; 
        address payable walletAddress;
        string description;  
        bool isApproved;
        uint256 totalReceived;  
        uint256 totalMatched;  // should be identical 
    }
    
    // Mapping from recipient address to recipient struct
    mapping(address => Recipient) public recipients;
    
    // Array to keep track of all approved recipient addresses
    address[] public approvedRecipientAddresses;
    
    // Events
    event RecipientAdded(address indexed recipientAddress, string name);
    event RecipientRemoved(address indexed recipientAddress);
    event DonationReceived(address indexed donor, address indexed recipient, uint256 amount);
    event MatchingFundAdded(address indexed from, uint256 amount);
    event MatchingApplied(address indexed recipient, uint256 amount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }
    
    modifier recipientExists(address _recipientAddress) {
        require(recipients[_recipientAddress].walletAddress != address(0), "Recipient does not exist");
        _;
    }
    
    modifier recipientApproved(address _recipientAddress) {
        require(recipients[_recipientAddress].isApproved, "Recipient is not approved");
        _;
    }
    
    // Constructor
    constructor() {
        owner = msg.sender;  // nominated owner is the address (wallet) that deploys the smart contract
        
        // Add initial recipients
        // Save the Children
        addRecipient(
            "Save the Children", 
            payable(0x4aAb2278a1325cFdbDF389e0664D100c74B95cf5), 
            "Provides lifesaving aid and support to children in need worldwide."
        );
        
        // American Cancer Society
        addRecipient(
            "American Cancer Society", 
            payable(0xdab278b63a1e2bE659bC90acd733c4c106Dee16C), 
            "Dedicated to eliminating cancer through research, education, and patient services."
        );
        
        // Oceanic Society
        addRecipient(
            "Oceanic Society", 
            payable(0xed0D9A1332E69A42fCAB0DFcd5fBfD68369acABF), 
            "Works to conserve marine ecosystems and wildlife through research and education."
        );
        
        // Little Princess Trust
        addRecipient(
            "Little Princess Trust", 
            payable(0x52fcc1FBC1cD30f562474c1130be514b7FEed539), 
            "Provides free real hair wigs to children and young people up to the age of 24, who have lost their own hair through cancer treatment or other conditions."
        );
    }
    
    /**
     * @dev allows owner to add funds to the matching pool
     */
    // Function to allow the contract owner to add additional matching funds to the pool.
    // It is marked 'payable', meaning it can receive Ether when invoked.
    function addMatchingFunds() external payable onlyOwner {
        // Increase the matching pool balance by the amount of Ether sent with this call
        matchingPoolBalance += msg.value;
        // Emit an event logging who added funds and how much was added
        emit MatchingFundAdded(msg.sender, msg.value);
    }
    
    /**
     * @dev Allows owner to add a new recipient
     * @param _name Name of the recipient organization
     * @param _recipientAddress Wallet address of the recipient
     * @param _description Description of the recipient organization
     */
    /*
    This function allows the contract owner to register a new recipient organization. 
    It first validates the provided recipient address to ensure it’s not a zero address and not already registered. 
    Then it creates and stores a new recipient with specified details (name, address, description), marking them as approved. 
    Finally, it adds the recipient’s address to the list of approved recipients and emits an event signaling the addition.
     */
    function addRecipient(string memory _name, address payable _recipientAddress, string memory _description) public onlyOwner {
        require(_recipientAddress != address(0), "Invalid recipient address");
        require(recipients[_recipientAddress].walletAddress == address(0), "Recipient already exists");
        
        recipients[_recipientAddress] = Recipient({
            name: _name,
            walletAddress: _recipientAddress,
            description: _description,
            isApproved: true,
            totalReceived: 0,
            totalMatched: 0
        });
        
        approvedRecipientAddresses.push(_recipientAddress);
        emit RecipientAdded(_recipientAddress, _name);
    }
    
    /**
     * @dev Allows owner to remove a recipient
     * @param _recipientAddress Address of the recipient to remove
     */
    /*
    This function enables the contract owner to remove (disapprove) an existing recipient. 
    It first sets the recipient's approval status to false. 
    Then, it loops through the array of approved recipients, finds the matching recipient address, and efficiently removes it by swapping it with the last element and then popping it from the array. 
    Finally, an event is emitted indicating the removal.
     */
    function removeRecipient(address _recipientAddress) external onlyOwner recipientExists(_recipientAddress) {
        recipients[_recipientAddress].isApproved = false;
        
        // Remove from the approved list
        for (uint i = 0; i < approvedRecipientAddresses.length; i++) {
            if (approvedRecipientAddresses[i] == _recipientAddress) {
                // Move the last element to the position of the element to delete
                approvedRecipientAddresses[i] = approvedRecipientAddresses[approvedRecipientAddresses.length - 1];
                // Remove the last element
                approvedRecipientAddresses.pop();
                break;
            }
        }
        
        emit RecipientRemoved(_recipientAddress);
    }
    
    /**
     * @dev Allows anyone to donate to an approved recipient
     * @param _recipientAddress Address of the recipient
     */
    /*
    This function allows any user to donate Ether to an approved recipient. 
    It validates that the donation amount is greater than zero, updates the recipient's total received funds, and then calls a function (applyMatching) to apply any matching funds available. 
    After applying matching, it forwards the donated Ether directly to the recipient's wallet address and emits an event logging the donation details.
     */
    function donate(address _recipientAddress) external payable recipientExists(_recipientAddress) recipientApproved(_recipientAddress) {
        require(msg.value > 0, "Donation amount must be greater than 0");
        
        // Record the donation
        recipients[_recipientAddress].totalReceived += msg.value;
        
        // Apply matching if possible
        applyMatching(_recipientAddress, msg.value);
        
        // Forward the donation to the recipient
        recipients[_recipientAddress].walletAddress.transfer(msg.value);
        
        emit DonationReceived(msg.sender, _recipientAddress, msg.value);
    }
    
    /**
     * @dev Internal function to apply matching funds
     * @param _recipientAddress Address of the recipient
     * @param _amount Amount to match
     */
    /*
    This internal function applies matching funds to a recipient when a donation is made. 
    It calculates the matching amount based on the available balance in the matching pool—matching up to the donated amount but capped by the pool balance. 
    It then deducts the matching amount from the pool balance, updates the recipient's total matched funds, transfers the matched Ether directly to the recipient, and emits an event to document the matching action.
     */
    function applyMatching(address _recipientAddress, uint256 _amount) internal {
        // Check if we have enough in the matching pool
        uint256 matchingAmount = _amount;
        if (matchingAmount > matchingPoolBalance) {
            matchingAmount = matchingPoolBalance;
        }
        
        if (matchingAmount > 0) {
            // Update state
            matchingPoolBalance -= matchingAmount;
            recipients[_recipientAddress].totalMatched += matchingAmount;
            
            // Transfer matching funds
            recipients[_recipientAddress].walletAddress.transfer(matchingAmount);
            
            emit MatchingApplied(_recipientAddress, matchingAmount);
        }
    }
    
    /**
     * @dev Returns the list of all approved recipients
     * @return Array of recipient addresses
     */
    function getApprovedRecipients() external view returns (address[] memory) {
        return approvedRecipientAddresses;
    }
    
    //@dev Gets recipient details * @param _recipientAddress Address of the recipient * @return Recipient details
    /*
    This function retrieves and returns detailed information about a specific recipient. 
    It accepts the recipient's wallet address, verifies the recipient exists, fetches their stored data (name, wallet address, description, approval status, total donations received, and total matching funds received), and returns these details to the caller. 
    It's a read-only function (view) and doesn't modify the contract state.
    */
    function getRecipientDetails(address _recipientAddress) 
        external 
        view 
        recipientExists(_recipientAddress) 
        returns (
            string memory name, 
            address walletAddress, 
            string memory description, 
            bool isApproved, 
            uint256 totalReceived, 
            uint256 totalMatched
        ) {
        Recipient memory recipient = recipients[_recipientAddress];
        return (
            recipient.name,
            recipient.walletAddress,
            recipient.description,
            recipient.isApproved,
            recipient.totalReceived,
            recipient.totalMatched
        );
    }
    
    /**
     * @dev Allows the owner to withdraw any excess matching funds
     * @param _amount Amount to withdraw
     */
    /*
    This function allows the contract owner to withdraw a specified amount of Ether from the matching funds pool. 
    It ensures the withdrawal amount doesn't exceed the available balance, updates the pool balance accordingly, and transfers the Ether directly to the owner's wallet address.
     */
    function withdrawMatchingFunds(uint256 _amount) external onlyOwner {
        require(_amount <= matchingPoolBalance, "Insufficient funds in matching pool");
        
        matchingPoolBalance -= _amount;
        payable(owner).transfer(_amount);
    }
}
