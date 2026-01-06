// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * This contract manages a synchronized committee structure across different blockchains.
 * It allows the committee members to propose and approve changes to the committee.
 */
contract CommitteeSync {
    using MessageHashUtils for bytes32;

    string public constant NAME = "OrbsCommitteeSync";
    string public constant VERSION = "1";

    bytes32 public constant EIP191_DOMAIN_TYPEHASH = keccak256("EIP191Domain(string name,string version)");
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256("Proposal(uint256 epoch,address[] committee)");
    bytes32 public constant EIP191_DOMAIN_SEPARATOR =
        keccak256(abi.encode(EIP191_DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION))));

    uint256 public constant MAX_SIZE = type(uint8).max;
    uint256 public constant MIN_SIZE = 3;
    uint256 public constant BPS = 100_00;

    uint256 public immutable epoch;
    uint256 public immutable threshold;

    address[] public committee;

    mapping(address => bytes32) public votes; // member => proposal
    mapping(bytes32 => uint256) public count; // proposal => count

    event NewCommittee(uint256 indexed epoch, address[] committee, uint256 votes, bytes32 proposal);

    error InvalidCommittee();
    error InvalidSignature();

    modifier validVote(address[] memory newCommittee) {
        if (newCommittee.length < MIN_SIZE || newCommittee.length > MAX_SIZE) revert InvalidCommittee();

        address prev = address(0);
        for (uint256 i; i < newCommittee.length; i++) {
            if (newCommittee[i] == address(0) || newCommittee[i] <= prev) revert InvalidCommittee();
            prev = newCommittee[i];
        }

        _;
    }

    constructor(address initialMember, uint256 _epoch, uint256 _threshold) {
        committee.push(initialMember);
        epoch = _epoch;
        threshold = _threshold;
    }

    function vote(address[] memory newCommittee, bytes[] memory sigs) external validVote(newCommittee) {
        if (sigs.length == 0) revert InvalidSignature();

        uint256 _epoch = block.timestamp / epoch;
        bytes32 proposal = keccak256(abi.encode(PROPOSAL_TYPEHASH, _epoch, keccak256(abi.encode(newCommittee))))
            .toEthSignedMessageHash();

        for (uint256 i; i < sigs.length; i++) {
            address signer = ECDSA.recover(proposal, sigs[i]);
            if (!isMember(signer)) continue;

            bytes32 previous = votes[signer];
            if (previous != 0 && count[previous] > 0) count[previous]--;

            votes[signer] = proposal;
            count[proposal]++;
        }

        uint256 _count = count[proposal];
        if (_count >= (committee.length * threshold) / BPS) {
            count[proposal] = 0;
            committee = newCommittee;
            emit NewCommittee(_epoch, committee, _count, proposal);
        }
    }

    function getCommittee() external view returns (address[] memory) {
        return committee;
    }

    function isMember(address member) public view returns (bool) {
        for (uint256 i; i < committee.length; i++) {
            if (member == committee[i]) return true;
        }
        return false;
    }
}
