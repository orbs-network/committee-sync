// SPDX-License-Identifier: MIT
pragma solidity 0.8.x;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * This contract manages a synchronized committee structure across different blockchains.
 * It allows the committee members to propose and approve changes to the committee.
 */
contract CommitteeSync {
    uint256 public constant MAX_COMMITTEE_SIZE = type(uint8).max;
    uint256 public constant MIN_COMMITTEE_SIZE = 3;
    uint256 public constant THRESHOLD = 70;

    address[] public committee;
    mapping(address => bytes32) public votes; // member => proposal
    mapping(bytes32 => address[]) public proposals; // proposal => new committee
    mapping(bytes32 => uint256) public counts; // proposal => count

    event NewCommittee(address[] committee);

    error MembersOnly();
    error InvalidCommittee();
    error AlreadyVoted();

    modifier membersOnly() {
        for (uint8 i = 0; i < committee.length; i++) {
            if (msg.sender == committee[i]) {
                _;
                return;
            }
        }
        revert MembersOnly();
    }

    // TODO: deterministic init
    constructor(address[] memory _committee) {
        committee = _committee;
    }

    function sync(address[] memory _committee) external membersOnly {
        if (_committee.length < MIN_COMMITTEE_SIZE || _committee.length > MAX_COMMITTEE_SIZE) {
            revert InvalidCommittee();
        }

        bytes32 proposal = keccak256(abi.encode(_committee));

        if (votes[msg.sender] == proposal) revert AlreadyVoted();

        votes[msg.sender] = proposal;
        proposals[proposal] = _committee;
        counts[proposal]++;

        if (counts[proposal] >= (committee.length * THRESHOLD) / 100) {
            committee = _committee;
            emit NewCommittee(committee);
        }
    }
}
