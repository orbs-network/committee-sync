// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

import "forge-std/Test.sol";

import "src/CommitteeSync.sol";

contract CommitteeSyncTest is Test {
    address deployer;
    uint256 deployerKey;
    CommitteeSync public committeeSync;

    function setUp() public {
        deployerKey = 0xA11CE;
        deployer = vm.addr(deployerKey);
        hoax(deployer);
        committeeSync = new CommitteeSync{salt: 0}(deployer, 1 hours, 7000);
    }

    function arr(uint256 m0, uint256 m1, uint256 m2) internal pure returns (address[] memory newCommittee) {
        address a = vm.addr(m0);
        address b = vm.addr(m1);
        address c = vm.addr(m2);
        if (a > b) {
            address tmp = a;
            a = b;
            b = tmp;
        }
        if (b > c) {
            address tmp = b;
            b = c;
            c = tmp;
        }
        if (a > b) {
            address tmp = a;
            a = b;
            b = tmp;
        }
        newCommittee = new address[](3);
        newCommittee[0] = a;
        newCommittee[1] = b;
        newCommittee[2] = c;
    }

    function signProposal(uint256 signerKey, address[] memory newCommittee) internal view returns (bytes memory) {
        bytes32 proposal = committeeSync.hash(block.timestamp / committeeSync.epochLength(), newCommittee);
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", proposal));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function sigsFor(uint256 signerKey, address[] memory newCommittee) internal view returns (bytes[] memory sigs) {
        sigs = new bytes[](1);
        sigs[0] = signProposal(signerKey, newCommittee);
    }

    function test_deployerAffectsAddress() public {
        uint256 deployer2Key = 0xB0B;
        address deployer2 = vm.addr(deployer2Key);
        hoax(deployer2);
        CommitteeSync committeeSync2 = new CommitteeSync{salt: 0}(deployer2, 1 hours, 7000);
        assertNotEq(address(committeeSync), address(committeeSync2));
    }

    function test_revert_invalidConfig() public {
        vm.expectRevert(CommitteeSync.InvalidConfig.selector);
        new CommitteeSync{salt: 0}(deployer, 0, 7000);
        vm.expectRevert(CommitteeSync.InvalidConfig.selector);
        new CommitteeSync{salt: 0}(deployer, 1 hours, 0);
        vm.expectRevert(CommitteeSync.InvalidConfig.selector);
        new CommitteeSync{salt: 0}(deployer, 1 hours, 100_01);
    }

    function test_helpers() public view {
        assertTrue(committeeSync.isMember(deployer));
        assertFalse(committeeSync.isMember(vm.addr(0xB0B)));
        assertEq(committeeSync.indexOf(deployer), 0);
        assertEq(committeeSync.indexOf(vm.addr(0xB0B)), committeeSync.NOT_FOUND());

        address[] memory newCommittee = arr(1, 2, 3);
        bytes32 expected = keccak256(
            abi.encode(
                committeeSync.EIP191_DOMAIN_SEPARATOR(),
                committeeSync.PROPOSAL_TYPEHASH(),
                (block.timestamp / committeeSync.epochLength()),
                keccak256(abi.encode(newCommittee))
            )
        );
        assertEq(committeeSync.hash(block.timestamp / committeeSync.epochLength(), newCommittee), expected);
    }

    function test_initialDeployerOnlyCommittee() public {
        assertEq(committeeSync.getCommittee().length, 1);
        assertEq(committeeSync.getCommittee()[0], deployer);
        address[] memory newCommittee = arr(1, 2, 3);
        committeeSync.vote(newCommittee, sigsFor(deployerKey, newCommittee));
        assertEq(committeeSync.getCommittee().length, 3);
        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_revert_signerNotMember() public {
        address[] memory initialCommittee = arr(1, 2, 3);
        committeeSync.vote(initialCommittee, sigsFor(deployerKey, initialCommittee));

        address[] memory newCommittee = arr(1, 2, 10);
        bytes[] memory badSigs = sigsFor(deployerKey, newCommittee);
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 0));
        committeeSync.vote(newCommittee, badSigs);
        assertEq(committeeSync.getCommittee(), initialCommittee);
    }

    function test_revert_invalidCommittee() public {
        bytes[] memory emptySigs = new bytes[](0);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.vote(new address[](0), emptySigs);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.vote(new address[](1), emptySigs);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.vote(new address[](2), emptySigs);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.vote(new address[](256), emptySigs);
    }

    function test_unsortedCommitteeAllowed() public {
        address[] memory bad = new address[](3);
        bad[0] = vm.addr(2);
        bad[1] = vm.addr(1);
        bad[2] = vm.addr(3);
        committeeSync.vote(bad, sigsFor(deployerKey, bad));
        assertEq(committeeSync.getCommittee(), bad);
    }

    function test_emptySigsRevert() public {
        address[] memory newCommittee = arr(1, 2, 3);
        bytes[] memory emptySigs = new bytes[](0);
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 0));
        committeeSync.vote(newCommittee, emptySigs);
    }

    function test_zeroMemberCommitteeAllowed() public {
        address[] memory bad = new address[](3);
        bad[0] = address(0);
        bad[1] = vm.addr(1);
        bad[2] = vm.addr(2);
        committeeSync.vote(bad, sigsFor(deployerKey, bad));
        assertEq(committeeSync.getCommittee(), bad);
    }

    function test_vote_majority() public {
        address[] memory initialCommittee = arr(1, 2, 3);
        committeeSync.vote(initialCommittee, sigsFor(deployerKey, initialCommittee));

        address[] memory newCommittee = arr(1, 2, 10);
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = signProposal(1, newCommittee);
        sigs[1] = signProposal(2, newCommittee);
        committeeSync.vote(newCommittee, sigs);
        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_duplicateSignaturesDontIncreaseCount() public {
        address[] memory initialCommittee = arr(1, 2, 3);
        committeeSync.vote(initialCommittee, sigsFor(deployerKey, initialCommittee));

        address[] memory newCommittee = arr(1, 2, 10);
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = signProposal(1, newCommittee);
        sigs[1] = sigs[0];
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 1));
        committeeSync.vote(newCommittee, sigs);
    }

    function test_vote_perEpoch() public {
        address[] memory initialCommittee = arr(1, 2, 3);
        committeeSync.vote(initialCommittee, sigsFor(deployerKey, initialCommittee));

        address[] memory newCommittee = arr(1, 2, 10);
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = signProposal(1, newCommittee);
        sigs[1] = signProposal(2, newCommittee);
        vm.warp(block.timestamp + 2 hours + 1 minutes);
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 0));
        committeeSync.vote(newCommittee, sigs);

        assertEq(committeeSync.getCommittee(), initialCommittee);
    }
}
