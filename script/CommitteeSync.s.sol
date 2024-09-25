// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import "../src/CommitteeSync.sol";

contract CounterScript is Script {
    CommitteeSync public committeeSync;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();


        vm.stopBroadcast();
    }
}
