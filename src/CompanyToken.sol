// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Company.md (COMD)
/// @notice A fixed-supply ERC-20. The whole supply is minted once, in the constructor, to the
///         deployer (`msg.sender`). There is no owner, no minter, no pause, no blocklist, no fee
///         and no burn hook: after construction the contract has no privileged functions at all,
///         and the supply can never change.
/// @dev Built on OpenZeppelin Contracts v5.3.0 `ERC20`, vendored under `lib/`. The constructor
///      takes no arguments and makes no external calls, so it deploys on an empty chain and the
///      launch manifest records it with an empty `constructorArgs`.
contract CompanyToken is ERC20 {
    /// @notice Token name, as returned by `name()`.
    string public constant TOKEN_NAME = "Company.md";

    /// @notice Token symbol, as returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "COMD";

    /// @notice Decimals, as returned by `decimals()`. OpenZeppelin's default is 18 and is not overridden.
    uint8 public constant TOKEN_DECIMALS = 18;

    /// @notice The entire supply in minor units: 1,000,000,000 tokens with 18 decimals.
    ///         Minted once to the deployer; `totalSupply()` equals this forever.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** uint256(TOKEN_DECIMALS);

    /// @notice Mints `INITIAL_SUPPLY` to `msg.sender`. Under the IMD launch `msg.sender` is the
    ///         ProjectFactory, which distributes the supply from there.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
