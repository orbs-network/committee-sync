// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

/// @title CommitteeSyncConfig
/// @notice Config utilities for CommitteeSync.
library CommitteeSyncConfig {
    struct Config {
        address account;
        uint8 version;
        bytes value;
    }

    struct StoredConfig {
        uint8 version;
        bytes value;
    }

    /// @notice Applies a batch of config updates to storage.
    function save(mapping(address => StoredConfig) storage config, Config[] memory updates) internal {
        for (uint256 i; i < updates.length; i++) {
            config[updates[i].account].version = updates[i].version;
            config[updates[i].account].value = updates[i].value;
        }
    }
}
