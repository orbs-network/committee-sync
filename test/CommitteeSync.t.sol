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

    function arr(uint256 count, uint256 start) internal pure returns (address[] memory newCommittee) {
        newCommittee = new address[](count);
        for (uint256 i; i < count; i++) {
            newCommittee[i] = vm.addr(start + i);
        }
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

        address[] memory newCommittee = arr(5, 1);
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

    function test_seedMemberCanBootstrapCommittee() public {
        assertEq(committeeSync.getCommittee().length, 1);
        assertEq(committeeSync.getCommittee()[0], deployer);
        address[] memory newCommittee = arr(5, 1);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = signProposal(deployerKey, newCommittee, nextNonce());
        committeeSync.sync(newCommittee, sigs);
        assertEq(committeeSync.getCommittee().length, 5);
        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_revert_signerNotMember() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signProposal(deployerKey, initialCommittee, nextNonce());
        committeeSync.sync(initialCommittee, initialSigs);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[2] = vm.addr(10);
        bytes[] memory badSigs = new bytes[](1);
        badSigs[0] = signProposal(deployerKey, newCommittee, nextNonce());
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 0));
        committeeSync.sync(newCommittee, badSigs);
        assertEq(committeeSync.getCommittee(), initialCommittee);
    }

    function test_invalidSignatureSkipped() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signProposal(deployerKey, initialCommittee, nextNonce());
        committeeSync.sync(initialCommittee, initialSigs);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[2] = vm.addr(10);
        uint256 proposalNonce = nextNonce();
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = signProposal(1, newCommittee, proposalNonce);
        sigs[1] = signProposal(2, newCommittee, proposalNonce);
        sigs[2] = hex"01";

        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 2));
        committeeSync.sync(newCommittee, sigs);
    }

    function test_invalidSignatureSkippedButPasses() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signProposal(deployerKey, initialCommittee, nextNonce());
        committeeSync.sync(initialCommittee, initialSigs);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[4] = vm.addr(10);
        uint256 proposalNonce = nextNonce();
        bytes[] memory sigs = new bytes[](4);
        sigs[0] = hex"01";
        sigs[1] = signProposal(1, newCommittee, proposalNonce);
        sigs[2] = signProposal(2, newCommittee, proposalNonce);
        sigs[3] = signProposal(3, newCommittee, proposalNonce);

        committeeSync.sync(newCommittee, sigs);
        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_revert_invalidCommitteeSize() public {
        bytes[] memory emptySigs = new bytes[](0);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.sync(arr(0, 1), emptySigs);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.sync(arr(1, 1), emptySigs);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.sync(arr(2, 1), emptySigs);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.sync(arr(3, 1), emptySigs);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.sync(arr(4, 1), emptySigs);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.sync(arr(256, 1), emptySigs);
    }

    function test_acceptsMaxCommitteeSize() public {
        address[] memory maxCommittee = arr(255, 1);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = signProposal(deployerKey, maxCommittee, nextNonce());
        committeeSync.sync(maxCommittee, sigs);
        assertEq(committeeSync.getCommittee().length, 255);
    }

    function test_unsortedCommitteeAllowed() public {
        address[] memory bad = arr(5, 1);
        bad[0] = vm.addr(2);
        bad[1] = vm.addr(1);
        bad[2] = vm.addr(5);
        bad[3] = vm.addr(3);
        bad[4] = vm.addr(4);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = signProposal(deployerKey, bad, nextNonce());
        committeeSync.sync(bad, sigs);
        assertEq(committeeSync.getCommittee(), bad);
    }

    function test_emptySigsRevert() public {
        address[] memory newCommittee = arr(5, 1);
        bytes[] memory emptySigs = new bytes[](0);
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 0));
        committeeSync.sync(newCommittee, emptySigs);
    }

    function test_revert_zeroMemberCommittee() public {
        address[] memory bad = arr(5, 1);
        bad[0] = address(0);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = signProposal(deployerKey, bad, nextNonce());
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.sync(bad, sigs);
    }

    function test_vote_majority() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signProposal(deployerKey, initialCommittee, nextNonce());
        committeeSync.sync(initialCommittee, initialSigs);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[2] = vm.addr(10);
        uint256 proposalNonce = nextNonce();
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = signProposal(1, newCommittee, proposalNonce);
        sigs[1] = signProposal(2, newCommittee, proposalNonce);
        sigs[2] = signProposal(3, newCommittee, proposalNonce);
        committeeSync.sync(newCommittee, sigs);
        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_duplicateSignaturesDontIncreaseCount() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signProposal(deployerKey, initialCommittee, nextNonce());
        committeeSync.sync(initialCommittee, initialSigs);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[4] = vm.addr(10);
        uint256 proposalNonce = nextNonce();
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = signProposal(1, newCommittee, proposalNonce);
        sigs[1] = sigs[0];
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 1));
        committeeSync.sync(newCommittee, sigs);
    }

    function test_replayOldNonceReverts() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signProposal(deployerKey, initialCommittee, nextNonce());
        committeeSync.sync(initialCommittee, initialSigs);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[2] = vm.addr(10);
        uint256 proposalNonce = nextNonce();
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = signProposal(1, newCommittee, proposalNonce);
        sigs[1] = signProposal(2, newCommittee, proposalNonce);
        sigs[2] = signProposal(3, newCommittee, proposalNonce);
        committeeSync.sync(newCommittee, sigs);

        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 0));
        committeeSync.sync(newCommittee, sigs);

        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_syncs_appliesSequentially() public {
        address[] memory committee1 = arr(5, 1);
        address[] memory committee2 = arr(5, 1);
        committee2[2] = vm.addr(10);

        uint256 firstNonce = nextNonce();
        bytes[] memory sigs1 = new bytes[](1);
        sigs1[0] = signProposal(deployerKey, committee1, firstNonce);

        uint256 secondNonce = firstNonce + 1;
        bytes[] memory sigs2 = new bytes[](3);
        sigs2[0] = signProposal(1, committee2, secondNonce);
        sigs2[1] = signProposal(2, committee2, secondNonce);
        sigs2[2] = signProposal(3, committee2, secondNonce);

        CommitteeSync.Vote[] memory votes = new CommitteeSync.Vote[](2);
        votes[0] = CommitteeSync.Vote({committee: committee1, sigs: sigs1});
        votes[1] = CommitteeSync.Vote({committee: committee2, sigs: sigs2});

        committeeSync.syncs(votes);

        assertEq(committeeSync.getCommittee(), committee2);
        assertEq(committeeSync.nonce(), secondNonce);
    }

    function test_syncs_emptyNoop() public {
        address[] memory beforeCommittee = committeeSync.getCommittee();
        uint256 beforeNonce = committeeSync.nonce();
        CommitteeSync.Vote[] memory votes = new CommitteeSync.Vote[](0);

        committeeSync.syncs(votes);

        assertEq(committeeSync.nonce(), beforeNonce);
        assertEq(committeeSync.getCommittee(), beforeCommittee);
    }

    function test_syncs_revertsAllOrNothing() public {
        address[] memory committee1 = arr(5, 1);
        uint256 firstNonce = nextNonce();
        bytes[] memory sigs1 = new bytes[](1);
        sigs1[0] = signProposal(deployerKey, committee1, firstNonce);

        address[] memory committee2 = arr(5, 1);
        committee2[2] = vm.addr(10);
        uint256 secondNonce = firstNonce + 1;
        bytes[] memory sigs2 = new bytes[](2);
        sigs2[0] = signProposal(1, committee2, secondNonce);
        sigs2[1] = signProposal(2, committee2, secondNonce);

        CommitteeSync.Vote[] memory votes = new CommitteeSync.Vote[](2);
        votes[0] = CommitteeSync.Vote({committee: committee1, sigs: sigs1});
        votes[1] = CommitteeSync.Vote({committee: committee2, sigs: sigs2});

        address[] memory beforeCommittee = committeeSync.getCommittee();
        uint256 beforeNonce = committeeSync.nonce();

        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 2));
        committeeSync.syncs(votes);

        assertEq(committeeSync.nonce(), beforeNonce);
        assertEq(committeeSync.getCommittee(), beforeCommittee);
    }

    function test_membership_afterUpdate() public {
        address[] memory newCommittee = arr(5, 1);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = signProposal(deployerKey, newCommittee, nextNonce());
        committeeSync.sync(newCommittee, sigs);

        assertTrue(committeeSync.isMember(vm.addr(1)));
        assertEq(committeeSync.indexOf(vm.addr(1)), 0);
        assertEq(committeeSync.indexOf(vm.addr(5)), 4);
        assertEq(committeeSync.indexOf(deployer), committeeSync.NOT_FOUND());
        assertFalse(committeeSync.isMember(deployer));
    }

    function test_updated_setAndNotChangedOnRevert() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signProposal(deployerKey, initialCommittee, nextNonce());

        vm.warp(1000);
        committeeSync.sync(initialCommittee, initialSigs);
        assertEq(committeeSync.updated(), 1000);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[2] = vm.addr(10);
        uint256 proposalNonce = nextNonce();
        bytes[] memory badSigs = new bytes[](2);
        badSigs[0] = signProposal(1, newCommittee, proposalNonce);
        badSigs[1] = signProposal(2, newCommittee, proposalNonce);

        vm.warp(2000);
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 2));
        committeeSync.sync(newCommittee, badSigs);

        assertEq(committeeSync.updated(), 1000);
    }

    function test_thresholdRoundsUp() public {
        address[] memory initialCommittee = arr(6, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signProposal(deployerKey, initialCommittee, nextNonce());
        committeeSync.sync(initialCommittee, initialSigs);

        address[] memory newCommittee = arr(6, 1);
        newCommittee[5] = vm.addr(7);

        uint256 proposalNonce = nextNonce();
        bytes[] memory threeSigs = new bytes[](3);
        threeSigs[0] = signProposal(1, newCommittee, proposalNonce);
        threeSigs[1] = signProposal(2, newCommittee, proposalNonce);
        threeSigs[2] = signProposal(3, newCommittee, proposalNonce);
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientVotes.selector, 3));
        committeeSync.sync(newCommittee, threeSigs);

        bytes[] memory fourSigs = new bytes[](4);
        fourSigs[0] = signProposal(1, newCommittee, proposalNonce);
        fourSigs[1] = signProposal(2, newCommittee, proposalNonce);
        fourSigs[2] = signProposal(3, newCommittee, proposalNonce);
        fourSigs[3] = signProposal(4, newCommittee, proposalNonce);
        committeeSync.sync(newCommittee, fourSigs);
        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_revert_duplicateCommittee() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signProposal(deployerKey, initialCommittee, nextNonce());
        committeeSync.sync(initialCommittee, initialSigs);

        address[] memory duplicateCommittee = arr(5, 1);
        duplicateCommittee[0] = vm.addr(1);
        duplicateCommittee[1] = vm.addr(1);
        duplicateCommittee[2] = vm.addr(1);
        duplicateCommittee[3] = vm.addr(2);
        duplicateCommittee[4] = vm.addr(2);

        uint256 proposalNonce = nextNonce();
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = signProposal(1, duplicateCommittee, proposalNonce);
        sigs[1] = signProposal(2, duplicateCommittee, proposalNonce);
        sigs[2] = signProposal(3, duplicateCommittee, proposalNonce);
        vm.expectRevert(CommitteeSync.InvalidCommittee.selector);
        committeeSync.sync(duplicateCommittee, sigs);
    }

    function test_hashOrderMatters() public view {
        address[] memory ordered = arr(5, 1);
        address[] memory shuffled = arr(5, 1);
        shuffled[0] = vm.addr(3);
        shuffled[1] = vm.addr(2);
        shuffled[2] = vm.addr(1);
        shuffled[3] = vm.addr(4);
        shuffled[4] = vm.addr(5);
        assertTrue(committeeSync.hash(1, ordered) != committeeSync.hash(1, shuffled));
    }

    function test_gas_vote_20_members() public {
        vm.pauseGasMetering();

        address[] memory committee20 = arr(20, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signProposal(deployerKey, committee20, nextNonce());
        committeeSync.sync(committee20, initialSigs);

        address[] memory newCommittee = arr(20, 1);
        newCommittee[19] = vm.addr(21);

        uint256 proposalNonce = nextNonce();
        bytes[] memory sigs = new bytes[](20);
        for (uint256 i; i < 20; i++) {
            sigs[i] = signProposal(i + 1, newCommittee, proposalNonce);
        }

        vm.resumeGasMetering();
        committeeSync.sync(newCommittee, sigs);
    }
}
