// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CommitteeSync
 * @notice This contract manages a synchronized committee structure across different blockchains.
 *         It allows the committee members to propose and approve changes to the committee.
 * @dev The contract is designed to be secure and efficient, preventing reentrancy attacks and
 *      potential misuse. All committee operations are protected by role-based access control.
 */
contract CommitteeSync is AccessControl, ReentrancyGuard {
    // Roles
    bytes32 public constant COMMITTEE_ROLE = keccak256("COMMITTEE_ROLE");

    // Current committee members
    address[] public currentCommittee;

    // Proposals to change the committee
    struct Proposal {
        address[] newCommittee; // The proposed new committee members
        uint256 proposalDeadline; // The deadline for the proposal to be valid
        uint256 approvals; // The number of approvals the proposal has received
        mapping(address => bool) hasApproved; // Tracks who has approved this proposal
    }

    mapping(bytes32 => Proposal) public proposals;
    bytes32[] public proposalHashes; // List to track existing proposals

    // Constants
    uint256 public constant PROPOSAL_DEADLINE = 1 days; // Default proposal validity period
    uint256 public constant MAX_COMMITTEE_SIZE = 100;   // Maximum allowed committee size

    // Events
    event CommitteeUpdated(address[] newCommittee);
    event ProposalSubmitted(bytes32 proposalHash);
    event ProposalApproved(bytes32 proposalHash);

    /**
     * @dev Initializes the contract with an initial committee.
     * @param initialCommittee The initial set of committee members.
     */
    constructor(address[] memory initialCommittee) {
        _setCommittee(initialCommittee);
        // Grant COMMITTEE_ROLE to each initial committee member
        for (uint256 i = 0; i < initialCommittee.length; i++) {
            _grantRole(COMMITTEE_ROLE, initialCommittee[i]);
        }
    }

    /**
     * @notice Returns the current committee members.
     * @return The current committee members as an array of addresses.
     */
    function getCurrentCommittee() public view returns (address[] memory) {
        return currentCommittee;
    }

    /**
     * @notice Proposes a new committee or approves an existing proposal.
     * @dev Only committee members can call this function. Each member can only approve once.
     *      The `approvalDeadline` parameter ensures that a proposal cannot be approved after it has expired.
     * @param newCommittee The proposed new committee members.
     * @param approvalDeadline The deadline by which this approval must be submitted.
     */
    function proposeOrApprove(address[] memory newCommittee, uint256 approvalDeadline)
    external
    onlyCommittee
    checkApprovalDeadline(approvalDeadline)
    {
        require(newCommittee.length > 0 && newCommittee.length <= MAX_COMMITTEE_SIZE, "Invalid committee size");

        bytes32 proposalHash = keccak256(abi.encode(newCommittee));

        // Check if proposal exists
        if (proposals[proposalHash].proposalDeadline == 0) {
            // Proposal doesn't exist, create a new one
            Proposal storage proposal = proposals[proposalHash];
            proposal.newCommittee = newCommittee;
            proposal.proposalDeadline = block.timestamp + PROPOSAL_DEADLINE;

            proposalHashes.push(proposalHash);
            // Track the proposal hash
            emit ProposalSubmitted(proposalHash);
        }

        // Check if sender has already approved
        Proposal storage existingProposal = proposals[proposalHash];
        require(!existingProposal.hasApproved[msg.sender], "Already approved");

        // Mark sender's approval
        existingProposal.hasApproved[msg.sender] = true;
        existingProposal.approvals++;

        // Check if enough approvals to update the committee
        if (existingProposal.approvals >= currentCommittee.length / 2) {
            _setCommittee(existingProposal.newCommittee);
            emit CommitteeUpdated(existingProposal.newCommittee);
            delete proposals[proposalHash];
            // Clean up proposal
            _removeProposalHash(proposalHash);
            // Remove from proposalHashes list
        }

        emit ProposalApproved(proposalHash);

        // Call maintenance to clean up expired data
        maintenance();
    }

    /**
     * @notice Cleans up expired proposals to reduce contract state size.
     * @dev This function should be called periodically to remove expired proposals.
     */
    function maintenance() public nonReentrant {
        // Iterate only over the existing proposals in proposalHashes
        for (uint256 i = 0; i < proposalHashes.length; i++) {
            bytes32 proposalHash = proposalHashes[i];
            Proposal storage proposal = proposals[proposalHash];
            if (proposal.proposalDeadline != 0 && block.timestamp > proposal.proposalDeadline) {
                delete proposals[proposalHash];
                // Delete the expired proposal
                _removeProposalHash(proposalHash);
                // Remove from proposalHashes list
                i--;
                // Adjust index after deletion
            }
        }
    }

    /**
     * @dev Internal function to set the current committee and update roles.
     * @param newCommittee The new committee members.
     */
    function _setCommittee(address[] memory newCommittee) internal {
        // Revoke COMMITTEE_ROLE from previous committee members
        for (uint256 i = 0; i < currentCommittee.length; i++) {
            _revokeRole(COMMITTEE_ROLE, currentCommittee[i]);
        }
        currentCommittee = newCommittee;
        // Grant COMMITTEE_ROLE to new committee members
        for (uint256 j = 0; j < newCommittee.length; j++) {
            _grantRole(COMMITTEE_ROLE, newCommittee[j]);
        }
    }

    /**
     * @dev Internal function to remove a proposal hash from the tracking list.
     * @param proposalHash The hash of the proposal to be removed.
     */
    function _removeProposalHash(bytes32 proposalHash) internal {
        // Find the index of the proposalHash in the array and remove it
        for (uint256 i = 0; i < proposalHashes.length; i++) {
            if (proposalHashes[i] == proposalHash) {
                proposalHashes[i] = proposalHashes[proposalHashes.length - 1];
                proposalHashes.pop();
                break;
            }
        }
    }

    /**
     * @dev This function allows access to proposal details without exposing the entire struct
     * @param proposalHash The keccak256 hash of the proposed committee members array
     * @return newCommittee The array of proposed new committee members
     * @return proposalDeadline The timestamp at which the proposal expires
     * @return approvals The number of approvals the proposal has received
     */
    function getProposal(bytes32 proposalHash) public view returns (address[] memory newCommittee, uint256 proposalDeadline, uint256 approvals) {
        Proposal storage proposal = proposals[proposalHash];
        require(proposal.proposalDeadline != 0, "Proposal does not exist");
        return (proposal.newCommittee, proposal.proposalDeadline, proposal.approvals);
    }

    /**
     * @dev Modifier to ensure that the sender is a committee member.
     */
    modifier onlyCommittee() {
        require(hasRole(COMMITTEE_ROLE, msg.sender), "Not a committee member");
        _;
    }

    /**
     * @dev Modifier to check if the approval deadline has not passed.
     * @param approvalDeadline The deadline for the approval to be valid.
     */
    modifier checkApprovalDeadline(uint256 approvalDeadline) {
        require(block.timestamp <= approvalDeadline, "Approval deadline has passed");
        _;
    }

    /**
     * @notice Prevents the contract from receiving Ether.
     */
    receive() external payable {
        revert("Contract does not accept Ether");
    }

    /**
     * @notice Fallback function to prevent accidental Ether transfers.
     */
    fallback() external payable {
        revert("Contract does not accept Ether");
    }

}
