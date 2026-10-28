// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISmartAccount — P1 账户实现的最小接口（供 AccountFactory 编码 initCode）
/// @notice 仅冻结 P1 冻结面：initialize(bytes32,bytes32)。
///         后续模块（WebAuthnValidator / RecoveryModule / MatchSessionValidator）
///         通过「启用已部署模块」扩展，不改本接口（docs/development-phases.md §1 分期原则 2）。
interface ISmartAccount {
    /// @notice 由 AccountFactory 部署的 ERC1967 代理在构造时调用，写入 passkey 公钥
    /// @param pubKeyX secp256r1 公钥 X 坐标（P-256，非压缩）
    /// @param pubKeyY secp256r1 公钥 Y 坐标
    function initialize(bytes32 pubKeyX, bytes32 pubKeyY) external;
}
