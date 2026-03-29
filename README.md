# CommitteeSync 🧭

Synchronizes committee membership and per-address config across EVM chains using off-chain EIP-712 signatures consensus.

## 🔐 Signatures
- EIP-712 domain uses **name + version only** (no `chainId`, no `verifyingContract`).
- Digests are intentionally replayable across chains and deployments.

## ✅ Rules
- `MIN_SIZE = 3`, `MAX_SIZE = 255`.
- `THRESHOLD = 6000` BPS (60%) **rounded up** of **current** committee size.
- New committee entries must be unique and non-zero.

## ✍️ Signature counting
- `sync` counts only unique valid signatures from the **current** committee (before the update).
- Invalid signatures are ignored.
- Duplicate signatures from the same signer are counted once.
- The signed digest nonce must match `nonce + 1`.

## ⚙️ State updates
- `committee = newCommittee`
- `nonce++`
- `updated = block.timestamp`
- Each provided `Config` item: `config[key][account] = value`
- Keys not present in `newConfig` are untouched.
- To clear a value, include the same `account + key` with `value = 0x`.

## 🔄 Ops
- Desync recovery: collect missing signed updates and call `syncs()` to replay them in order.
- Empty batch is a no-op.
- `syncs()` is atomic: if one step fails, the whole transaction reverts.

## 🧰 Bootstrap (`init`)
- `init(initialCommittee, initialConfig, newNonce)` works only while committee size is still `1`.
- Caller must be that sole initial member.
- `newNonce` must be greater than the current nonce.
- `initialCommittee` must pass the normal committee validation rules.
- Each provided `initialConfig` item is stored with the same semantics as `sync`.

## 📦 Interfaces
- `sync(address[] newCommittee, Config[] newConfig, bytes[] sigs)`
- `syncs(Update[] batch)` where `Update = {committee, config, sigs}`
- `init(address[] initialCommittee, Config[] initialConfig, uint256 newNonce)`
- `hash(uint256 digestNonce, address[] newCommittee, Config[] newConfig)`
- `Config = {key, account, value}` stored in `config[key][account]`.
- Libraries: `CommitteeSyncHash`, `CommitteeSyncConfig`, `CommitteeSyncValidation`.

## 🚀 Deploy
```bash
forge script script/Deploy.s.sol:Deploy --broadcast --verify
```
- `OWNER` is required.
- `SALT` is optional (script has a built-in default).
