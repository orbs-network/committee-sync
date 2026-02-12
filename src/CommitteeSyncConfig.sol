// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

/// @title CommitteeSyncConfig
/// @notice Config utilities for CommitteeSync.
library CommitteeSyncConfig {
    struct Config {
        address account;
        bytes32 key;
        bytes value;
    }

    /// @notice Applies a batch of config updates to storage.
    function save(mapping(address => mapping(bytes32 => bytes)) storage config, Config[] memory updates) internal {
        for (uint256 i; i < updates.length; i++) {
            config[updates[i].account][updates[i].key] = updates[i].value;
        }
    }
}
