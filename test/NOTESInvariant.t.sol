// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {NOTES} from "../src/NOTES.sol";

/// @dev Drives transfers and approvals between a closed set of holders while tracking a reference ledger.
contract NOTESHandler is Test {
    NOTES private immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(NOTES token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1_000_000_000 * 1e18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 available = expectedBalance[owner];
        uint256 allowed = expectedAllowance[owner][spender];
        amount = bound(amount, 0, available < allowed ? available : allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    function rejectedOverdraw(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        vm.prank(from);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.transfer, (to, balance + 1)));
        assertFalse(success, "overdraw succeeded");
        assertEq(
            reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1)
        );
    }

    function rejectedOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed == type(uint256).max) return;
        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, allowed + 1)));
        assertFalse(success, "overspend succeeded");
        assertEq(
            reason,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
    }

    /// @dev Force transitions to revoked, unlimited and small finite approvals;
    /// unrestricted uint256 fuzzing alone rarely revisits these states.
    function changeApproval(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint256 mode) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        mode %= 3;
        amount = mode == 0 ? 0 : mode == 1 ? type(uint256).max : bound(amount, 0, 1_000_000_000 * 1e18);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    /// @dev Sufficient approval isolates the balance check. The reverted spend
    /// must roll back any attempted allowance deduction as well as balances.
    function rejectedDelegatedOverdraw(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amount,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max);
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;

        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        assertFalse(success, "delegated overdraw succeeded");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        assertEq(token.allowance(owner, spender), approved, "failed transfer consumed approval");
    }

    function rejectedZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 available = expectedBalance[owner];
        uint256 allowed = expectedAllowance[owner][spender];
        if (delegated && allowed < available) available = allowed;
        amount = bound(amount, 0, available);
        bytes memory data = delegated
            ? abi.encodeCall(token.transferFrom, (owner, address(0), amount))
            : abi.encodeCall(token.transfer, (address(0), amount));
        vm.prank(delegated ? spender : owner);
        (bool success, bytes memory reason) = address(token).call(data);
        assertFalse(success, "zero receiver accepted");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
    }

    function rejectedZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.prank(owner);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.approve, (address(0), amount)));
        assertFalse(success, "zero spender accepted");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract NOTESInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    NOTES private token;
    NOTESHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new NOTES();
        actors = [address(this), makeAddr("holder one"), makeAddr("holder two"), makeAddr("holder three")];
        handler = new NOTESHandler(token, actors);

        // Fund every actor and seed approvals so the campaign can exercise
        // nonzero delegated transfers from its first random operation.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, SUPPLY / actors.length);
        }
        for (uint256 i; i < actors.length; ++i) {
            handler.approve(i, (i + 1) % actors.length, SUPPLY / 8);
        }
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.rejectedOverdraw.selector;
        selectors[4] = handler.rejectedOverspend.selector;
        selectors[5] = handler.changeApproval.selector;
        selectors[6] = handler.rejectedDelegatedOverdraw.selector;
        selectors[7] = handler.rejectedZeroReceiver.selector;
        selectors[8] = handler.rejectedZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyAndBalancesMatchReferenceLedger() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.name(), "NOTES");
        assertEq(token.symbol(), "NOTES");
        assertEq(token.decimals(), 18);
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_AllowancesMatchReferenceLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }

    /// @dev Solvency alone would miss frozen funds. After every random sequence,
    /// each actor must be able to move its entire balance and receive it back.
    function afterInvariant() public {
        for (uint256 i; i < actors.length; ++i) {
            address owner = actors[i];
            address recipient = actors[(i + 1) % actors.length];
            uint256 amount = handler.expectedBalance(owner);
            uint256 recipientBefore = handler.expectedBalance(recipient);
            vm.prank(owner);
            assertTrue(token.transfer(recipient, amount));
            assertEq(token.balanceOf(owner), 0);
            assertEq(token.balanceOf(recipient), recipientBefore + amount);

            vm.prank(recipient);
            assertTrue(token.transfer(owner, amount));
            assertEq(token.balanceOf(owner), amount);
            assertEq(token.balanceOf(recipient), recipientBefore);
        }
        invariant_SupplyAndBalancesMatchReferenceLedger();
        invariant_AllowancesMatchReferenceLedger();
    }
}
