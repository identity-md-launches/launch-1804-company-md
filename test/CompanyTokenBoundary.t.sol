// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CompanyToken} from "src/CompanyToken.sol";

/// @notice Boundary cases and algebraic properties supplementing the original deployment suite.
/// forge-config: default.fuzz.runs = 1000
contract CompanyTokenBoundaryTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    CompanyToken internal token;
    address internal alice = makeAddr("boundary alice");
    address internal bob = makeAddr("boundary bob");
    address internal carol = makeAddr("boundary carol");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new CompanyToken();
    }

    function test_constructorLogsExactlyOneMint() public {
        vm.recordLogs();
        CompanyToken fresh = new CompanyToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "constructor must mint exactly once");
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_oneWeiAndEntireSupplyCanRoundTrip() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransfersFromEmptyAccountEmitEvents() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, carol, 0);
        vm.prank(alice);
        assertTrue(token.transfer(carol, 0));

        // No approval is needed to spend zero, even when both balances are empty.
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, carol, 0);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 0));
        _assertBalances(0, 0, 0);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_zeroTransferToZeroAddressStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transfer(address(0), 0);
        _assertBalances(0, 0, 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_zeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(alice);
        token.approve(address(0), 0);
        assertEq(token.allowance(alice, address(0)), 0);
        _assertBalances(0, 0, 0);
    }

    function test_transferFromZeroOwnerCannotMintEvenZero() public {
        // Only rejection is required here: error precedence is not an ERC-20 guarantee.
        vm.expectRevert();
        vm.prank(bob);
        token.transferFrom(address(0), carol, 0);
        vm.expectRevert();
        vm.prank(bob);
        token.transferFrom(address(0), carol, 1);
        _assertBalances(0, 0, 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(alice, 2);
        _assertBalances(1, 0, 0);
    }

    function test_maximumTransferAmountRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        _assertBalances(0, 0, 0);
    }

    function test_maximumTransferFromRevertsAndKeepsInfiniteApproval() public {
        token.transfer(alice, SUPPLY);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, SUPPLY, type(uint256).max)
        );
        vm.prank(bob);
        token.transferFrom(alice, carol, type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    function test_maximumMinusOneApprovalIsFinite() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(bob, type(uint256).max - 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 1));
        assertEq(token.allowance(alice, bob), type(uint256).max - 2);
        _assertBalances(0, 0, 1);
    }

    function test_exhaustedAllowanceCannotBeSpentTwice() public {
        token.transfer(alice, 11);
        vm.prank(alice);
        token.approve(bob, 10);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 10));
        assertEq(token.allowance(alice, bob), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, carol, 1);
        _assertBalances(1, 0, 10);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_revokingInfiniteApprovalImmediatelyStopsSpending() public {
        token.transfer(alice, 2);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.approve(bob, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, carol, 1);
        _assertBalances(1, 0, 1);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_ownerUsingTransferFromNeedsItsOwnAllowance() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, carol, 1);
        _assertBalances(1, 0, 0);

        vm.prank(alice);
        assertTrue(token.approve(alice, 1));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, carol, 1));
        _assertBalances(0, 0, 1);
        assertEq(token.allowance(alice, alice), 0);
    }

    function test_approvalDoesNotAuthorizeAnotherSpender() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, carol, 0, 1));
        vm.prank(carol);
        token.transferFrom(alice, carol, 1);
        _assertBalances(1, 0, 0);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.allowance(alice, carol), 0);
    }

    function test_approvalBeforeFundingCanBeUsedAfterFunding() public {
        vm.prank(alice);
        assertTrue(token.approve(bob, SUPPLY));
        _assertBalances(0, 0, 0);
        token.transfer(alice, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, carol, SUPPLY);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, SUPPLY));
        _assertBalances(0, 0, SUPPLY);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_transferToTokenContractIsNotABurn() public {
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testFuzz_transferRoundTripRestoresBalances(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        _assertBalances(0, 0, 0);
    }

    function testFuzz_splitTransferEqualsSingleTransfer(uint256 amount, uint256 first) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        CompanyToken single = new CompanyToken();
        assertTrue(single.transfer(alice, amount));
        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, amount - first));
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalReplacementIsIdempotentAndIsolated(uint256 original, uint256 replacement) public {
        vm.startPrank(alice);
        assertTrue(token.approve(carol, original));
        assertTrue(token.approve(bob, original));
        assertTrue(token.approve(bob, replacement));
        assertTrue(token.approve(bob, replacement));
        vm.stopPrank();
        assertEq(token.allowance(alice, bob), replacement);
        assertEq(token.allowance(alice, carol), original);
        assertEq(token.allowance(bob, alice), 0);
        assertEq(token.allowance(carol, bob), 0);
        _assertBalances(0, 0, 0);
    }

    function testFuzz_transferFromInsufficientBalanceRollsBackAllowance(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(bob, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(bob);
        token.transferFrom(alice, carol, amount);
        _assertBalances(balance, 0, 0);
        assertEq(token.allowance(alice, bob), amount, "failed spending consumed an allowance");
    }

    function testFuzz_insufficientAllowanceLeavesAllStateUnchanged(uint256 balance, uint256 allowed, uint256 amount)
        public
    {
        balance = bound(balance, 1, SUPPLY);
        allowed = bound(allowed, 0, balance - 1);
        amount = bound(amount, allowed + 1, balance);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(bob, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, allowed, amount));
        vm.prank(bob);
        token.transferFrom(alice, carol, amount);
        _assertBalances(balance, 0, 0);
        assertEq(token.allowance(alice, bob), allowed);
    }

    function testFuzz_zeroRecipientRollsBackDelegatedTransfer(uint256 amount, uint256 allowed) public {
        amount = bound(amount, 0, SUPPLY);
        allowed = bound(allowed, amount, type(uint256).max);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.approve(bob, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(bob);
        token.transferFrom(alice, address(0), amount);
        _assertBalances(amount, 0, 0);
        assertEq(token.allowance(alice, bob), allowed);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testFuzz_delegatedSelfTransferOnlySpendsAllowance(uint256 balance, uint256 amount, uint256 allowed)
        public
    {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, 0, balance);
        allowed = bound(allowed, amount, type(uint256).max);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(bob, allowed);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, alice, amount);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, alice, amount));
        _assertBalances(balance, 0, 0);
        assertEq(token.allowance(alice, bob), allowed == type(uint256).max ? allowed : allowed - amount);
    }

    function testFuzz_splitDelegatedSpendingMatchesTotal(uint256 amount, uint256 first, uint256 allowed) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        allowed = bound(allowed, amount, type(uint256).max);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.approve(bob, allowed);
        vm.startPrank(bob);
        assertTrue(token.transferFrom(alice, carol, first));
        assertTrue(token.transferFrom(alice, carol, amount - first));
        vm.stopPrank();
        _assertBalances(0, 0, amount);
        assertEq(token.allowance(alice, bob), allowed == type(uint256).max ? allowed : allowed - amount);
    }

    function _assertBalances(uint256 aliceBalance, uint256 bobBalance, uint256 carolBalance) internal view {
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(carol), carolBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance - carolBalance);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
