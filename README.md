# SorobanAnchor

A Soroban smart contract SDK for Stellar anchors. Handles attestation management, SEP-6 deposit/withdrawal flows, SEP-10 JWT authentication, anchor routing, rate limiting, and transaction state tracking — all in a `no_std` Rust library compiled to WASM.

## What it does

- Registers and revokes attestors with SEP-10 JWT verification
- Submits and retrieves on-chain attestations with replay attack protection
- Normalizes SEP-6 deposit, withdrawal, and transaction status responses across anchors
- Verifies SEP-10 EdDSA JWTs on-chain using stored Ed25519 public keys
- Routes requests across multiple anchors by reputation, fees, and settlement time
- Caches anchor metadata and stellar.toml capabilities with TTL-based expiry
- Tracks transaction state transitions with full audit logging
- Propagates request IDs and tracing spans across operations
- Enforces rate limits and configurable retry/backoff strategies
- Validates anchor domain endpoints and response schemas

## Project structure

```
src/                        # Core library
  lib.rs                    # Public API surface
  contract.rs               # Soroban contract (attestations, sessions, quotes, routing)
  sep6.rs                   # SEP-6 deposit/withdrawal normalization
  sep10_jwt.rs              # SEP-10 JWT verification (EdDSA, no_std)
  domain_validator.rs       # Anchor domain/endpoint validation
  errors.rs                 # Stable error codes
  rate_limiter.rs           # Rate limiting
  response_validator.rs     # Response schema validation
  retry.rs                  # Retry with exponential backoff
  transaction_state_tracker.rs
  deterministic_hash.rs     # Canonical SHA-256 payload hashing

tests/                      # Integration and unit tests
configs/                    # Example anchor configurations (JSON + TOML)
examples/                   # Rust and shell usage examples
scripts/                    # Build, validation, and deploy scripts
docs/                       # Feature and guide documentation
test_snapshots/             # Snapshot fixtures for deterministic tests
```

## Building

```bash
cargo build --release
```

For WASM output (Soroban deployment):

```bash
cargo build --release --target wasm32-unknown-unknown --no-default-features --features wasm
```

## Testing

```bash
cargo test
```

## CLI

```bash
# Deploy to testnet
anchorkit deploy --network testnet

# Register an attestor
anchorkit register --address GANCHOR123... --services deposits,withdrawals,kyc

# Submit an attestation
anchorkit attest --subject GUSER123... --payload-hash abc123...

# Check environment setup
anchorkit doctor
```

## Key APIs

```rust
// SEP-6: normalize a raw anchor deposit response
let response = initiate_deposit(raw)?;

// SEP-10: verify an anchor JWT on-chain
contract.verify_sep10_token(token, issuer);

// Submit an attestation (replay-protected)
let id = contract.submit_attestation(issuer, subject, timestamp, payload_hash, sig);

// Route across anchors by lowest fee
let best = contract.route(options);

// Track transaction state
tracker.transition(tx_id, TransactionStatus::Completed);
```

## Configuration

Anchor configs live in `configs/` as JSON or TOML. Validate them with:

```bash
./scripts/validate_all.sh
```

Schema reference: `config_schema.json`

## Production Deployment

### Build artifacts

```bash
# Native CLI binary
cargo build --release
# Binary: target/release/anchorkit

# WASM contract for Soroban
cargo build --release --target wasm32-unknown-unknown --no-default-features --features wasm
# Artifact: target/wasm32-unknown-unknown/release/anchorkit.wasm
```

### Pre-deployment checklist

Run the automated validator first:

```bash
./scripts/pre_deploy_validate.sh
```

Then verify each item manually:

- [ ] All configs in `configs/` pass schema validation (`./scripts/validate_all.sh`)
- [ ] WASM binary builds cleanly with `--no-default-features --features wasm`
- [ ] `cargo test` passes with no failures
- [ ] Admin keypair is stored in the Stellar CLI keystore or encrypted with GPG/age (see `docs/secret-file-encryption.md`)
- [ ] `ANCHOR_ADMIN_SECRET` is **not** set in shell history or CI logs
- [ ] Contract ID is recorded in `.anchorkit/deployments.json` after deploy
- [ ] Rate limits and session timeouts are set in your config file
- [ ] Monitoring alerts are configured (see `configs/` `monitoring` block)
- [ ] Webhook endpoints use HTTPS and are reachable from the contract host

### WASM deployment to Soroban

```bash
# 1. Deploy contract (testnet)
anchorkit deploy \
  --network testnet \
  --source anchor-admin \       # Stellar CLI keystore alias
  --admin GADMIN_ADDRESS

# 2. Record the contract ID printed by the deploy command, then initialize:
export ANCHOR_CONTRACT_ID=CXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# 3. Register your first attestor
anchorkit register \
  --address GATTESTOR_ADDRESS \
  --services deposits,withdrawals,kyc \
  --contract-id "$ANCHOR_CONTRACT_ID" \
  --network testnet \
  --source anchor-admin \
  --sep10-token <JWT> \
  --sep10-issuer <ISSUER>

# 4. Verify the deployment
anchorkit doctor --network testnet
```

