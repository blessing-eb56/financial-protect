# Financial Protection System

A Clarity smart contract that implements a decentralized financial protection system where users can purchase protection for their assets and file claims in case of losses.

## Overview

The Financial Protection System allows users to:
- Purchase protection for their contracts/assets
- File protection requests when losses occur
- Process and manage claims through an approval system
- Track protection status and request history

## Key Features

- **Protection Pool**: A shared pool of funds used to pay out approved claims
- **Request Management**: Complete lifecycle management for protection requests
- **Expiration System**: Automatic expiration of requests after a defined period
- **Partial Payouts**: Support for partial claim payments when pool funds are insufficient
- **Owner Controls**: Secure administrative functions for contract management

## Functions

### Public Functions

#### Protection Management
- `purchase-protection (amount: uint) → (response bool uint)`
  - Purchase protection coverage for the specified amount
  - Returns success or error with specific error code

- `file-request (request-amount: uint) → (response bool uint)`
  - File a new protection request
  - Amount must be less than or equal to protected amount

#### Request Processing
- `approve-request (requester: principal) (request-amount: uint) → (response uint uint)`
  - Approve and process a protection request
  - Only callable by contract owner
  - Returns the actual payout amount

- `reject-request (requester: principal) (request-amount: uint) → (response bool uint)`
  - Reject a protection request
  - Only callable by contract owner

#### Administrative Functions
- `change-contract-owner (new-owner: principal) → (response bool uint)`
  - Transfer contract ownership to a new principal
  - Only callable by current owner

- `check-and-expire-request (requester: principal) (request-amount: uint) → (response bool uint)`
  - Check and expire requests that have exceeded the expiration period

### Read-Only Functions

- `get-pool-balance () → (response uint uint)`
  - Returns the current balance of the protection pool

- `is-protected (contract: principal) → bool`
  - Check if a contract has active protection

- `get-protected-amount (contract: principal) → (response uint uint)`
  - Get the protection amount for a specific contract

- `get-request-status (requester: principal) (request-amount: uint) → (response {status: (string-ascii 20), timestamp: uint, paid-amount: uint} uint)`
  - Get detailed status information for a specific request

## Error Codes

- `ERR_INVALID_AMOUNT (u100)`: Invalid amount specified
- `ERR_INSUFFICIENT_FUNDS (u101)`: Insufficient funds for operation
- `ERR_REQUEST_NOT_FOUND (u102)`: Request not found
- `ERR_UNAUTHORIZED (u103)`: Unauthorized access attempt
- `ERR_ALREADY_PROTECTED (u104)`: Contract already has protection
- `ERR_INVALID_PRINCIPAL (u105)`: Invalid principal specified
- `ERR_NOT_PROTECTED (u106)`: Contract not protected
- `ERR_ZERO_AMOUNT (u107)`: Zero amount specified
- `ERR_REQUEST_ALREADY_PROCESSED (u108)`: Request already processed
- `ERR_POOL_EMPTY (u109)`: Protection pool is empty
- `ERR_REQUEST_NOT_EXPIRED (u110)`: Request has not expired
- `ERR_REQUEST_EXCEEDS_PROTECTED (u111)`: Request exceeds protected amount

## Configuration

- Request Expiration Period: 4320 blocks (approximately 30 days at 10-minute block times)

## Events

The contract emits the following events:
- `protection-purchased`: When new protection is purchased
- `request-filed`: When a new request is filed
- `request-approved`: When a request is approved and paid
- `request-rejected`: When a request is rejected
- `request-expired`: When a request expires
- `contract-owner-changed`: When contract ownership changes

## Security Considerations

- Only the contract owner can approve or reject requests
- Protection amounts are verified against available pool funds
- Request expiration prevents indefinite pending requests
- Principal validation prevents invalid ownership transfers