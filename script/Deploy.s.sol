// SPDX-License-Identifier: MIT
pragma solidity 0.8.*;

import "forge-std/Script.sol";

import "src/CommitteeSync.sol";

contract Deploy is Script {
    function run() public returns (address committeeSync) {
        address owner = vm.envAddress("OWNER");
        bytes32 salt = vm.envOr("SALT", bytes32(0x1b565f5306ac3a9d0ab31d6806b69921fc5ed54fa6c6822015ac021a422cb025));
        bytes32 initCodeHash = hashInitCode(type(CommitteeSync).creationCode, abi.encode(owner));
        console.logBytes32(initCodeHash);

        address previousDeployment = _getExistingDeployment();
        console.log("prev deployment", previousDeployment);

        address expectedDeployment = vm.computeCreate2Address(salt, initCodeHash);
        if (expectedDeployment.code.length != 0) {
            console.log("already deployed", expectedDeployment);
            return expectedDeployment;
        }

        vm.broadcast();
        CommitteeSync deployed = new CommitteeSync{salt: salt}(owner);
        committeeSync = address(deployed);
        console.log("deployed", committeeSync);
    }

    function _getExistingDeployment() internal view returns (address existing) {
        try vm.getDeployment("CommitteeSync", uint64(block.chainid)) returns (address deployedAddress) {
            existing = deployedAddress;
        } catch {}
    }
}