For mainnet, replace `--network testnet` with `--network mainnet` and use a hardware-backed or HSM-managed key as `--source`.

### Contract upgrade

```bash
anchorkit deploy \
  --upgrade \
  --contract-id "$ANCHOR_CONTRACT_ID" \
  --network mainnet \
  --source anchor-admin
```

### Runtime configuration

Copy and edit one of the provided templates:

```bash
cp configs/fiat-on-off-ramp.toml my-anchor.toml
# Edit: contract.network, contract.admin_address, attestors.registry
```

Key fields to set before going live:

| Field | Purpose |
|-------|---------|
| `contract.network` | `mainnet` or `testnet` |
| `contract.admin_address` | Your admin Stellar address |
| `attestors.registry[].address` | Attestor public keys |
| `security.rate_limit_per_minute` | Per-attestor rate cap |
| `sessions.session_timeout_seconds` | Session TTL |
| `monitoring.alert_email` | Ops alert destination |

---

## Security controls

### Secret management

Never pass secret keys as CLI arguments in production. Use one of:

1. **Stellar CLI keystore** (recommended) — keys encrypted with a passphrase, never written to disk in plaintext:
   ```bash
   stellar keys add anchor-admin --secret-key
   anchorkit deploy --source anchor-admin --network mainnet
   ```

2. **Encrypted keypair file** — GPG or age encryption, decrypted to a RAM-backed path at runtime:
   ```bash
   gpg --decrypt --output /dev/shm/keypair.json keypair.json.gpg
   anchorkit register --keypair-file /dev/shm/keypair.json ...
   shred -u /dev/shm/keypair.json
   ```

3. **Encrypted credential store** — AES-256-GCM keystore managed by the CLI:
   ```bash
   anchorkit credentials add --name anchor-admin-key
   anchorkit register --credential-name anchor-admin-key ...
   ```

See `docs/secret-file-encryption.md` for full guidance including CI/CD patterns.

### Key rotation

```bash
# 1. Generate a new keypair and store it
stellar keys add anchor-admin-v2 --secret-key

# 2. Update the admin on-chain (requires current admin signature)
anchorkit deploy --upgrade --source anchor-admin --network mainnet

# 3. Revoke the old attestor if the key was used as one
anchorkit revoke \
  --address GOLD_ATTESTOR_ADDRESS \
  --contract-id "$ANCHOR_CONTRACT_ID" \
  --source anchor-admin-v2 \
  --network mainnet

# 4. Remove the old key from the keystore
stellar keys remove anchor-admin
```

Rotate keys immediately if a secret key is ever exposed in logs, shell history, or version control.

### Replay attack protection

Every attestation is keyed on `(issuer, payload_hash)` with a 7-day TTL. Duplicate submissions return error code 6 (`ReplayAttack`). Ensure your payload hashes are unique per operation — use `contract.generate_request_id()` to derive them deterministically.

### Rate limiting

Per-attestor sliding-window limits are enforced on-chain. Configure the cap in your config file:

```toml
[security]
rate_limit_per_minute = 60
```

Exceeding the limit returns error code 16 (`RateLimitExceeded`). Back off and retry after the window resets.

### Domain validation

All anchor endpoints are validated as HTTPS-only before any outbound request. HTTP endpoints are rejected with error code 12 (`InvalidEndpointFormat`). Never register an anchor with an HTTP endpoint in production.

### Monitoring

Enable structured logging and set up alerts on these signals:

- `RateLimitExceeded` (code 16) — possible abuse or misconfigured client
- `ReplayAttack` (code 6) — potential replay attack in progress
- `KycRejected` (code 21) — compliance event requiring review
- `WebhookDeliveryFailed` (code 22) — downstream integration issue
- `SessionExpired` (code 25) — clients not refreshing sessions

The `static/status-monitor.html` and `static/webhook_monitor.html` dashboards provide a browser-based view of live anchor and webhook status.

Full error code reference: `docs/error-codes.md`
Gas and storage cost guide: `docs/gas-and-storage-costs.md`

---

## Examples

| File | What it shows |
|------|--------------|
| `examples/cli_example.sh` | Full deposit/withdrawal workflow |
| `examples/anchor_info_discovery.sh` | Fetch anchor metadata and validate amounts |
| `examples/anchor_routing_example.sh` | Multi-anchor routing strategies |
| `examples/credential_management.sh` | Encrypted credential storage |
| `examples/kyc_workflow.sh` | End-to-end KYC lifecycle |
| `examples/attestation_workflow.sh` | Attestation submission and verification |
| `examples/mock_mode_example.sh` | Testing without live anchors |
| `examples/logging_demo.sh` | Logging configuration |

Run any shell example directly:

```bash
bash examples/kyc_workflow.sh
```

Rust examples:

```bash
cargo run --example logging_example
cargo run --example domain_validation_example
```

---

## Storybook (UI components)

The `storybook/` directory contains standalone HTML component previews. Open them in any browser — no build step required:

```bash
open storybook/index.html
```

To verify all pages load without broken links:

```bash
./scripts/validate_storybook.sh
```

To regenerate or update a component, edit the corresponding `.html` file in `storybook/` directly. Each file is self-contained with inline styles and scripts.

---

## License

MIT
