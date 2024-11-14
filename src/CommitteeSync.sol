// SPDX-License-Identifier: MIT
pragma solidity 0.8.x;

/**
 * This contract manages a synchronized committee structure across different blockchains.
 * It allows the committee members to propose and approve changes to the committee.
 */
contract CommitteeSync {
    uint256 public constant MAX_SIZE = type(uint8).max;
    uint256 public constant MIN_SIZE = 3;
    uint256 public constant THRESHOLD = 70;
    uint256 public constant PCNT = 100;
    uint256 public constant EPOCH = 1 hours;

    address[] public committee;
    mapping(address => bytes32) public votes; // member => proposal
    mapping(bytes32 => uint256) public count; // proposal => count

    event Vote(address indexed member, bytes32 indexed proposal);
    event NewCommittee(uint256 count, address[] committee);

    error MembersOnly();
    error InvalidCommittee();

    modifier membersOnly() {
        if (!isMember(msg.sender)) revert MembersOnly();
        _;
    }

    modifier validVote(address[] memory _committee) {
        if (_committee.length < MIN_SIZE || _committee.length > MAX_SIZE) revert InvalidCommittee();
        _;
    }

    constructor(address initialMember) {
        committee.push(initialMember);
    }

    function vote(address[] memory _committee) external membersOnly validVote(_committee) {
        bytes32 proposal = keccak256(abi.encode((block.timestamp / EPOCH), _committee));

        bytes32 previous = votes[msg.sender];
        if (previous != 0 && count[previous] > 0) count[previous]--;

        votes[msg.sender] = proposal;
        count[proposal]++;
        emit Vote(msg.sender, proposal);

        uint256 _count = count[proposal];
        if (_count >= (committee.length * THRESHOLD) / PCNT) {
            count[proposal] = 0;
            committee = _committee;
            emit NewCommittee(_count, committee);
        }
    }

    function getCommittee() external view returns (address[] memory) {
        return committee;
    }

    function isMember(address member) public view returns (bool) {
        for (uint8 i = 0; i < committee.length; i++) {
            if (member == committee[i]) {
                return true;
            }
        }
        return false;
    }
}
