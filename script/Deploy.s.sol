// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

import "forge-std/Script.sol";

import "src/CommitteeSync.sol";

contract Deploy is Script {
    function run() public returns (address committeeSync) {
        address owner = vm.envAddress("OWNER");
        console.logBytes32(hashInitCode(type(CommitteeSync).creationCode, abi.encode(owner)));

        vm.broadcast();
        CommitteeSync deployed = new CommitteeSync{salt: 0}(owner);
        committeeSync = address(deployed);
    }
}
