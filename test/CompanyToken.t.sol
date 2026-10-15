// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CompanyToken} from "../src/CompanyToken.sol";

/// @notice Stands in for the launch factory: deploys the token so that `msg.sender` in the
///         constructor is a contract, and forwards transfers on request, as the factory does.
contract DeployerProbe {
    CompanyToken public token;

    function deploy() external returns (CompanyToken deployed) {
        deployed = new CompanyToken();
        token = deployed;
    }

    function send(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract CompanyTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    CompanyToken internal token;
    DeployerProbe internal deployer;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = new DeployerProbe();
        token = deployer.deploy();
    }

    // ---------------------------------------------------------------------------------------
    // Metadata and supply
    // ---------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "Company.md");
        assertEq(token.symbol(), "COMD");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "Company.md");
        assertEq(token.TOKEN_SYMBOL(), "COMD");
        assertEq(token.TOKEN_DECIMALS(), 18);
    }

    function test_supplyConstantMatchesBrief() public view {
        // 1,000,000,000 with 18 decimals, written out in full.
        assertEq(token.INITIAL_SUPPLY(), 1_000_000_000_000_000_000_000_000_000);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    function test_mintsWholeSupplyToDeployerOnce() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(deployer)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        // Fresh deployment from this test so the expectation sees the constructor's event.
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(this), SUPPLY);
        CompanyToken fresh = new CompanyToken();
        assertEq(fresh.balanceOf(address(this)), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_deployerIsMsgSenderNotTxOrigin() public {
        // The probe deployed the token: it, not the test's EOA origin, holds the supply.
        vm.prank(alice, alice);
        DeployerProbe other = new DeployerProbe();
        vm.prank(alice, alice);
        CompanyToken fresh = other.deploy();
        assertEq(fresh.balanceOf(address(other)), SUPPLY);
        assertEq(fresh.balanceOf(alice), 0);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    // ---------------------------------------------------------------------------------------
    // Transfers: success
    // ---------------------------------------------------------------------------------------

    function test_transferMovesExactAmount() public {
        assertTrue(deployer.send(alice, 1_000 ether));
        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.balanceOf(address(deployer)), SUPPLY - 1_000 ether);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 400 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 400 ether));

        assertEq(token.balanceOf(alice), 600 ether);
        assertEq(token.balanceOf(bob), 400 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWholeBalanceAndZeroAmount() public {
        deployer.send(alice, 5 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 5 ether));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 5 ether);

        // Zero-value transfers are allowed by ERC-20 and change nothing.
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 5 ether);
    }

    function test_transferToSelfKeepsBalance() public {
        deployer.send(alice, 7 ether);
        vm.prank(alice);
        assertTrue(token.transfer(alice, 7 ether));
        assertEq(token.balanceOf(alice), 7 ether);
    }

    function test_launchFlowsMoveExactly() public {
        // Mirrors the launch: 10% to a distributor, a claim out of it, 80% toward the pool
        // seeder, the remaining 10% to the requester. No fee, no rounding, nothing lost.
        address distributor = makeAddr("distributor");
        address claimant = makeAddr("claimant");
        address poolManager = makeAddr("poolManager");
        address requester = makeAddr("requester");

        uint256 swarm = SUPPLY / 10;
        uint256 pool = (SUPPLY * 8_000) / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        assertTrue(deployer.send(distributor, swarm));
        assertTrue(deployer.send(poolManager, pool));
        assertTrue(deployer.send(requester, remainder));
        assertEq(token.balanceOf(address(deployer)), 0);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));

        assertEq(token.balanceOf(claimant), swarm);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.balanceOf(requester), remainder);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------------------------------
    // Transfers: failure
    // ---------------------------------------------------------------------------------------

    function test_transferRevertsOnInsufficientBalance() public {
        deployer.send(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 10 ether + 1)
        );
        token.transfer(bob, 10 ether + 1);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, carol, 0, 1));
        token.transfer(bob, 1);
    }

    function test_transferToZeroAddressReverts() public {
        deployer.send(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------------------------------
    // Allowances: success
    // ---------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(alice, bob, 123);
        vm.prank(alice);
        assertTrue(token.approve(bob, 123));
        assertEq(token.allowance(alice, bob), 123);

        // Re-approving overwrites rather than accumulates.
        vm.prank(alice);
        token.approve(bob, 5);
        assertEq(token.allowance(alice, bob), 5);
    }

    function test_transferFromSpendsAllowance() public {
        deployer.send(alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 60 ether);

        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 40 ether));

        assertEq(token.balanceOf(alice), 60 ether);
        assertEq(token.balanceOf(carol), 40 ether);
        assertEq(token.allowance(alice, bob), 20 ether);
    }

    function test_transferFromWithMaxAllowanceDoesNotDecrease() public {
        deployer.send(alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.transferFrom(alice, carol, 30 ether);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(carol), 30 ether);
    }

    // ---------------------------------------------------------------------------------------
    // Allowances: failure
    // ---------------------------------------------------------------------------------------

    function test_transferFromRevertsOnInsufficientAllowance() public {
        deployer.send(alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 10 ether, 10 ether + 1)
        );
        token.transferFrom(alice, carol, 10 ether + 1);
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function test_transferFromWithoutApprovalReverts() public {
        deployer.send(alice, 100 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(alice, carol, 1);
    }

    function test_transferFromRevertsWhenOwnerBalanceTooLow() public {
        deployer.send(alice, 5 ether);
        vm.prank(alice);
        token.approve(bob, 50 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        token.transferFrom(alice, carol, 6 ether);
    }

    function test_approveZeroSpenderReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    // ---------------------------------------------------------------------------------------
    // No privileged surface: nothing mints, pauses, freezes or seizes
    // ---------------------------------------------------------------------------------------

    function test_noAdminCallIncreasesSupply() public {
        address attacker = makeAddr("attacker");
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(address(deployer));
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
        }
    }

    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        deployer.send(alice, SUPPLY / 1_000);
        uint256 held = token.balanceOf(alice);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            vm.prank(address(deployer));
            (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], alice, true));
            assertFalse(ok, signatures[i]);
        }
        // The deployer has no allowance, so it cannot pull from the holder either.
        vm.prank(address(deployer));
        (bool moved,) = address(token).call(abi.encodeWithSelector(IERC20.transferFrom.selector, alice, deployer, 1));
        assertFalse(moved);
        assertEq(token.balanceOf(alice), held);

        vm.prank(alice);
        assertTrue(token.transfer(bob, held / 2));
        assertEq(token.balanceOf(bob), held / 2);
    }

    function test_unknownSelectorAndPlainEtherReverts() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok, "no fallback");
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (ok,) = address(token).call{value: 1 wei}("");
        assertFalse(ok, "no receive");
        assertEq(address(token).balance, 0);
    }

    // ---------------------------------------------------------------------------------------
    // Fuzz: conservation of supply
    // ---------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(deployer));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(deployer.send(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(address(deployer)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 funded, uint256 excess) public {
        funded = bound(funded, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - funded);
        deployer.send(alice, funded);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funded, funded + excess)
        );
        token.transfer(bob, funded + excess);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowanceAmount, uint256 spend) public {
        allowanceAmount = bound(allowanceAmount, 0, SUPPLY);
        spend = bound(spend, 0, SUPPLY);
        deployer.send(alice, SUPPLY);
        vm.prank(alice);
        token.approve(bob, allowanceAmount);

        vm.prank(bob);
        if (spend > allowanceAmount) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, allowanceAmount, spend)
            );
            token.transferFrom(alice, carol, spend);
        } else {
            assertTrue(token.transferFrom(alice, carol, spend));
            assertEq(token.balanceOf(carol), spend);
            assertEq(token.allowance(alice, bob), allowanceAmount - spend);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
