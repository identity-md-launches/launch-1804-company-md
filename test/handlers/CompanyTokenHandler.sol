// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CompanyToken} from "src/CompanyToken.sol";

/// @notice Closed actor set: every successful transfer stays among these five holders.
/// @dev Expected balances come from the initial allocation plus a journal of requested transfers,
///      never from token.balanceOf. Approvals are similarly tracked from requested values.
contract CompanyTokenHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant ACTOR_COUNT = 5;
    CompanyToken public immutable token;
    address[5] public actors;

    mapping(address => uint256) public initialBalance;
    mapping(address => uint256) public sent;
    mapping(address => uint256) public received;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    uint256 public transfers;
    uint256 public delegatedTransfers;
    uint256 public positiveTransfers;
    uint256 public approvals;
    uint256 public rejectedCalls;

    constructor() {
        token = new CompanyToken();
        actors[0] = address(this); // The constructor's actual deployer remains a tested holder.
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant carol");
        actors[4] = makeAddr("invariant dave");

        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        initialBalance[address(this)] = SUPPLY;
        for (uint256 i = 1; i < ACTOR_COUNT; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / ACTOR_COUNT));
            _recordTransfer(address(this), actors[i], SUPPLY / ACTOR_COUNT);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), _amount(amountSeed, expectedBalance(from)));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        // Exercise revocation, infinite approvals, small finite approvals and the whole uint256 domain.
        uint256 mode = amountSeed % 4;
        uint256 amount =
            mode == 0 ? 0 : mode == 1 ? type(uint256).max : mode == 2 ? bound(amountSeed, 0, SUPPLY) : amountSeed;
        _approve(owner, _actor(spenderSeed), amount);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), 0);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 limit = expectedBalance(owner);
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed < limit) limit = allowed;
        _transferFrom(owner, spender, _actor(toSeed), _amount(amountSeed, limit));
    }

    /// @dev Ensures meaningful delegated transfers are reachable even before a random approve action.
    function approveAndTransferFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(amountSeed, expectedBalance(owner));
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _transferFrom(owner, spender, _actor(toSeed), amount);
    }

    function rejectOverdraft(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance(from);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(_actor(toSeed), amount);
        ++rejectedCalls;
    }

    function rejectOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = bound(amountSeed, 0, SUPPLY);
        _approve(owner, spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, _actor(toSeed), allowed + 1);
        ++rejectedCalls;
    }

    function rejectDelegatedOverdraft(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = expectedBalance(owner);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, _actor(toSeed), amount);
        // The model does not spend any allowance on a reverted transfer.
        ++rejectedCalls;
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(amountSeed, expectedBalance(owner));
        if (delegated) {
            _approve(owner, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
        ++rejectedCalls;
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(_actor(ownerSeed));
        token.approve(address(0), amount);
        ++rejectedCalls;
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 amount = _amount(amountSeed, expectedBalance(from));
        _transfer(from, to, amount);
        _transfer(to, from, amount);
        assertEq(token.balanceOf(from), fromBefore, "round trip changed sender balance");
        assertEq(token.balanceOf(to), toBefore, "round trip changed recipient balance");
    }

    function expectedBalance(address owner) public view returns (uint256) {
        return initialBalance[owner] + received[owner] - sent[owner];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, ACTOR_COUNT - 1)];
    }

    function _amount(uint256 seed, uint256 limit) internal pure returns (uint256) {
        uint256 mode = seed % 4;
        if (mode == 0) return 0;
        if (mode == 1) return limit == 0 ? 0 : 1;
        if (mode == 2) return limit;
        return bound(seed, 0, limit);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approval returned false");
        expectedAllowance[owner][spender] = amount;
        ++approvals;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "transfer returned false");
        _recordTransfer(from, to, amount);
        ++transfers;
        if (amount != 0) ++positiveTransfers;
    }

    function _transferFrom(address owner, address spender, address to, uint256 amount) internal {
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "transferFrom returned false");
        _recordTransfer(owner, to, amount);
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] = allowed - amount;
        ++delegatedTransfers;
        if (amount != 0) ++positiveTransfers;
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        sent[from] += amount;
        received[to] += amount;
    }
}
