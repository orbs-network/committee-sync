// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

import "forge-std/Test.sol";

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "src/CommitteeSync.sol";
import "src/CommitteeSyncConfig.sol";
import "src/CommitteeSyncHash.sol";
import "src/CommitteeSyncValidation.sol";

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

    function emptyConfig() internal pure returns (CommitteeSyncConfig.Config[] memory config) {
        config = new CommitteeSyncConfig.Config[](0);
    }

    function nextNonce() internal view returns (uint256) {
        return committeeSync.nonce() + 1;
    }

    function signDigest(
        uint256 signerKey,
        address[] memory newCommittee,
        CommitteeSyncConfig.Config[] memory newConfig,
        uint256 digestNonce
    ) internal view returns (bytes memory) {
        bytes32 digest = committeeSync.hash(digestNonce, newCommittee, newConfig);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function hashCommittee(address[] memory newCommittee) internal pure returns (bytes32) {
        return CommitteeSyncHash.hashCommittee(newCommittee);
    }

    function hashConfig(CommitteeSyncConfig.Config[] memory newConfig) internal pure returns (bytes32) {
        return CommitteeSyncHash.hashConfig(newConfig);
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
        CommitteeSyncConfig.Config[] memory newConfig = emptyConfig();
        uint256 digestNonce = nextNonce();
        bytes32 structHash = keccak256(
            abi.encode(
                CommitteeSyncHash.DIGEST_TYPEHASH, digestNonce, hashCommittee(newCommittee), hashConfig(newConfig)
            )
        );
        bytes32 expected = MessageHashUtils.toTypedDataHash(CommitteeSyncHash.EIP712_DOMAIN_SEPARATOR, structHash);
        assertEq(committeeSync.hash(digestNonce, newCommittee, newConfig), expected);
    }

    function test_seedMemberCanBootstrapCommittee() public {
        assertEq(committeeSync.getCommittee().length, 1);
        assertEq(committeeSync.getCommittee()[0], deployer);
        address[] memory newCommittee = arr(5, 1);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = signDigest(deployerKey, newCommittee, emptyConfig(), nextNonce());
        committeeSync.sync(newCommittee, emptyConfig(), sigs);
        assertEq(committeeSync.getCommittee().length, 5);
        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_revert_signerNotMember() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signDigest(deployerKey, initialCommittee, emptyConfig(), nextNonce());
        committeeSync.sync(initialCommittee, emptyConfig(), initialSigs);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[2] = vm.addr(10);
        bytes[] memory badSigs = new bytes[](1);
        badSigs[0] = signDigest(deployerKey, newCommittee, emptyConfig(), nextNonce());
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientCount.selector, 0));
        committeeSync.sync(newCommittee, emptyConfig(), badSigs);
        assertEq(committeeSync.getCommittee(), initialCommittee);
    }

    function test_invalidSignatureSkipped() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signDigest(deployerKey, initialCommittee, emptyConfig(), nextNonce());
        committeeSync.sync(initialCommittee, emptyConfig(), initialSigs);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[2] = vm.addr(10);
        uint256 digestNonce = nextNonce();
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = signDigest(1, newCommittee, emptyConfig(), digestNonce);
        sigs[1] = signDigest(2, newCommittee, emptyConfig(), digestNonce);
        sigs[2] = hex"01";

        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientCount.selector, 2));
        committeeSync.sync(newCommittee, emptyConfig(), sigs);
    }

    function test_invalidSignatureSkippedButPasses() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signDigest(deployerKey, initialCommittee, emptyConfig(), nextNonce());
        committeeSync.sync(initialCommittee, emptyConfig(), initialSigs);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[4] = vm.addr(10);
        uint256 digestNonce = nextNonce();
        bytes[] memory sigs = new bytes[](4);
        sigs[0] = hex"01";
        sigs[1] = signDigest(1, newCommittee, emptyConfig(), digestNonce);
        sigs[2] = signDigest(2, newCommittee, emptyConfig(), digestNonce);
        sigs[3] = signDigest(3, newCommittee, emptyConfig(), digestNonce);

        committeeSync.sync(newCommittee, emptyConfig(), sigs);
        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_revert_invalidCommitteeSize() public {
        bytes[] memory emptySigs = new bytes[](0);
        vm.expectRevert(CommitteeSyncValidation.InvalidCommittee.selector);
        committeeSync.sync(arr(0, 1), emptyConfig(), emptySigs);
        vm.expectRevert(CommitteeSyncValidation.InvalidCommittee.selector);
        committeeSync.sync(arr(1, 1), emptyConfig(), emptySigs);
        vm.expectRevert(CommitteeSyncValidation.InvalidCommittee.selector);
        committeeSync.sync(arr(2, 1), emptyConfig(), emptySigs);
        vm.expectRevert(CommitteeSyncValidation.InvalidCommittee.selector);
        committeeSync.sync(arr(256, 1), emptyConfig(), emptySigs);
    }

    function test_acceptsMaxCommitteeSize() public {
        address[] memory maxCommittee = arr(255, 1);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = signDigest(deployerKey, maxCommittee, emptyConfig(), nextNonce());
        committeeSync.sync(maxCommittee, emptyConfig(), sigs);
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
        sigs[0] = signDigest(deployerKey, bad, emptyConfig(), nextNonce());
        committeeSync.sync(bad, emptyConfig(), sigs);
        assertEq(committeeSync.getCommittee(), bad);
    }

    function test_emptySigsRevert() public {
        address[] memory newCommittee = arr(5, 1);
        bytes[] memory emptySigs = new bytes[](0);
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientCount.selector, 0));
        committeeSync.sync(newCommittee, emptyConfig(), emptySigs);
    }

    function test_revert_zeroMemberCommittee() public {
        address[] memory bad = arr(5, 1);
        bad[0] = address(0);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = signDigest(deployerKey, bad, emptyConfig(), nextNonce());
        vm.expectRevert(CommitteeSyncValidation.InvalidCommittee.selector);
        committeeSync.sync(bad, emptyConfig(), sigs);
    }

    function test_sync_majority() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signDigest(deployerKey, initialCommittee, emptyConfig(), nextNonce());
        committeeSync.sync(initialCommittee, emptyConfig(), initialSigs);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[2] = vm.addr(10);
        uint256 digestNonce = nextNonce();
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = signDigest(1, newCommittee, emptyConfig(), digestNonce);
        sigs[1] = signDigest(2, newCommittee, emptyConfig(), digestNonce);
        sigs[2] = signDigest(3, newCommittee, emptyConfig(), digestNonce);
        committeeSync.sync(newCommittee, emptyConfig(), sigs);
        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_duplicateSignaturesDontIncreaseCount() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signDigest(deployerKey, initialCommittee, emptyConfig(), nextNonce());
        committeeSync.sync(initialCommittee, emptyConfig(), initialSigs);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[4] = vm.addr(10);
        uint256 digestNonce = nextNonce();
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = signDigest(1, newCommittee, emptyConfig(), digestNonce);
        sigs[1] = sigs[0];
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientCount.selector, 1));
        committeeSync.sync(newCommittee, emptyConfig(), sigs);
    }

    function test_replayOldNonceReverts() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signDigest(deployerKey, initialCommittee, emptyConfig(), nextNonce());
        committeeSync.sync(initialCommittee, emptyConfig(), initialSigs);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[2] = vm.addr(10);
        uint256 digestNonce = nextNonce();
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = signDigest(1, newCommittee, emptyConfig(), digestNonce);
        sigs[1] = signDigest(2, newCommittee, emptyConfig(), digestNonce);
        sigs[2] = signDigest(3, newCommittee, emptyConfig(), digestNonce);
        committeeSync.sync(newCommittee, emptyConfig(), sigs);

        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientCount.selector, 0));
        committeeSync.sync(newCommittee, emptyConfig(), sigs);

        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_syncs_appliesSequentially() public {
        address[] memory committee1 = arr(5, 1);
        address[] memory committee2 = arr(5, 1);
        committee2[2] = vm.addr(10);

        uint256 firstNonce = nextNonce();
        bytes[] memory sigs1 = new bytes[](1);
        sigs1[0] = signDigest(deployerKey, committee1, emptyConfig(), firstNonce);

        uint256 secondNonce = firstNonce + 1;
        bytes[] memory sigs2 = new bytes[](3);
        sigs2[0] = signDigest(1, committee2, emptyConfig(), secondNonce);
        sigs2[1] = signDigest(2, committee2, emptyConfig(), secondNonce);
        sigs2[2] = signDigest(3, committee2, emptyConfig(), secondNonce);

        CommitteeSync.Sync[] memory batch = new CommitteeSync.Sync[](2);
        batch[0] = CommitteeSync.Sync({committee: committee1, config: emptyConfig(), sigs: sigs1});
        batch[1] = CommitteeSync.Sync({committee: committee2, config: emptyConfig(), sigs: sigs2});

        committeeSync.syncs(batch);

        assertEq(committeeSync.getCommittee(), committee2);
        assertEq(committeeSync.nonce(), secondNonce);
    }

    function test_syncs_emptyNoop() public {
        address[] memory beforeCommittee = committeeSync.getCommittee();
        uint256 beforeNonce = committeeSync.nonce();
        CommitteeSync.Sync[] memory batch = new CommitteeSync.Sync[](0);

        committeeSync.syncs(batch);

        assertEq(committeeSync.nonce(), beforeNonce);
        assertEq(committeeSync.getCommittee(), beforeCommittee);
    }

    function test_syncs_revertsAllOrNothing() public {
        address[] memory committee1 = arr(5, 1);
        uint256 firstNonce = nextNonce();
        bytes[] memory sigs1 = new bytes[](1);
        sigs1[0] = signDigest(deployerKey, committee1, emptyConfig(), firstNonce);

        address[] memory committee2 = arr(5, 1);
        committee2[2] = vm.addr(10);
        uint256 secondNonce = firstNonce + 1;
        bytes[] memory sigs2 = new bytes[](2);
        sigs2[0] = signDigest(1, committee2, emptyConfig(), secondNonce);
        sigs2[1] = signDigest(2, committee2, emptyConfig(), secondNonce);

        CommitteeSync.Sync[] memory batch = new CommitteeSync.Sync[](2);
        batch[0] = CommitteeSync.Sync({committee: committee1, config: emptyConfig(), sigs: sigs1});
        batch[1] = CommitteeSync.Sync({committee: committee2, config: emptyConfig(), sigs: sigs2});

        address[] memory beforeCommittee = committeeSync.getCommittee();
        uint256 beforeNonce = committeeSync.nonce();

        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientCount.selector, 2));
        committeeSync.syncs(batch);

        assertEq(committeeSync.nonce(), beforeNonce);
        assertEq(committeeSync.getCommittee(), beforeCommittee);
    }

    function test_membership_afterUpdate() public {
        address[] memory newCommittee = arr(5, 1);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = signDigest(deployerKey, newCommittee, emptyConfig(), nextNonce());
        committeeSync.sync(newCommittee, emptyConfig(), sigs);

        assertTrue(committeeSync.isMember(vm.addr(1)));
        assertEq(committeeSync.indexOf(vm.addr(1)), 0);
        assertEq(committeeSync.indexOf(vm.addr(5)), 4);
        assertEq(committeeSync.indexOf(deployer), committeeSync.NOT_FOUND());
        assertFalse(committeeSync.isMember(deployer));
    }

    function test_sync_setsConfig() public {
        address[] memory newCommittee = arr(5, 1);
        CommitteeSyncConfig.Config[] memory newConfig = new CommitteeSyncConfig.Config[](2);
        newConfig[0] = CommitteeSyncConfig.Config({account: vm.addr(100), version: 1, value: abi.encode(uint256(123))});
        newConfig[1] = CommitteeSyncConfig.Config({account: vm.addr(101), version: 2, value: bytes("hi")});

        bytes[] memory sigs = new bytes[](1);
        sigs[0] = signDigest(deployerKey, newCommittee, newConfig, nextNonce());
        committeeSync.sync(newCommittee, newConfig, sigs);

        (uint8 version100, bytes memory value100) = committeeSync.config(vm.addr(100));
        (uint8 version101, bytes memory value101) = committeeSync.config(vm.addr(101));
        assertEq(value100, abi.encode(uint256(123)));
        assertEq(value101, bytes("hi"));
        assertEq(version100, 1);
        assertEq(version101, 2);
    }

    function test_updated_setAndNotChangedOnRevert() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signDigest(deployerKey, initialCommittee, emptyConfig(), nextNonce());

        vm.warp(1000);
        committeeSync.sync(initialCommittee, emptyConfig(), initialSigs);
        assertEq(committeeSync.updated(), 1000);

        address[] memory newCommittee = arr(5, 1);
        newCommittee[2] = vm.addr(10);
        uint256 digestNonce = nextNonce();
        bytes[] memory badSigs = new bytes[](2);
        badSigs[0] = signDigest(1, newCommittee, emptyConfig(), digestNonce);
        badSigs[1] = signDigest(2, newCommittee, emptyConfig(), digestNonce);

        vm.warp(2000);
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientCount.selector, 2));
        committeeSync.sync(newCommittee, emptyConfig(), badSigs);

        assertEq(committeeSync.updated(), 1000);
    }

    function test_thresholdRoundsUp() public {
        address[] memory initialCommittee = arr(6, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signDigest(deployerKey, initialCommittee, emptyConfig(), nextNonce());
        committeeSync.sync(initialCommittee, emptyConfig(), initialSigs);

        address[] memory newCommittee = arr(6, 1);
        newCommittee[5] = vm.addr(7);

        uint256 digestNonce = nextNonce();
        bytes[] memory threeSigs = new bytes[](3);
        threeSigs[0] = signDigest(1, newCommittee, emptyConfig(), digestNonce);
        threeSigs[1] = signDigest(2, newCommittee, emptyConfig(), digestNonce);
        threeSigs[2] = signDigest(3, newCommittee, emptyConfig(), digestNonce);
        vm.expectRevert(abi.encodeWithSelector(CommitteeSync.InsufficientCount.selector, 3));
        committeeSync.sync(newCommittee, emptyConfig(), threeSigs);

        bytes[] memory fourSigs = new bytes[](4);
        fourSigs[0] = signDigest(1, newCommittee, emptyConfig(), digestNonce);
        fourSigs[1] = signDigest(2, newCommittee, emptyConfig(), digestNonce);
        fourSigs[2] = signDigest(3, newCommittee, emptyConfig(), digestNonce);
        fourSigs[3] = signDigest(4, newCommittee, emptyConfig(), digestNonce);
        committeeSync.sync(newCommittee, emptyConfig(), fourSigs);
        assertEq(committeeSync.getCommittee(), newCommittee);
    }

    function test_revert_duplicateCommittee() public {
        address[] memory initialCommittee = arr(5, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signDigest(deployerKey, initialCommittee, emptyConfig(), nextNonce());
        committeeSync.sync(initialCommittee, emptyConfig(), initialSigs);

        address[] memory duplicateCommittee = arr(5, 1);
        duplicateCommittee[0] = vm.addr(1);
        duplicateCommittee[1] = vm.addr(1);
        duplicateCommittee[2] = vm.addr(1);
        duplicateCommittee[3] = vm.addr(2);
        duplicateCommittee[4] = vm.addr(2);

        uint256 digestNonce = nextNonce();
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = signDigest(1, duplicateCommittee, emptyConfig(), digestNonce);
        sigs[1] = signDigest(2, duplicateCommittee, emptyConfig(), digestNonce);
        sigs[2] = signDigest(3, duplicateCommittee, emptyConfig(), digestNonce);
        vm.expectRevert(CommitteeSyncValidation.InvalidCommittee.selector);
        committeeSync.sync(duplicateCommittee, emptyConfig(), sigs);
    }

    function test_hashOrderMatters() public view {
        address[] memory ordered = arr(5, 1);
        address[] memory shuffled = arr(5, 1);
        shuffled[0] = vm.addr(3);
        shuffled[1] = vm.addr(2);
        shuffled[2] = vm.addr(1);
        shuffled[3] = vm.addr(4);
        shuffled[4] = vm.addr(5);
        assertTrue(committeeSync.hash(1, ordered, emptyConfig()) != committeeSync.hash(1, shuffled, emptyConfig()));
    }

    function test_gas_sync_20_members() public {
        vm.pauseGasMetering();

        address[] memory committee20 = arr(20, 1);
        bytes[] memory initialSigs = new bytes[](1);
        initialSigs[0] = signDigest(deployerKey, committee20, emptyConfig(), nextNonce());
        committeeSync.sync(committee20, emptyConfig(), initialSigs);

        address[] memory newCommittee = arr(20, 1);
        newCommittee[19] = vm.addr(21);

        uint256 digestNonce = nextNonce();
        bytes[] memory sigs = new bytes[](20);
        for (uint256 i; i < 20; i++) {
            sigs[i] = signDigest(i + 1, newCommittee, emptyConfig(), digestNonce);
        }

        vm.resumeGasMetering();
        committeeSync.sync(newCommittee, emptyConfig(), sigs);
    }

    function test_init_initialMemberOnlyBeforeCommittee() public {
        vm.prank(deployer);
        committeeSync.init(100);
        assertEq(committeeSync.nonce(), 100);

        address[] memory newCommittee = arr(5, 1);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = signDigest(deployerKey, newCommittee, emptyConfig(), 101);
        committeeSync.sync(newCommittee, emptyConfig(), sigs);
        assertEq(committeeSync.nonce(), 101);
    }

    function test_init_revertNotInitialMember() public {
        vm.prank(vm.addr(0xB0B));
        vm.expectRevert(CommitteeSync.InitFailed.selector);
        committeeSync.init(1);
    }

    function test_init_revertCommitteeInitialized() public {
        address[] memory newCommittee = arr(5, 1);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = signDigest(deployerKey, newCommittee, emptyConfig(), nextNonce());
        committeeSync.sync(newCommittee, emptyConfig(), sigs);

        vm.prank(deployer);
        vm.expectRevert(CommitteeSync.InitFailed.selector);
        committeeSync.init(10);
    }

    function test_init_revertInvalidNonce() public {
        vm.prank(deployer);
        vm.expectRevert(CommitteeSync.InitFailed.selector);
        committeeSync.init(0);
    }
}
