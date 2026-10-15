# Company.md (COMD)

A fixed-supply ERC-20 token for an IMD custom-token launch on Ethereum mainnet (chain id 1).

| Field | Value |
|---|---|
| Solidity contract | `CompanyToken` (`src/CompanyToken.sol`) |
| `name()` | `Company.md` |
| `symbol()` | `COMD` |
| `decimals()` | `18` |
| Total supply | `1,000,000,000 COMD` = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Minted to | `msg.sender` of the constructor, once, in the constructor |
| Owner / admin | none |
| Mint after deployment | impossible: no mint function exists |
| Transfer fee, tax, burn, reflection | none |
| Pause, blocklist, freeze, seize | none |
| Upgradeability, delegatecall, selfdestruct | none |

## Design

`CompanyToken` inherits OpenZeppelin Contracts v5.3.0 `ERC20` without overriding any behaviour.
The only code the project adds is the constructor, which mints `INITIAL_SUPPLY` to `msg.sender`.
Everything the brief asks for is in the named constants at the top of the contract:

- `TOKEN_NAME = "Company.md"`
- `TOKEN_SYMBOL = "COMD"`
- `TOKEN_DECIMALS = 18` (OpenZeppelin's default, stated explicitly and tested)
- `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18`

The brief leaves no number open, so no value was chosen by the contributor.

After construction the contract exposes nothing beyond the ERC-20 interface (`name`, `symbol`,
`decimals`, `totalSupply`, `balanceOf`, `transfer`, `approve`, `allowance`, `transferFrom`) and the
public constants above. There is no owner, so there is no key to compromise and no privileged
action to govern. The supply can only ever shrink, and only by a holder sending tokens somewhere
irretrievable themselves, since there is no `burn` function either.

## Assumptions

- **The deployer is a contract or wallet that will distribute the supply.** Under the IMD launch the
  constructor's `msg.sender` is `ProjectFactory`, which forwards 10% to the launch's
  `MerkleDistributor`, seeds the Uniswap v4 pool with 80% and sends the remaining 10% to the
  requester's `remainderTo` address. The token does not know or care who deploys it; whoever does
  holds the whole supply afterwards. `tx.origin` is never used.
- **Launch flows must move exactly what they say.** Because there is no fee, tax or burn on any
  transfer, every transfer delivers exactly its amount, whether the sender is the factory, the pool
  manager, the distributor or an ordinary holder. No address needs to be exempted, so the
  constructor does not take the factory, pool manager or launch number.
- **The constructor makes no external calls** and reads no other contract, so it deploys on an
  empty chain and the launch's pre-checks can run it in isolation.
- **Compiler and build settings are pinned** in `foundry.toml`: `solc = "0.8.26"`, optimizer on at
  200 runs, `evm_version = "cancun"`, `bytecode_hash = "none"` and `cbor_metadata = false` so the
  deployed bytes are reproducible and carry no metadata hash. `ffi` is off and `fs_permissions` is
  empty.

## Deployment parameters

The IMD deployer launches the token from its creation code as built. For the manifest step:

| Manifest field | Value |
|---|---|
| `token.contract` | `CompanyToken` |
| `token.name` | `Company.md` |
| `token.symbol` | `COMD` |
| `token.decimals` | `18` |
| `token.constructorArgs` | `[]` |
| `token.totalSupply` | `1000000000000000000000000000` |
| `contracts` | `[]` (no application contracts) |

Launch economics, pool pairing (IMD at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`), fee
(`12500`), tick spacing (`60`) and opening price are the launch's and are copied into the manifest
by the manifest step, not by this repository. This repository intentionally contains no
`launch.json`.

`script/DeployCompanyToken.s.sol` is a reference script for local or manual deployment outside the
IMD launch. Its `deploy()` function takes no configuration and is exercised directly by
`test/DeployCompanyToken.t.sol`; `run()` only wraps it in a broadcast. The script reads no
environment variables.

```sh
forge script script/DeployCompanyToken.s.sol --rpc-url <public mainnet RPC> --broadcast
```

The account that broadcasts receives the whole supply.

## After launch

There is nothing to configure. The token has no owner-settable values, no setters and no
post-deployment initialisation. Nothing in this repository needs a value only the requester holds.

## Operational responsibilities

- **Supply custody.** Whoever receives the supply at deployment (the factory under IMD, otherwise
  the broadcasting account) is responsible for distributing it. The contract cannot claw tokens
  back, reissue them or freeze them, so a mistaken transfer is final.
- **No admin to run.** There is no owner key to rotate, no multisig to set up and no pause to
  operate. This also means there is no on-chain remedy if tokens are sent to a wrong address or a
  holder's key is lost. That is the deliberate trade-off of a fully immutable token.
- **Explorer verification.** After the launch, the deployer should verify the source on Etherscan
  (`forge verify-contract` with compiler `0.8.26`, optimizer `200` runs, EVM `cancun`, and the
  `bytecode_hash = "none"` / `cbor_metadata = false` settings) so holders can audit what they hold.
  That step belongs to the launch's deployer, not to this task.
- **Security review.** Tests passing is not an audit. The contract is a thin wrapper over an audited
  library and adds one line of logic, but an independent adversarial review before release remains
  good practice for anything that will hold value.

## Repository layout

```
foundry.toml                      Foundry configuration (solc 0.8.26, bytecode_hash = "none")
remappings.txt                    forge-std and @openzeppelin/contracts remappings
src/CompanyToken.sol              the token
script/DeployCompanyToken.s.sol   reference deploy script
test/CompanyToken.t.sol           behaviour, failure and fuzz tests
test/DeployCompanyToken.t.sol     deploy-script tests
lib/forge-std/                    forge-std v1.9.7 (vendored as plain files, MIT/Apache-2.0)
lib/openzeppelin-contracts/       OpenZeppelin Contracts v5.3.0 (vendored as plain files, MIT)
```

Dependencies are committed as ordinary files, not git submodules, so the project builds offline.

## Verification

```sh
forge build
forge test
forge fmt --check
```

The test suite covers:

- metadata and the exact supply figure from the brief;
- the whole supply minted once to `msg.sender` (a contract deployer, not `tx.origin`), with the
  single mint `Transfer` event;
- transfers and `transferFrom` on success paths, including whole-balance, zero-value, self-transfer
  and unlimited-allowance cases, and a rehearsal of the launch's 10% / 80% / 10% flows arriving whole;
- failure paths: insufficient balance, insufficient or missing allowance, zero-address receiver and
  spender, unknown selectors and plain ETH sends;
- the absence of any mint, pause, blocklist, freeze, lock, seize or `burnFrom` entry point, tried
  from both a stranger and the deployer;
- a bytecode scan confirming no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT` opcode and a runtime
  under the EIP-170 limit;
- fuzz tests for supply conservation, over-balance reverts and allowance accounting.

Tests read no environment variables and do not depend on the calling address, so they pass in any
order and in parallel.

Tools run for this task: `forge build`, `forge test` (with the verifier's fuzz seed) and
`forge fmt --check`. Slither and Mythril were not available on this machine and were not run.
