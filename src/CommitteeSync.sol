// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {CommitteeSyncConfig} from "./CommitteeSyncConfig.sol";
import {CommitteeSyncHash} from "./CommitteeSyncHash.sol";
import {CommitteeSyncValidation} from "./CommitteeSyncValidation.sol";

/// @title CommitteeSync
/// @notice Synchronizes committee membership and per-address config across EVM chains.
/// @dev
/// - Off-chain signatures from current governance members.
/// - Signatures bind to an incrementing nonce.
/// - EIP-712 typed data; domain includes name/version only (no chainId or verifyingContract).
/// - Signatures are replayable across chains and deployments by design to keep committees aligned
/// - Upgrade boundary is the EIP-712 version string; change it to invalidate prior digests
/// - Config entries persist unless explicitly overwritten/cleared; clear by syncing value = 0x
contract CommitteeSync {
    uint256 public constant THRESHOLD = 60_00;
    uint256 public constant BPS = 100_00;
    uint256 public constant NOT_FOUND = type(uint256).max;

    address[] public committee;
    mapping(address => CommitteeSyncConfig.StoredConfig) public config;
    uint256 public nonce;
    uint256 public updated;

    event Init(uint256 newNonce);
    event NewCommittee(uint256 indexed nonce, address[] committee, uint256 count, bytes32 digest);

    error InitFailed();
    error InsufficientCount(uint256 count);

    struct Sync {
        address[] committee;
        CommitteeSyncConfig.Config[] config;
        bytes[] sigs;
    }

    /// @param initialMember The initial committee member.
    constructor(address initialMember) {
        committee.push(initialMember);
    }

    /// @notice Applies multiple sequential committee updates in one call.
    /// @param batch Target committee members and signatures for each step.
    function syncs(Sync[] memory batch) external {
        for (uint256 i; i < batch.length; i++) {
            sync(batch[i].committee, batch[i].config, batch[i].sigs);
        }
    }

    /// @notice Updates committee if enough current members signed the digest.
    /// @param newCommittee Target committee members.
    /// @param newConfig Per-address config to set alongside the committee update.
    /// @param sigs ECDSA signatures over the digest.
    function sync(address[] memory newCommittee, CommitteeSyncConfig.Config[] memory newConfig, bytes[] memory sigs)
        public
    {
        CommitteeSyncValidation.validate(newCommittee);

        uint256 digestNonce = nonce + 1;
        bytes32 digest = hash(digestNonce, newCommittee, newConfig);
        uint256 count = _countUniqueMembers(digest, sigs);

        uint256 required = Math.max(1, Math.mulDiv(committee.length, THRESHOLD, BPS, Math.Rounding.Ceil));
        if (count < required) revert InsufficientCount(count);

        committee = newCommittee;
        nonce = digestNonce;
        updated = block.timestamp;
        CommitteeSyncConfig.save(config, newConfig);
        emit NewCommittee(digestNonce, committee, count, digest);
    }

    /// @notice Sets the nonce while the committee still has only the initial member.
    /// @param newNonce The nonce to set (must be greater than the current nonce).
    function init(uint256 newNonce) external {
        bool allowed = committee.length == 1 && msg.sender == committee[0] && newNonce > nonce;
        if (!allowed) revert InitFailed();
        nonce = newNonce;
        emit Init(newNonce);
    }

    /// @notice Returns the current committee array.
    function getCommittee() external view returns (address[] memory) {
        return committee;
    }

    /// @notice True if the address is a current committee member.
    function isMember(address member) external view returns (bool) {
        return indexOf(member) != NOT_FOUND;
    }

    /// @notice Returns the index of a committee member, or NOT_FOUND.
    function indexOf(address member) public view returns (uint256 index) {
        for (uint256 i; i < committee.length; i++) {
            if (member == committee[i]) return i;
        }
        return NOT_FOUND;
    }

    /// @notice Returns the digest for the given nonce, committee, and config.
    function hash(uint256 digestNonce, address[] memory newCommittee, CommitteeSyncConfig.Config[] memory newConfig)
        public
        pure
        returns (bytes32)
    {
        return CommitteeSyncHash.hash(digestNonce, newCommittee, newConfig);
    }

    /// @dev Counts unique current members who signed the digest.
    function _countUniqueMembers(bytes32 digest, bytes[] memory sigs) internal view returns (uint256 count) {
        uint256 seen;
        for (uint256 i; i < sigs.length; i++) {
            (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, sigs[i]);
            if (err != ECDSA.RecoverError.NoError) continue;

            uint256 index = indexOf(signer);
            if (index == NOT_FOUND) continue;

            uint256 mask = 1 << index;
            if (seen & mask != 0) continue;
            seen |= mask;

            count++;
        }
    }
}
