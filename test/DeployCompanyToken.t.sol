// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CompanyToken} from "../src/CompanyToken.sol";
import {DeployCompanyToken} from "../script/DeployCompanyToken.s.sol";

contract DeployCompanyTokenTest is Test {
    function test_deployMintsSupplyToTheDeployingContract() public {
        DeployCompanyToken deployer = new DeployCompanyToken();
        CompanyToken token = deployer.deploy();
        // Called without a broadcast, the script contract is `msg.sender` in the constructor.
        assertEq(token.totalSupply(), token.INITIAL_SUPPLY());
        assertEq(token.balanceOf(address(deployer)), token.INITIAL_SUPPLY());
        assertEq(token.name(), "Company.md");
        assertEq(token.symbol(), "COMD");
        assertEq(token.decimals(), 18);
    }

    function test_twoDeploymentsAreIndependent() public {
        DeployCompanyToken deployer = new DeployCompanyToken();
        CompanyToken first = deployer.deploy();
        CompanyToken second = deployer.deploy();
        assertTrue(address(first) != address(second));
        assertEq(first.totalSupply(), second.totalSupply());
        assertEq(first.balanceOf(address(deployer)), first.INITIAL_SUPPLY());
        assertEq(second.balanceOf(address(deployer)), second.INITIAL_SUPPLY());
    }
}
