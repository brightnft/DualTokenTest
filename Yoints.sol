// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// TODO: Router setup isn't complete and not sure if we handle routing ourselves
// Note: Since the contract has activeTrading disabled by default, we can remove blacklisting functionality

/// @title Yoints Token ($YOINTS)
/// @notice ERC-20 Token with management features for trading control, overflow handling, and administrative actions
/// @dev Extends OpenZeppelin's ERC20, Ownable
contract Yoints is ERC20, Ownable, ReentrancyGuard {
	mapping(address => bool) private _blacklisted;

	bool public activeTrading = false;

	address public routerAddress;

	// 100 million tokens with 18 decimals
	uint256 public constant INITIAL_SUPPLY = 100000000 * (10 ** 18);

	/// @dev Marks the timestamp when the contract is deployed
	uint256 public immutable deploymentTime;

	/// @notice Constructs the Yoints Token
	constructor() ERC20("YOINTS Token", "YOINTS") Ownable(_msgSender()) {
		_mint(_msgSender(), INITIAL_SUPPLY);
		deploymentTime = block.timestamp;
	}

	/// @notice Modifier to check if trading is allowed
	/// @dev Can only be called by the owner or if trading is allowed
	modifier tradeControl() {
		require(
			_msgSender() == owner() ||
				(activeTrading && !_blacklisted[_msgSender()]),
			"Account is blacklisted or trading is disabled"
		);
		_;
	}

	/// @notice Sets the router for token exchanges
	/// @param router The address of the exchange router
	function setRouter(address router) external onlyOwner {
		routerAddress = router;
	}

	/// @notice Enables active trading of the token
	/// @dev Can only be enabled by the owner
	function enableActiveTrading() external onlyOwner {
		activeTrading = true;
	}

	/// @notice Blacklists an address to prevent trading
	/// @param account Address to be blacklisted
	/// @dev Blacklisting is only possible within 72 hours of contract deployment
	function blockAccount(address account) external onlyOwner {
		require(
			block.timestamp <= deploymentTime + 72 hours,
			"Blacklisting period expired"
		);
		_blacklisted[account] = true;
	}

	/// @notice Unblacklists an address to allow trading
	/// @param account Address to be unblacklisted
	function unblockAccount(address account) external onlyOwner {
		_blacklisted[account] = false;
	}

	/// @notice Allows recovery of ERC-20 tokens sent to this contract by mistake
	/// @param tokenAddress Address of the ERC-20 token to recover
	/// @param tokenAmount Amount of tokens to recover
	/// @dev Can only be called by the owner
	function claimOverflow(
		address tokenAddress,
		uint256 tokenAmount
	) external onlyOwner nonReentrant {
		ERC20 token = ERC20(tokenAddress);
		require(token.transfer(_msgSender(), tokenAmount), "Transfer failed");
	}

	/// @notice Overrides the transfer function to include trading controls
	/// @param recipient Recipient of the tokens
	/// @param amount Amount of tokens to transfer
	/// @return A boolean that indicates if the operation was successful.
	function transfer(
		address recipient,
		uint256 amount
	) public override tradeControl returns (bool) {
		return super.transfer(recipient, amount);
	}

	/// @notice Overrides the transferFrom function to include trading controls
	/// @param sender Source of the tokens
	/// @param recipient Recipient of the tokens
	/// @param amount Amount of tokens to be transferred
	/// @return A boolean that indicates if the operation was successful.
	function transferFrom(
		address sender,
		address recipient,
		uint256 amount
	) public override tradeControl returns (bool) {
		return super.transferFrom(sender, recipient, amount);
	}
}
