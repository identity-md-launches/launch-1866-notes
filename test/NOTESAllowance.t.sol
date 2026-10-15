// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {NOTES} from "../src/NOTES.sol";

/// @notice Regression properties for approval lifecycles and independent failure conditions.
/// forge-config: default.fuzz.runs = 1000
contract NOTESAllowanceTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    NOTES private token;
    address private alice;
    address private bob;
    address private spender;
    address private otherSpender;

    function setUp() public {
        token = new NOTES();
        alice = makeAddr("allowance holder");
        bob = makeAddr("allowance recipient");
        spender = makeAddr("first operator");
        otherSpender = makeAddr("second operator");
    }

    function test_OneBaseUnitMovesDirectlyAndWithAllowance() public {
        assertTrue(token.transfer(alice, 1));
        _assertHoldings(1, 0);
        _approve(1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        _assertHoldings(0, 1);
    }

    function test_MaximumFiniteAllowanceIsDecremented() public {
        token.transfer(alice, 1);
        _approve(type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), type(uint256).max - 2);
        _assertHoldings(0, 1);
    }

    function test_UnlimitedApprovalCanBeReducedRevokedAndGrantedAgain() public {
        token.transfer(alice, 100);
        _approve(type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 7));
        assertEq(token.allowance(alice, spender), type(uint256).max);

        _approve(4);
        assertEq(token.allowance(alice, spender), 4);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 3);

        _approve(0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        _assertHoldings(92, 8);

        _approve(2);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 2));
        assertEq(token.allowance(alice, spender), 0);
        _assertHoldings(90, 10);
    }

    function test_ExhaustedAllowanceDoesNotResetWhenHolderIsFundedAgain() public {
        token.transfer(alice, 1);
        _approve(1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));

        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        _assertHoldings(1, 1);
    }

    function test_HolderNeedsSelfApprovalToUseTransferFrom() public {
        token.transfer(alice, 5);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        _assertHoldings(5, 0);

        vm.prank(alice);
        assertTrue(token.approve(alice, 5));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, bob, 5));
        assertEq(token.allowance(alice, alice), 0);
        _assertHoldings(0, 5);
    }

    function test_ApprovalBeforeFundingCanBeUsedAfterFunding() public {
        _approve(5);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 5));
        vm.prank(spender);
        token.transferFrom(alice, bob, 5);
        assertEq(token.allowance(alice, spender), 5);
        _assertHoldings(0, 0);

        token.transfer(alice, 5);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 5));
        assertEq(token.allowance(alice, spender), 0);
        _assertHoldings(0, 5);
    }

    function test_ZeroTransfersPreserveFiniteAndInfiniteApprovals() public {
        uint256[2] memory approvals = [uint256(1), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            _approve(approvals[i]);
            vm.prank(alice);
            assertTrue(token.transfer(bob, 0));
            vm.prank(spender);
            assertTrue(token.transferFrom(alice, bob, 0));
            vm.prank(spender);
            assertTrue(token.transferFrom(alice, alice, 0));
            assertEq(token.allowance(alice, spender), approvals[i]);
            _assertHoldings(0, 0);
        }
    }

    function test_MaximumTransferAmountsRevertWithoutOverflow() public {
        token.transfer(alice, SUPPLY);
        _approve(type(uint256).max);
        bytes memory expected =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, SUPPLY, type(uint256).max);
        vm.expectRevert(expected);
        vm.prank(alice);
        token.transfer(bob, type(uint256).max);
        vm.expectRevert(expected);
        vm.prank(spender);
        token.transferFrom(alice, bob, type(uint256).max);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        _assertHoldings(SUPPLY, 0);
    }

    function test_ZeroReceiverRejectsZeroAmountWithFiniteAndInfiniteApproval() public {
        token.transfer(alice, 1);
        bytes memory expected = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        vm.expectRevert(expected);
        vm.prank(alice);
        token.transfer(address(0), 0);

        uint256[2] memory approvals = [uint256(1), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            _approve(approvals[i]);
            vm.expectRevert(expected);
            vm.prank(spender);
            token.transferFrom(alice, address(0), 0);
            assertEq(token.allowance(alice, spender), approvals[i]);
            _assertHoldings(1, 0);
        }
    }

    function testFuzz_PartiallyFundedHolderCannotOverdraw(uint256 funding, uint256 amount, bool selfTransfer) public {
        funding = bound(funding, 0, SUPPLY);
        amount = bound(amount, funding + 1, type(uint256).max);
        token.transfer(alice, funding);
        _approve(type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funding, amount));
        vm.prank(alice);
        token.transfer(selfTransfer ? alice : bob, amount);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        _assertHoldings(funding, 0);
    }

    function testFuzz_DelegatedOverdrawPreservesApproval(
        uint256 funding,
        uint256 amount,
        bool unlimited,
        bool selfTransfer
    ) public {
        funding = bound(funding, 0, SUPPLY);
        amount = bound(amount, funding + 1, type(uint256).max - 1);
        uint256 approved = unlimited ? type(uint256).max : amount;
        token.transfer(alice, funding);
        _approve(approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funding, amount));
        vm.prank(spender);
        token.transferFrom(alice, selfTransfer ? alice : bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        _assertHoldings(funding, 0);
    }

    function testFuzz_AllowanceFailureWithSufficientBalanceIsAtomic(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        token.transfer(alice, SUPPLY);
        _approve(approved);
        vm.prank(alice);
        token.approve(otherSpender, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.allowance(alice, otherSpender), type(uint256).max);
        _assertHoldings(SUPPLY, 0);
    }

    function testFuzz_SpendersCannotBorrowEachOthersAllowance(uint256 first, uint256 second) public {
        first = bound(first, 1, SUPPLY - 1);
        second = bound(second, 1, SUPPLY - first);
        token.transfer(alice, first + second);
        _approve(first);
        vm.prank(alice);
        assertTrue(token.approve(otherSpender, second));

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, first));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, otherSpender), second);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        _assertHoldings(second, first);
        assertEq(token.allowance(alice, otherSpender), second);

        vm.prank(otherSpender);
        assertTrue(token.transferFrom(alice, bob, second));
        assertEq(token.allowance(alice, otherSpender), 0);
        assertEq(token.allowance(alice, spender), 0);
        _assertHoldings(0, first + second);
    }

    function testFuzz_DelegatedSelfTransferConsumesOnlyAllowance(uint256 funding, uint256 approved, uint256 amount)
        public
    {
        funding = bound(funding, 0, SUPPLY);
        approved = bound(approved, 0, type(uint256).max - 1);
        amount = bound(amount, 0, funding < approved ? funding : approved);
        token.transfer(alice, funding);
        _approve(approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, amount));
        assertEq(token.allowance(alice, spender), approved - amount);
        _assertHoldings(funding, 0);
    }

    function testFuzz_SplitTransfersRoundTripWithoutFees(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(bob, second));
        _approve(type(uint256).max);
        _assertHoldings(first, second);

        vm.prank(alice);
        assertTrue(token.transfer(bob, first));
        _assertHoldings(0, first + second);
        vm.prank(bob);
        assertTrue(token.transfer(address(this), first + second));
        _assertHoldings(0, 0);
        assertEq(token.allowance(alice, spender), type(uint256).max);
    }

    function _approve(uint256 amount) private {
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(alice, spender), amount);
    }

    function _assertHoldings(uint256 aliceBalance, uint256 bobBalance) private view {
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
