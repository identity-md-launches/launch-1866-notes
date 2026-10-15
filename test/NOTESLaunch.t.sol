// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {NOTES} from "../src/NOTES.sol";

/// @dev Test-only contract actor; it is not a production factory or an AMM.
contract TokenAccount {
    function deploy(bytes32 salt) external returns (NOTES) {
        return new NOTES{salt: salt}();
    }

    function send(NOTES token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }

    function pull(NOTES token, address from, uint256 amount) external returns (bool) {
        return token.transferFrom(from, address(this), amount);
    }
}

contract NOTESLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    TokenAccount private factory;
    NOTES private token;

    function setUp() public {
        factory = new TokenAccount();
        token = factory.deploy(keccak256("NOTES launch test"));
    }

    function test_Create2FactoryReceivesAllSupply() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_LaunchDistributionClaimsAndPoolCustodyTransferExactAmounts() public {
        TokenAccount distributor = new TokenAccount();
        TokenAccount poolCustodian = new TokenAccount();
        address recipient = makeAddr("launch remainder recipient");
        address claimant = makeAddr("contributor claimant");
        address trader = makeAddr("ordinary trader");

        uint256 swarm = SUPPLY * 10 / 100;
        uint256 pool = SUPPLY * 88 / 100;
        uint256 remainder = SUPPLY * 2 / 100;
        assertTrue(factory.send(token, address(distributor), swarm));
        assertTrue(factory.send(token, address(poolCustodian), pool));
        assertTrue(factory.send(token, recipient, remainder));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(address(distributor)), swarm);
        assertEq(token.balanceOf(address(poolCustodian)), pool);
        assertEq(token.balanceOf(recipient), remainder);

        assertTrue(distributor.send(token, claimant, swarm));
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(token.balanceOf(claimant), swarm);

        uint256 tradeAmount = 123 * 1e18;
        assertTrue(poolCustodian.send(token, trader, tradeAmount));
        assertEq(token.balanceOf(trader), tradeAmount);
        assertEq(token.balanceOf(address(poolCustodian)), pool - tradeAmount);
        vm.prank(trader);
        assertTrue(token.transfer(address(poolCustodian), tradeAmount));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(address(poolCustodian)), pool);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(
            token.balanceOf(claimant) + token.balanceOf(address(poolCustodian)) + token.balanceOf(recipient), SUPPLY
        );
    }

    function test_FactoryNeedsHolderApprovalAfterDistribution() public {
        address holder = makeAddr("holder");
        assertTrue(factory.send(token, holder, 100));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, 1)
        );
        factory.pull(token, holder, 1);
        assertEq(token.balanceOf(holder), 100);

        vm.prank(holder);
        token.approve(address(factory), 1);
        assertTrue(factory.pull(token, holder, 1));
        assertEq(token.balanceOf(holder), 99);
        assertEq(token.allowance(holder, address(factory)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
