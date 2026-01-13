# CommitteeSync 🧭

Synchronizes committee membership across EVM chains using off-chain signatures and a shared nonce.

## 🔁 Cross-chain replay (by design)
- The domain omits `chainId` and `verifyingContract`, so proposals are replayable across chains **and deployments**.
- This is intentional to keep committees aligned even when contract addresses differ (e.g., some zkEVMs).

## ✅ Governance rules
- `MIN_SIZE = 5`, `MAX_SIZE = 255`.
- `THRESHOLD = 6000` BPS (60%) **rounded up**.

## 🌱 Bootstrap flow
- The constructor seeds a **single** initial member (`OWNER`).
- That seed member can bootstrap the first full committee by calling `sync` once.
- Committees must be unique and non-zero address members.

## 🔄 Desync recovery
If a chain falls behind, gather the signed proposals for the missing nonces and call `syncs()` on that chain.
`syncs()` applies proposals sequentially, advancing the nonce to match other chains.
An empty batch is a no-op.

## 🚀 Deployment
Requires a single environment variable:

```bash
export OWNER=0xYourInitialMember
```

Then run the script in `script/Deploy.s.sol`.

## 📦 Interfaces
- `sync(address[] newCommittee, bytes[] sigs)`
- `syncs(Vote[] batch)` where `Vote = {committee, sigs}`
