// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/CommitteeSync.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract CommitteeSyncTest is Test {
    using ECDSA for bytes32;

    CommitteeSync public committeeSync;
    address[] public initialCommittee;
    uint256 public constant THRESHOLD = 2; // 2 approvals needed for the test
    uint256 public constant PROPOSAL_DEADLINE = 1 days;

    // Committee member private keys (for signing)
    uint256[] private committeePrivateKeys;

    // Non-committee member addresses
    address public nonCommitteeMember = address(99);

    // A helper variable to store the current time
    uint256 public currentTime;

    function setUp() public {
        // Assign addresses for committee members
        initialCommittee = [address(1), address(2), address(3)];

        // Private keys corresponding to the committee member addresses
        // Note: In Foundry, addresses from address(1) to address(20) correspond to private keys 1 to 20
        committeePrivateKeys = [uint256(1), uint256(2), uint256(3)];

        // Simulate deployment from address(1)
        vm.startPrank(address(1));

        // Deploy the CommitteeSync contract
        committeeSync = new CommitteeSync(initialCommittee);

        // Stop simulating address(1)
        vm.stopPrank();
    }

    function testInitialSetup() public {

        // Verify that initial committee members are set correctly
        for (uint256 i = 0; i < initialCommittee.length; i++) {
            assertTrue(committeeSync.hasRole(committeeSync.COMMITTEE_ROLE(), initialCommittee[i]), "Initial committee member not set");
        }

        // Verify that the committee size is correct
        assertEq(committeeSync.getCurrentCommittee().length, initialCommittee.length, "Incorrect committee size");

    }

    function testSubmitProposal() public {
        // New committee members
        address[] memory newCommittee = new address[](2);
        newCommittee[0] = address(4);
        newCommittee[1] = address(5);

        uint256 approvalDeadline = block.timestamp + 1 hours;
        // Set a deadline 1 hour from now

        // Simulate a committee member calling the function
        vm.startPrank(initialCommittee[0]);

        // Submit the proposal
        committeeSync.proposeOrApprove(newCommittee, approvalDeadline);

        vm.stopPrank();

        // Verify the proposal exists
        bytes32 proposalHash = keccak256(abi.encode(newCommittee));
        (address[] memory proposedCommittee, uint256 proposalDeadline, uint256 approvals) = committeeSync.getProposal(proposalHash);

        assertEq(proposalDeadline, block.timestamp + PROPOSAL_DEADLINE, "Proposal deadline not set correctly");
        assertEq(approvals, 1, "Initial approval count should be 1");
        assertEq(proposedCommittee.length, newCommittee.length, "Proposed committee size mismatch");

        for (uint i = 0; i < newCommittee.length; i++) {
            assertEq(proposedCommittee[i], newCommittee[i], "Proposed committee member mismatch");
        }

    }

    function testApproveProposal() public {

        // New committee members
        address[] memory newCommittee = new address[](2);
        newCommittee[0] = address(4);
        newCommittee[1] = address(5);

        uint256 approvalDeadline = block.timestamp + 1 hours;

        // Check initial committee
        address[] memory initialCommitteeMembers = committeeSync.getCurrentCommittee();
        console.log("Initial committee size:", initialCommitteeMembers.length);

        // Submit the proposal with the first committee member
        vm.startPrank(initialCommittee[0]);
        committeeSync.proposeOrApprove(newCommittee, approvalDeadline);
        vm.stopPrank();

        // Check committee after first approval
        address[] memory committeeAfterFirstApproval = committeeSync.getCurrentCommittee();
        console.log("Committee size after first approval:", committeeAfterFirstApproval.length);

        // Check if initialCommittee[1] is still a committee member
        bool isStillCommitteeMember = committeeSync.hasRole(committeeSync.COMMITTEE_ROLE(), initialCommittee[1]);
        console.log("Is initialCommittee[1] still a committee member?", isStillCommitteeMember);

        // Approve the proposal with the second committee member
        vm.startPrank(initialCommittee[1]);
        try committeeSync.proposeOrApprove(newCommittee, approvalDeadline) {
            console.log("Second approval succeeded");
        } catch Error(string memory reason) {
            console.log("Second approval failed:", reason);
        }
        vm.stopPrank();

        // Verify final committee state
        address[] memory updatedCommittee = committeeSync.getCurrentCommittee();
        console.log("Final committee size:", updatedCommittee.length);

        for (uint256 i = 0; i < updatedCommittee.length; i++) {
            console.log("Committee member", i, ":", updatedCommittee[i]);
        }

        // Assertions
        assertEq(updatedCommittee.length, newCommittee.length, "Committee size not updated");

        for (uint256 i = 0; i < newCommittee.length; i++) {
            assertTrue(committeeSync.hasRole(committeeSync.COMMITTEE_ROLE(), newCommittee[i]), "New committee member not set");
        }
    }

    function testProposalExpired() public {

        // New committee members
        address[] memory newCommittee = new address[](2);

        newCommittee[0] = address(4);
        newCommittee[1] = address(5);

        uint256 approvalDeadline = block.timestamp + 1 hours;
        // Set a deadline 1 hour from now

        // Submit the proposal first
        vm.startPrank(initialCommittee[0]);
        committeeSync.proposeOrApprove(newCommittee, approvalDeadline);
        vm.stopPrank();

        // Increase time beyond the proposal deadline
        vm.warp(block.timestamp + PROPOSAL_DEADLINE + 10);

        // Expect revert before calling the next `proposeOrApprove` function
        vm.startPrank(initialCommittee[1]);
        vm.expectRevert("Proposal has expired");
        committeeSync.proposeOrApprove(newCommittee, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function testNonCommitteeMemberCannotPropose() public {

        // New committee members
        address[] memory newCommittee = new address[](2);

        newCommittee[0] = address(4);
        newCommittee[1] = address(5);

        uint256 approvalDeadline = block.timestamp + 1 hours;
        // Set a deadline 1 hour from now

        // Attempt to submit a proposal from a non-committee member
        vm.startPrank(nonCommitteeMember);
        vm.expectRevert("Not a committee member");

        committeeSync.proposeOrApprove(newCommittee, approvalDeadline);

        vm.stopPrank();

    }

    function testMaintenanceCleansUpExpiredProposals() public {

        // New committee members
        address[] memory newCommittee = new address[](2);

        newCommittee[0] = address(4);
        newCommittee[1] = address(5);

        uint256 approvalDeadline = block.timestamp + 1 hours;

        // Submit the proposal first
        vm.startPrank(initialCommittee[0]);
        committeeSync.proposeOrApprove(newCommittee, approvalDeadline);
        vm.stopPrank();

        // Increase time beyond the proposal deadline
        vm.warp(block.timestamp + PROPOSAL_DEADLINE + 10);

        // Call maintenance to clean up expired proposals
        committeeSync.maintenance();

        // Verify the proposal has been removed
        bytes32 proposalHash = keccak256(abi.encode(newCommittee));

        // Try to get the proposal, expect it to revert
        vm.expectRevert("Proposal does not exist");

        committeeSync.getProposal(proposalHash);

    }
}
