// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { SmartAccount } from "../src/account/SmartAccount.sol";
import { AccountFactory } from "../src/account/AccountFactory.sol";

/// @title P1-A 部署脚本：SmartAccount 实现 + AccountFactory
/// @notice 上线顺序遵循 docs/development-phases.md §9.2：实现先行（P1 冻结），工厂随后。
///         使用：
///           forge script script/DeployAccounts.s.sol --rpc-url $BASE_SEPOLIA --broadcast --verify
contract DeployAccounts is Script {
    function run() public returns (SmartAccount impl, AccountFactory factory) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        impl = new SmartAccount();
        factory = new AccountFactory(impl);

        vm.stopBroadcast();

        console2.log("SmartAccount implementation:", address(impl));
        console2.log("AccountFactory            :", address(factory));
        console2.log("next deployer nonce       :", vm.getNonce(msg.sender));
    }
}
