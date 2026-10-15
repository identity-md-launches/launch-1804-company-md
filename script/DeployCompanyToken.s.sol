// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {CompanyToken} from "../src/CompanyToken.sol";

/// @title Deploy script for Company.md (COMD)
/// @notice Reference deployment for local or manual use. The IMD launch does not run this script:
///         the factory deploys the token from its creation code with no constructor arguments.
///         The token has no configuration, so there is nothing to read from the environment.
contract DeployCompanyToken is Script {
    /// @notice Deploys the token. Whoever calls this (the broadcaster under `run()`, or the test
    ///         contract directly) receives the whole supply.
    function deploy() public returns (CompanyToken token) {
        token = new CompanyToken();
    }

    /// @notice Broadcast entry point: `forge script script/DeployCompanyToken.s.sol --broadcast`.
    function run() external returns (CompanyToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
