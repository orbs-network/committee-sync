// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title CommitteeSync
/// @notice Synchronizes committee membership across EVM chains.
/// @dev
/// Architecture:
/// - Off-chain signatures from current governance members.
/// - Signatures bind to epoch = block.timestamp / epochLength.
/// - Custom hashing: EIP-712-style struct hashing without chainId or verifying contract.
/// - Signatures can be replayed across EVM chains by design.
/// Hashing:
/// 1) committeeHash = keccak256(abi.encode(newCommittee))
/// 2) structHash = keccak256(abi.encode(EIP191_DOMAIN_SEPARATOR, PROPOSAL_TYPEHASH, epoch, committeeHash))
/// 3) signature = EIP-191 prefixed signature over structHash digest.
contract CommitteeSync {
    using MessageHashUtils for bytes32;

    string public constant NAME = "OrbsCommitteeSync";
    string public constant VERSION = "1";

    bytes32 public constant EIP191_DOMAIN_TYPEHASH = keccak256("EIP191Domain(string name,string version)");
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256("Proposal(uint256 epoch,bytes32 committeeHash)");
    bytes32 public constant EIP191_DOMAIN_SEPARATOR =
        keccak256(abi.encode(EIP191_DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION))));

    uint256 public constant MAX_SIZE = type(uint8).max;
    uint256 public constant MIN_SIZE = 3;
    uint256 public constant BPS = 100_00;
    uint256 public constant NOT_FOUND = type(uint256).max;

    uint256 public immutable epochLength;
    uint256 public immutable threshold;

    address[] public committee;

    event NewCommittee(uint256 indexed epoch, address[] committee, uint256 votes, bytes32 proposal);

    /// @dev Proposed committee size is outside allowed bounds.
    error InvalidCommittee();
    /// @dev Constructor parameters are invalid.
    error InvalidConfig();
    /// @dev Collected signatures are fewer than threshold.
    error InsufficientVotes(uint256 votes);

    /// @param initialMember The initial committee member.
    /// @param _epochLength Epoch length in seconds.
    /// @param _threshold Required threshold in BPS (1..BPS).
    constructor(address initialMember, uint256 _epochLength, uint256 _threshold) {
        if (_epochLength == 0 || _threshold == 0 || _threshold > BPS) revert InvalidConfig();
        committee.push(initialMember);
        epochLength = _epochLength;
        threshold = _threshold;
    }

    /// @notice Updates committee if enough current members signed the proposal.
    /// @param newCommittee Proposed committee members.
    /// @param sigs ECDSA signatures over the proposal.
    function vote(address[] memory newCommittee, bytes[] memory sigs) external {
        if (newCommittee.length < MIN_SIZE || newCommittee.length > MAX_SIZE) revert InvalidCommittee();

        uint256 epoch = block.timestamp / epochLength;
        bytes32 proposal = hash(epoch, newCommittee).toEthSignedMessageHash();
        uint256 count = _countUniqueMembers(proposal, sigs);

        uint256 required = Math.max(1, committee.length * threshold / BPS);
        if (count < required) revert InsufficientVotes(count);

        committee = newCommittee;
        emit NewCommittee(epoch, committee, count, proposal);
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

    /// @notice Returns the proposal hash for the given epoch and committee.
    function hash(uint256 epoch, address[] memory newCommittee) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(EIP191_DOMAIN_SEPARATOR, PROPOSAL_TYPEHASH, epoch, keccak256(abi.encode(newCommittee)))
            );
    }

    /// @dev Counts unique current members who signed the proposal.
    function _countUniqueMembers(bytes32 proposal, bytes[] memory sigs) internal view returns (uint256 count) {
        uint256 seen;
        for (uint256 i; i < sigs.length; i++) {
            address signer = ECDSA.recover(proposal, sigs[i]);

            uint256 index = indexOf(signer);
            if (index == NOT_FOUND) continue;

            uint256 mask = 1 << index;
            if (seen & mask != 0) continue;
            seen |= mask;

            count++;
        }
    }
}
