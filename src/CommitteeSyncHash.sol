// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {CommitteeSyncConfig} from "./CommitteeSyncConfig.sol";

/// @title CommitteeSyncHash
/// @notice Hashing utilities for CommitteeSync digests.
/// @dev EIP-712 struct hashing with a name/version-only domain separator.
library CommitteeSyncHash {
    string internal constant NAME = "OrbsCommitteeSync";
    string internal constant VERSION = "0";

    string internal constant EIP712_DOMAIN_TYPE = "EIP712Domain(string name,string version)";
    string internal constant CONFIG_TYPE = "Config(address account,uint8 version,bytes value)";
    string internal constant DIGEST_TYPE = "Digest(uint256 nonce,address[] committee,Config[] config)";

    bytes32 public constant EIP712_DOMAIN_TYPEHASH = keccak256(bytes(EIP712_DOMAIN_TYPE));
    bytes32 public constant EIP712_DOMAIN_SEPARATOR =
        keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION))));
    bytes32 public constant CONFIG_TYPEHASH = keccak256(bytes(CONFIG_TYPE));
    bytes32 public constant DIGEST_TYPEHASH = keccak256(abi.encodePacked(DIGEST_TYPE, CONFIG_TYPE));

    /// @notice Returns the EIP-712 digest for a committee/config update.
    function hash(uint256 digestNonce, address[] memory newCommittee, CommitteeSyncConfig.Config[] memory newConfig)
        internal
        pure
        returns (bytes32)
    {
        bytes32 structHash =
            keccak256(abi.encode(DIGEST_TYPEHASH, digestNonce, hashCommittee(newCommittee), hashConfig(newConfig)));
        return MessageHashUtils.toTypedDataHash(EIP712_DOMAIN_SEPARATOR, structHash);
    }

    /// @notice Hashes an address array as an EIP-712 array.
    function hashCommittee(address[] memory newCommittee) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](newCommittee.length);
        for (uint256 i; i < newCommittee.length; i++) {
            hashes[i] = bytes32(uint256(uint160(newCommittee[i])));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    /// @notice Hashes a Config[] as an EIP-712 array.
    function hashConfig(CommitteeSyncConfig.Config[] memory newConfig) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](newConfig.length);
        for (uint256 i; i < newConfig.length; i++) {
            hashes[i] = keccak256(
                abi.encode(CONFIG_TYPEHASH, newConfig[i].account, newConfig[i].version, keccak256(newConfig[i].value))
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }
}
