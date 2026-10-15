// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CompanyToken} from "src/CompanyToken.sol";
import {CompanyTokenHandler} from "./handlers/CompanyTokenHandler.sol";

/// @notice Accounting and authorization must hold after arbitrary interleavings of valid and invalid calls.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract CompanyTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 internal constant ACTOR_COUNT = 5;
    CompanyTokenHandler internal handler;
    CompanyToken internal token;

    function setUp() public {
        handler = new CompanyTokenHandler();
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.revoke.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.approveAndTransferFrom.selector;
        selectors[5] = handler.rejectOverdraft.selector;
        selectors[6] = handler.rejectOverAllowance.selector;
        selectors[7] = handler.rejectDelegatedOverdraft.selector;
        selectors[8] = handler.rejectZeroRecipient.selector;
        selectors[9] = handler.rejectZeroSpender.selector;
        selectors[10] = handler.roundTrip.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndMetadataNeverChange() public view {
        assertEq(token.totalSupply(), SUPPLY, "fixed supply changed after deployment");
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.name(), "Company.md");
        assertEq(token.symbol(), "COMD");
        assertEq(token.decimals(), 18);
    }

    function invariant_allSupplyIsAccountedFor() public view {
        uint256 total;
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            uint256 balance = token.balanceOf(handler.actors(i));
            assertLe(balance, SUPPLY);
            total += balance;
        }
        assertEq(total, SUPPLY, "transfer lost or created tokens");
        assertEq(token.balanceOf(address(0)), 0, "zero address received tokens");
        assertEq(token.balanceOf(address(token)), 0, "unrequested token fee");
        assertEq(token.balanceOf(address(this)), 0, "unrequested transfer to test runner");
    }

    function invariant_eachBalanceMatchesTransferJournal() public view {
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            address actor = handler.actors(i);
            // This also detects incorrect recipient attribution, self-transfer inflation and
            // partial state changes on failed calls, even when aggregate supply still balances.
            assertEq(
                token.balanceOf(actor) + handler.sent(actor),
                handler.initialBalance(actor) + handler.received(actor),
                "balance does not match authorized transfers"
            );
        }
    }

    function invariant_allowancesMatchApprovalsAndSuccessfulSpending() public view {
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < ACTOR_COUNT; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance changed without approval or successful spending"
                );
            }
        }
    }

    function afterInvariant() public view {
        // No setup calls contribute to these counters. Detect an accidentally empty target campaign.
        assertGt(handler.transfers() + handler.delegatedTransfers() + handler.approvals() + handler.rejectedCalls(), 0);
    }

    function test_handlerExercisesPositiveSpendingRevocationAndRollback() public {
        handler.transfer(0, 1, 1);
        handler.approve(1, 2, 3);
        handler.transferFrom(1, 2, 3, 1);
        handler.revoke(1, 2);
        handler.transferFrom(1, 2, 3, 1); // Revoked approval permits only zero spending.
        handler.approveAndTransferFrom(3, 4, 0, 1, false);
        handler.approveAndTransferFrom(3, 4, 0, 1, true);
        handler.rejectOverdraft(0, 1, type(uint256).max);
        handler.rejectOverAllowance(1, 2, 3, 0);
        handler.rejectDelegatedOverdraft(1, 2, 3, type(uint256).max - 1, false);
        handler.rejectDelegatedOverdraft(1, 2, 3, type(uint256).max, true);
        handler.rejectZeroRecipient(1, 2, 1, false);
        handler.rejectZeroRecipient(1, 2, 1, true);
        handler.rejectZeroSpender(1, type(uint256).max);
        handler.roundTrip(0, 1, 2); // Entire current balance, then return it.

        assertGt(handler.positiveTransfers(), 0, "handler never moved value");
        assertEq(handler.delegatedTransfers(), 4);
        assertEq(handler.rejectedCalls(), 7);
        invariant_supplyAndMetadataNeverChange();
        invariant_allSupplyIsAccountedFor();
        invariant_eachBalanceMatchesTransferJournal();
        invariant_allowancesMatchApprovalsAndSuccessfulSpending();
    }
}
