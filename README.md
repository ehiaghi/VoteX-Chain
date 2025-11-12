 VoteX-Chain

**VoteX-Chain** is a tokenized voting power system built on the Stacks blockchain using Clarity smart contracts. It enables decentralized governance with fungible voting tokens, proposal creation, and token-weighted voting.

 Features

- **Fungible Governance Token:** Built-in `votex-token` for voting power.
- **Proposal Lifecycle:** Create, vote (weighted by token balance), finalize, and cancel proposals.
- **Double-Voting Prevention:** Each address can only vote once per proposal.
- **On-Chain Storage:** All proposals, votes, and statuses are stored on-chain.
- **Event Emission:** Key actions emit event-like tuples for off-chain indexing.

 Contract Overview

- **Token:** `votex-token` (fungible, mintable by contract owner)
- **Proposal Structure:** Title, description, creator, deadline, for/against votes, status
- **Voting:** Token-weighted, supports FOR/AGAINST, only open proposals, only once per address
- **Finalization:** Anyone can finalize after deadline; result is APPROVED, REJECTED, or TIE

 Usage

### Mint Tokens (Owner Only)
```clarity
(mint-tokens recipient amount)
```

### Create Proposal
```clarity
(create-proposal title description duration)
```

 Cast Vote
```clarity
(cast-vote proposal-id support)
```

 Finalize Proposal
```clarity
(finalize-proposal proposal-id)
```

 Cancel Proposal
```clarity
(cancel-proposal proposal-id)
```

 Read-Only Functions
- `voting-weight (who)` — Get token balance
- `get-proposal (proposal-id)` — Get proposal details
- `has-voted (proposal-id who)` — Check if address has voted
- `proposal-summary (proposal-id)` — Get summary info

 Development

- **Language:** [Clarity](https://docs.stacks.co/write-smart-contracts/clarity-lang)
- **Recommended Tools:** [Clarinet](https://github.com/hirosystems/clarinet), [VS Code](https://code.visualstudio.com/)

 Project Structure

- `contracts/VoteX-Chain.clar` — Main smart contract
- `.gitignore` — Standard ignores for Stacks/Node.js projects

 License

MIT License
