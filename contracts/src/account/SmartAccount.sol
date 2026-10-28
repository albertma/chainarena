// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ISmartAccount } from "../interfaces/ISmartAccount.sol";

/// @title SmartAccount — P1 骨架（passkey owner 存储 + ERC-1271 占位）
/// @notice ⚠️ P1-A（AccountFactory）story 的最小可测实现：
///         - initialize 写入 passkey 公钥（后续 WebAuthnValidator 验签的注册源）
///         - isValidSignature 为占位（恒拒），P1-B（Signin）接入验签模块后实现
///         - 账户实现 P1 冻结（分期原则），扩展只走「启用已部署模块」
/// @dev 部署形态：ERC1967Proxy → 本实现（由 AccountFactory CREATE2 铸出）
contract SmartAccount is Initializable, IERC1271, ISmartAccount {
    /// @notice owner passkey 公钥（secp256r1）
    bytes32 public pubKeyX;
    bytes32 public pubKeyY;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc ISmartAccount
    function initialize(bytes32 _pubKeyX, bytes32 _pubKeyY) external initializer {
        pubKeyX = _pubKeyX;
        pubKeyY = _pubKeyY;
    }

    /// @notice ERC-1271 占位实现：P1 骨架阶段恒拒（magic = 0xffffffff）
    /// @dev P1-B 接入 WebAuthnValidator（RIP-7212 precompile 0x100）后替换
    function isValidSignature(
        bytes32,
        /* hash */
        bytes calldata /* signature */
    )
        external
        pure
        override
        returns (bytes4)
    {
        return 0xffffffff; // InvalidSignature
    }

    /// @notice 账户可收款（P2：奖池、退款；P1 预留）
    receive() external payable { }
}
