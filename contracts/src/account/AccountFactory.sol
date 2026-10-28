// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ISmartAccount } from "../interfaces/ISmartAccount.sol";

/// @title AccountFactory — 玩家智能账户的 CREATE2 确定性铸造器
/// @notice 地址确定性公式（与客户端 @arena/core 严格镜像，docs/tech/01-signup.md §2.1）：
///
///         salt   = uint256(keccak256(pubKeyX ‖ pubKeyY ‖ userSalt))
///         initCode = ERC1967Proxy creationCode ‖ abi.encode(impl, abi.encodeCall(initialize,(x,y)))
///         addr   = keccak256(0xff ‖ factory ‖ bytes32(salt) ‖ keccak256(initCode))[12:]
///
///         同一 passkey + 同一 userSalt ⇒ 永远同一地址（中断续跑的根基）。
/// @dev 三大职责（docs/tech/01-signup.md §1.2）：
///      ① counterfactual 惰性部署（getAddress 先算地址后部署）
///      ② ERC-4337 标准部署通道（UserOp.initCode = factory ‖ createAccount calldata）
///      ③ 最小代理 + 单一冻结实现（百万玩家共享一份字节码，存量零迁移）
contract AccountFactory {
    /// @notice P1 冻结的账户实现（所有代理共享）
    ISmartAccount public immutable accountImplementation;

    /// @notice CREATE2 前缀哈希已存在（地址冲突重放部署）——理论不可达，防御性断言
    error DeployFailed();

    /// @notice 账户铸造成功（索引器据此建 players 读模型，docs/tech/01-signup.md §7）
    /// @param account  账户地址（CREATE2 确定）
    /// @param pubKeyHash keccak256(pubKeyX ‖ pubKeyY)——不暴露公钥本体，供风控索引
    /// @param userSalt  用户盐（默认 0；非 0 = 高级用户主动换地址）
    event AccountCreated(address indexed account, bytes32 indexed pubKeyHash, uint256 userSalt);

    constructor(ISmartAccount implementation) {
        accountImplementation = implementation;
    }

    /// @notice 部署（或幂等返回已存在的）账户——EntryPoint 经 UserOp.initCode 调用，或任何人直接调用
    /// @param pubKeyX passkey 公钥 X（secp256r1）
    /// @param pubKeyY passkey 公钥 Y
    /// @param userSalt 用户盐（默认 0）
    /// @return account 部署后的账户地址（与 getAddress 预计算恒等）
    function createAccount(bytes32 pubKeyX, bytes32 pubKeyY, uint256 userSalt)
        external
        returns (address payable account)
    {
        account = getAddress(pubKeyX, pubKeyY, userSalt);

        // 幂等：已部署直接返回（EntryPoint 对「sender 已有代码却带 initCode」自会判 AA13，
        // 工厂层保持幂等以服务直接调用方与重放场景）
        if (account.code.length > 0) return account;

        address deployed =
            Create2.deploy(0, _createSalt(pubKeyX, pubKeyY, userSalt), _initCode(pubKeyX, pubKeyY));
        if (deployed != account || deployed.code.length == 0) revert DeployFailed();

        emit AccountCreated(deployed, keccak256(abi.encodePacked(pubKeyX, pubKeyY)), userSalt);
    }

    /// @notice 纯预计算地址（不上链、零成本）——客户端与合约双端公式一致性的链上锚
    function getAddress(bytes32 pubKeyX, bytes32 pubKeyY, uint256 userSalt)
        public
        view
        returns (address payable)
    {
        bytes32 initCodeHash = keccak256(_initCode(pubKeyX, pubKeyY));
        return
            payable(Create2.computeAddress(_createSalt(pubKeyX, pubKeyY, userSalt), initCodeHash));
    }

    /// @notice CREATE2 盐 = keccak256(pubKeyX ‖ pubKeyY ‖ userSalt)（客户端 §2.1 同式）
    function computeSalt(bytes32 pubKeyX, bytes32 pubKeyY, uint256 userSalt)
        public
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encodePacked(pubKeyX, pubKeyY, userSalt)));
    }

    /// @dev initCode = 代理字节码 ‖ 构造参数(impl, initialize(x,y) calldata)
    ///      注意：initCode 哈希依赖 (impl 地址, x, y)——实现冻结 + 公钥入盐 ⇒ 地址可本地预计算
    function _initCode(bytes32 pubKeyX, bytes32 pubKeyY) internal view returns (bytes memory) {
        return abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                address(accountImplementation),
                abi.encodeCall(ISmartAccount.initialize, (pubKeyX, pubKeyY))
            )
        );
    }

    function _createSalt(bytes32 pubKeyX, bytes32 pubKeyY, uint256 userSalt)
        private
        pure
        returns (bytes32)
    {
        return bytes32(computeSalt(pubKeyX, pubKeyY, userSalt));
    }
}
