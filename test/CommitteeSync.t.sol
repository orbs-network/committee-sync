// SPDX-License-Identifier: MIT
pragma solidity 0.8.x;

import "forge-std/Test.sol";

import "src/CommitteeSync.sol";

contract CommitteeSyncTest is Test {
    CommitteeSync public committeeSync;

    function setUp() public {
        committeeSync = new CommitteeSync();
    }

    function arr(uint256 m0, uint256 m1, uint256 m2) internal pure returns (address[] memory newCommittee) {
        newCommittee = new address[](3);
        newCommittee[0] = address(uint160(m0));
        newCommittee[1] = address(uint160(m1));
        newCommittee[2] = address(uint160(m2));
    }

    function test_emptyCommittee() public {
        assertEq(committeeSync.getCommittee().length, 0);
        committeeSync.vote(arr(1, 2, 3));
        assertEq(committeeSync.getCommittee().length, 3);
        assertEq(committeeSync.getCommittee(), arr(1, 2, 3));
    }

    function test_revert_membersOnly() public {
        committeeSync.vote(arr(1, 2, 3));
        vm.expectRevert(CommitteeSync.MembersOnly.selector);
        hoax(address(4));
        committeeSync.vote(arr(1, 2, 3));
    }

    function test_revert_invalidCommittee() public {
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.vote(new address[](0));
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.vote(new address[](1));
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.vote(new address[](2));
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.vote(new address[](256));
    }

    function test_vote_majority() public {
        committeeSync.vote(arr(1, 2, 3));

        hoax(address(1));
        committeeSync.vote(arr(1, 2, 10));
        hoax(address(2));
        committeeSync.vote(arr(1, 2, 10));
        assertEq(committeeSync.getCommittee(), arr(1, 2, 10));
    }

    function test_vote_perEpoch() public {
        committeeSync.vote(arr(1, 2, 3));

        vm.warp(block.timestamp + 1 hours + 59 minutes);
        hoax(address(1));
        committeeSync.vote(arr(1, 2, 10));
        vm.warp(block.timestamp + 2 hours + 1 minutes);
        hoax(address(2));
        committeeSync.vote(arr(1, 2, 10));

        assertEq(committeeSync.getCommittee(), arr(1, 2, 3));
    }
}
