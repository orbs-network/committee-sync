// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

import "forge-std/Script.sol";

import "src/CommitteeSync.sol";

contract Deploy is Script {
    function run() public returns (address committeeSync) {
        address owner = vm.envAddress("OWNER");
        bytes32 salt = vm.envOr("SALT", bytes32(0x75e3be5a0037b707320866345cfb398f5401fc5736077dcdadfa9e4c6737210b));
        console.logBytes32(hashInitCode(type(CommitteeSync).creationCode, abi.encode(owner)));

        vm.broadcast();
        CommitteeSync deployed = new CommitteeSync{salt: salt}(owner);
        committeeSync = address(deployed);
    }
}
