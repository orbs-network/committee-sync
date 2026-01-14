// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

/// @title CommitteeSyncValidation
/// @notice Validation helpers for CommitteeSync.
library CommitteeSyncValidation {
    uint256 public constant MIN_SIZE = 3;
    uint256 public constant MAX_SIZE = type(uint8).max;

    error InvalidCommittee();

    /// @notice Reverts if the committee is empty, too large, has zero addresses, or duplicates.
    function validate(address[] memory newCommittee) internal pure {
        uint256 length = newCommittee.length;
        if (length < MIN_SIZE || length > MAX_SIZE) revert InvalidCommittee();
        for (uint256 i; i < length; i++) {
            address member = newCommittee[i];
            if (member == address(0)) revert InvalidCommittee();
            for (uint256 j; j < i; j++) {
                if (newCommittee[j] == member) revert InvalidCommittee();
            }
        }
    }
}
