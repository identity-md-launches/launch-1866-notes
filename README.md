# NOTES

NOTES is a fixed-supply ERC-20. Its constructor mints **1,000,000,000 NOTES** with **18 decimals** to the immediate deployer. In the intended launch, that deployer is the factory.

## Contract and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `NOTES` |
| Source | `src/NOTES.sol` |
| Name / symbol | `NOTES` / `NOTES` |
| Decimals | `18` |
| Supply in whole tokens | `1000000000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Deployment value | `0` |
| Initial recipient | Constructor `msg.sender` |
| Application contracts | None |
| Owner, initialization, linked libraries | None |
| Intended launch chain | Robinhood Chain, chain ID `4663`, as specified by the assignment |

`INITIAL_SUPPLY` is the named constant for the constructor issuance. The deployed runtime has no callable mint or burn function. Neither the deployer nor any other account can increase supply, seize balances, freeze transfers, change metadata, or upgrade the implementation.

The constructor performs no external calls and needs no pre-existing chain contracts. Deploy the creation bytecode in `out/NOTES.sol/NOTES.json` directly through the authorized launch factory, with no appended constructor arguments. Deploying through any other helper would give that helper the entire supply, so the immediate deployer must be able to distribute its tokens. The source artifact is `src/NOTES.sol:NOTES`.

The separate launch process creates the manifest and submits transactions. This project does not contain a manifest, private keys, RPC configuration, or a broadcast script.

## Behavior and assumptions

- Transfers move exactly the requested number of base units. There are no transfer fees, rebases, vesting rules, or special pool/distributor exemptions.
- Successful `transfer`, `approve`, and `transferFrom` calls return `true`. Invalid recipients, insufficient balances, and insufficient allowances revert with OpenZeppelin ERC-20 custom errors.
- Zero-value transfers between nonzero addresses are valid and emit `Transfer`. Transfers to the zero address revert, including zero-value transfers. Self-transfers preserve balances and still check available funds.
- `approve` replaces the caller's allowance. A finite allowance decreases on `transferFrom`; `type(uint256).max` acts as unlimited allowance and is not decreased. Delegated self-transfers still require and spend finite allowance.
- The constructor emits one `Transfer(address(0), deployer, INITIAL_SUPPLY)`. Transfers emit `Transfer`, and explicit approvals emit `Approval`. In the vendored implementation, spending an allowance does not emit an additional `Approval`; integrations should read `allowance` when they need its current value.
- There are no recipient callbacks, oracle dependencies, signatures, or time/block-based rules. Token behavior does not depend on a chain's block timing or sequencer ordering.
- No owner or recovery function exists. Tokens sent to the token contract itself, or to another address unable to send them, cannot be recovered by an administrator. Ordinary native-currency payments revert; forcibly received native currency also has no withdrawal path.

## Launch handoff

These values are supplied by the assignment for the separate factory/manifest process. They are not constructor arguments or token transfer rules:

| Launch setting | Supplied value |
| --- | --- |
| Pair currency | IMD at `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127`, 18 decimals |
| Pool fee / tick spacing | `12500` (1.25%) / `60` |
| Pool initial price provenance | `79228162514264337593543950336` |
| `economics.poolBps` | `8800` |
| `economics.initialMarketCapWei` | `2500000000000000000000` |
| `economics.remainderTo` | `0x380fbf99a903253e14b9eb797807b4b92cd4b019` |

The factory receives the whole supply first. The launch policy then distributes 10% to its MerkleDistributor, allocates 88% to pool seeding, and sends the remaining 2% to the specified recipient. The launch deployer derives the actual opening pool price from the initial market cap, supply, and currency ordering. None of these allocations or pool settings is implemented inside NOTES; the token charges no fee on any of those transfers.

## Build and verification

Requires Foundry and Solidity **0.8.26**. All Solidity dependencies are vendored as ordinary files under `lib/`; no dependency download, package installation, submodule, environment configuration, FFI, or filesystem cheatcode permission is required. The compiler must already be installed for a build without network access.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x44209e6bccbc617b18caede613b37b570071687aad64a0019347522e66ab4359 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, the optimizer at 200 runs, and `bytecode_hash = "none"`. Fuzz tests use 512 cases each. Stateful invariant tests use 128 runs of up to 64 operations. Tests use isolated local fixtures and no environment-reading or environment-writing cheatcodes, forks, RPCs, or filesystem operations.

Tests cover constructor issuance and its event, direct and CREATE2 factory deployment, exact transfers, approvals and revocation, delegated transfers, infinite allowances, zero/self transfers, failure rollback, rejected administrative calls, runtime opcode restrictions, launch allocation/claim/custody transfers, and a reference ledger for randomized sequences of successful and rejected operations.

`test/NOTESLaunch.t.sol` uses test-only contract accounts to check token movements. It does not simulate AMM pricing or run the supplied network's full Uniswap v4 harness. That protected harness depends on launch infrastructure and resolved manifest values supplied by the independent verifier. Local checks do not establish that a launch has been deployed or independently audited.

Dependency versions, immutable upstream commits, and SHA-256 hashes of every vendored file are recorded in `DEPENDENCIES.json`. Production code uses the unmodified ERC-20 dependency subset from OpenZeppelin Contracts v5.0.2; tests use forge-std v1.9.7. Their licenses are preserved alongside their source. Formatting excludes vendored files to retain their upstream hashes.

## After launch

There are no owner-settable settings, initialization calls, privileged keys, or keeper jobs for NOTES.

The launch operator is responsible for checking the chain and deployed artifact, verifying the source on the chain's explorer, checking name/symbol/decimals/supply, and confirming the factory's distribution and liquidity setup. The distributor and pool are operated by the launch infrastructure, independently of the token. Independent security review remains part of the launch process; local unit, fuzz, and invariant tests are not a substitute for it. Slither and Mythril are not part of this project's local checks.

Holders are responsible for securing their wallets and managing approvals. Allowance replacement has the standard ERC-20 transaction-ordering risk: a spender may spend the old allowance before a replacement transaction is included. Applications should use limited approvals and handle revocation/replacement deliberately.
