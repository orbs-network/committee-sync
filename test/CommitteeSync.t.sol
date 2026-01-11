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
        committeeSync = new CommitteeSync{salt: 0}(deployer);
    }

    function arr(uint256 m0, uint256 m1, uint256 m2, uint256 m3, uint256 m4)
        internal
        pure
        returns (address[] memory newCommittee)
    {
        newCommittee = new address[](5);
        newCommittee[0] = vm.addr(m0);
        newCommittee[1] = vm.addr(m1);
        newCommittee[2] = vm.addr(m2);
        newCommittee[3] = vm.addr(m3);
        newCommittee[4] = vm.addr(m4);
    }

    function nextNonce() internal view returns (uint256) {
        return committeeSync.nonce() + 1;
    }

    function signProposal(uint256 signerKey, address[] memory newCommittee, uint256 proposalNonce)
        internal
        view
        returns (bytes memory)
    {
        bytes32 proposal = committeeSync.hash(proposalNonce, newCommittee);
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", proposal));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function sigsFor(uint256 signerKey, address[] memory newCommittee, uint256 proposalNonce)
        internal
        view
        returns (bytes[] memory sigs)
    {
        sigs = new bytes[](1);
        sigs[0] = signProposal(signerKey, newCommittee, proposalNonce);
    }

    function test_deployerAffectsAddress() public {
        uint256 deployer2Key = 0xB0B;
        address deployer2 = vm.addr(deployer2Key);
        hoax(deployer2);
        CommitteeSync committeeSync2 = new CommitteeSync{salt: 0}(deployer2);
        assertNotEq(address(committeeSync), address(committeeSync2));
    }

    function test_helpers() public view {
        assertTrue(committeeSync.isMember(deployer));
        assertFalse(committeeSync.isMember(vm.addr(0xB0B)));
        assertEq(committeeSync.indexOf(deployer), 0);
        assertEq(committeeSync.indexOf(vm.addr(0xB0B)), committeeSync.NOT_FOUND());

        address[] memory newCommittee = arr(1, 2, 3, 4, 5);
        uint256 proposalNonce = nextNonce();
        bytes32 expected = keccak256(
            abi.encode(
                committeeSync.EIP191_DOMAIN_SEPARATOR(),
                committeeSync.PROPOSAL_TYPEHASH(),
                proposalNonce,
                keccak256(abi.encode(newCommittee))
            )
        );
        assertEq(committeeSync.hash(proposalNonce, newCommittee), expected);
    }

    function test_initialDeployerOnlyCommittee() public {
        assertEq(committeeSync.getCommittee().length, 1);
        assertEq(committeeSync.getCommittee()[0], deployer);
        address[] memory newCommittee = arr(1, 2, 3, 4, 5);
        committeeSync.vote(newCommittee, sigsFor(deployerKey, newCommittee, nextNonce()));
        assertEq(committeeSync.getCommittee().length, 5);
        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_revert_signerNotMember() public {
        address[] memory initialCommittee = arr(1, 2, 3, 4, 5);
        committeeSync.vote(initialCommittee, sigsFor(deployerKey, initialCommittee, nextNonce()));

        address[] memory newCommittee = arr(1, 2, 10, 4, 5);
        bytes[] memory badSigs = sigsFor(deployerKey, newCommittee, nextNonce());
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
        committeeSync.vote(new address[](3), emptySigs);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.vote(new address[](4), emptySigs);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.vote(new address[](256), emptySigs);
    }

    function test_unsortedCommitteeAllowed() public {
        address[] memory bad = new address[](5);
        bad[0] = vm.addr(2);
        bad[1] = vm.addr(1);
        bad[2] = vm.addr(5);
        bad[3] = vm.addr(3);
        bad[4] = vm.addr(4);
        committeeSync.vote(bad, sigsFor(deployerKey, bad, nextNonce()));
        assertEq(committeeSync.getCommittee(), bad);
    }

    function test_emptySigsRevert() public {
        address[] memory newCommittee = arr(1, 2, 3, 4, 5);
        bytes[] memory emptySigs = new bytes[](0);
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 0));
        committeeSync.vote(newCommittee, emptySigs);
    }

    function test_zeroMemberCommitteeAllowed() public {
        address[] memory bad = new address[](5);
        bad[0] = address(0);
        bad[1] = vm.addr(1);
        bad[2] = vm.addr(2);
        bad[3] = vm.addr(3);
        bad[4] = vm.addr(4);
        committeeSync.vote(bad, sigsFor(deployerKey, bad, nextNonce()));
        assertEq(committeeSync.getCommittee(), bad);
    }

    function test_vote_majority() public {
        address[] memory initialCommittee = arr(1, 2, 3, 4, 5);
        committeeSync.vote(initialCommittee, sigsFor(deployerKey, initialCommittee, nextNonce()));

        address[] memory newCommittee = arr(1, 2, 10, 4, 5);
        uint256 proposalNonce = nextNonce();
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = signProposal(1, newCommittee, proposalNonce);
        sigs[1] = signProposal(2, newCommittee, proposalNonce);
        sigs[2] = signProposal(3, newCommittee, proposalNonce);
        committeeSync.vote(newCommittee, sigs);
        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_duplicateSignaturesDontIncreaseCount() public {
        address[] memory initialCommittee = new address[](5);
        initialCommittee[0] = vm.addr(1);
        initialCommittee[1] = vm.addr(2);
        initialCommittee[2] = vm.addr(3);
        initialCommittee[3] = vm.addr(4);
        initialCommittee[4] = vm.addr(5);
        committeeSync.vote(initialCommittee, sigsFor(deployerKey, initialCommittee, nextNonce()));

        address[] memory newCommittee = new address[](5);
        newCommittee[0] = vm.addr(1);
        newCommittee[1] = vm.addr(2);
        newCommittee[2] = vm.addr(3);
        newCommittee[3] = vm.addr(4);
        newCommittee[4] = vm.addr(10);
        uint256 proposalNonce = nextNonce();
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = signProposal(1, newCommittee, proposalNonce);
        sigs[1] = sigs[0];
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 1));
        committeeSync.vote(newCommittee, sigs);
    }

    function test_replayOldNonceReverts() public {
        address[] memory initialCommittee = arr(1, 2, 3, 4, 5);
        committeeSync.vote(initialCommittee, sigsFor(deployerKey, initialCommittee, nextNonce()));

        address[] memory newCommittee = arr(1, 2, 10, 4, 5);
        uint256 proposalNonce = nextNonce();
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = signProposal(1, newCommittee, proposalNonce);
        sigs[1] = signProposal(2, newCommittee, proposalNonce);
        sigs[2] = signProposal(3, newCommittee, proposalNonce);
        committeeSync.vote(newCommittee, sigs);

        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 0));
        committeeSync.vote(newCommittee, sigs);

        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_votes_appliesSequentially() public {
        address[] memory committee1 = arr(1, 2, 3, 4, 5);
        address[] memory committee2 = arr(1, 2, 10, 4, 5);

        uint256 firstNonce = nextNonce();
        bytes[] memory sigs1 = sigsFor(deployerKey, committee1, firstNonce);

        uint256 secondNonce = firstNonce + 1;
        bytes[] memory sigs2 = new bytes[](3);
        sigs2[0] = signProposal(1, committee2, secondNonce);
        sigs2[1] = signProposal(2, committee2, secondNonce);
        sigs2[2] = signProposal(3, committee2, secondNonce);

        CommitteeSync.Vote[] memory votes = new CommitteeSync.Vote[](2);
        votes[0] = CommitteeSync.Vote({committee: committee1, sigs: sigs1});
        votes[1] = CommitteeSync.Vote({committee: committee2, sigs: sigs2});

        committeeSync.votes(votes);

        assertEq(committeeSync.getCommittee(), committee2);
        assertEq(committeeSync.nonce(), secondNonce);
    }
}
