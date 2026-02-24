// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

/// @title CommitteeSyncConfig
/// @notice Config utilities for CommitteeSync.
library CommitteeSyncConfig {
    struct Config {
        bytes32 key;
        address account;
        bytes value;
    }

    /// @notice Applies a batch of config updates to storage.
    function save(mapping(bytes32 => mapping(address => bytes)) storage config, Config[] memory updates) internal {
        for (uint256 i; i < updates.length; i++) {
            config[updates[i].key][updates[i].account] = updates[i].value;
        }
    }
}
