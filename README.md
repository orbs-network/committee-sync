# CommitteeSync 🧭

Synchronizes committee membership and per-address config across EVM chains using off-chain EIP-712 signatures and a shared nonce.

## 🔐 Signatures
- EIP-712 typed data; domain uses **name + version only** (no `chainId` or `verifyingContract`).
- Digests are replayable across chains/deployments by design.
- Version changes intentionally invalidate prior digests.

## ✅ Rules
- `MIN_SIZE = 3`, `MAX_SIZE = 255`.
- `THRESHOLD = 6000` BPS (60%) **rounded up**.
- Committee entries must be unique and non-zero.

## 🔄 Ops
- Desync recovery: collect missing digests and call `syncs()` to replay sequentially.
- Empty batch is a no-op.
- Config mapping only updates the provided accounts; old entries remain unless overwritten/cleared (clear by including the account in a `sync` with `value = 0x`).

## 📦 Interfaces
- `sync(address[] newCommittee, Config[] config, bytes[] sigs)`
- `syncs(Sync[] batch)` where `Sync = {committee, config, sigs}`
- `Config = {account, version, value}` stored in a single per-address mapping.
- Libraries: `CommitteeSyncHash`, `CommitteeSyncConfig`, `CommitteeSyncValidation`.

## 🚀 Deploy
```bash
export OWNER=0xYourInitialMember
```
Run `script/Deploy.s.sol`.
