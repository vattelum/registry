// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {Registry} from "../src/Registry.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        Registry registry = new Registry(deployer);
        console.log("Registry deployed at:", address(registry));

        registry.addCategory("Universal Standards");
        registry.addCategory("Blockchain Standards");
        registry.addCategory("Governing Standards");
        console.log("Seeded 3 categories");

        vm.stopBroadcast();
    }
}
