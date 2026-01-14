// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

import "forge-std/Script.sol";

import "src/CommitteeSync.sol";

contract Deploy is Script {
    function run() public returns (address committeeSync) {
        address owner = vm.envAddress("OWNER");
        bytes32 salt = vm.envOr("SALT", bytes32(0xb21874a5697f0a1440eb94eba22be986c4843cf05bfdd0db15d3ad4fb39b7f59));
        console.logBytes32(hashInitCode(type(CommitteeSync).creationCode, abi.encode(owner)));

        vm.broadcast();
        CommitteeSync deployed = new CommitteeSync{salt: salt}(owner);
        committeeSync = address(deployed);
    }
}
