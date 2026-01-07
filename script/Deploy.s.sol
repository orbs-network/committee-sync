// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

import "forge-std/Script.sol";

import "src/CommitteeSync.sol";

contract Deploy is Script {
    function run() public returns (address committeeSync) {
        vm.broadcast();
        CommitteeSync deployed =
            new CommitteeSync{salt: 0}(vm.envAddress("OWNER"), vm.envUint("EPOCH_LENGTH"), vm.envUint("THRESHOLD_BPS"));
        committeeSync = address(deployed);
    }
}
