# ChainArena Contracts

ChainArena 智能合约工程（Foundry + OpenZeppelin v5）。设计文档见 [`../docs/`](../docs/README.md)，当前实现对应 **P1-A：AccountFactory**（[docs/development-phases.md](../docs/development-phases.md)）。

## 快速开始

```bash
# 依赖（lib/ 已含 forge-std 与 openzeppelin-contracts v5.1.0，如缺失则重新拉取）
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-commit

forge build          # 编译（solc 0.8.28）
forge test           # 全量测试
forge test -vvv      # 详细模式
forge coverage       # 覆盖率
```

## 目录结构

```
src/
├── account/
│   ├── AccountFactory.sol   # CREATE2 确定性铸造器（P1-A）
│   └── SmartAccount.sol     # P1 骨架：passkey 存储 + ERC-1271 占位
├── interfaces/
│   └── ISmartAccount.sol    # 工厂编码 initCode 所需的最小冻结接口
test/
└── account/
    └── AccountFactory.t.sol # 13 个测试（含 fuzz）
script/
└── DeployAccounts.s.sol     # 实现 + 工厂部署脚本
lib/                          # forge-std、openzeppelin-contracts@v5.1.0（submodule）
```

## 核心公式（客户端与合约严格镜像）

```
salt     = uint256(keccak256(pubKeyX ‖ pubKeyY ‖ userSalt))
initCode = ERC1967Proxy creationCode ‖ abi.encode(impl, abi.encodeCall(initialize,(x,y)))
addr     = keccak256(0xff ‖ factory ‖ bytes32(salt) ‖ keccak256(initCode))[12:]
```

- **同 passkey + 同 userSalt ⇒ 永远同地址**（中断续跑、地址预览的根基）
- 工厂幂等：同参数重复 `createAccount` 返回既有账户、不重复发事件
- `AccountCreated(account, pubKeyHash, userSalt)`：索引器建 `players` 读模型的事件源（公钥不上链，只上哈希）

## 测试矩阵（对应 docs/tech/01-signup.md §10）

| 分组 | 用例 |
|---|---|
| 地址确定性 | 纯函数确定性 / 不同 x、y、userSalt 互异 / 客户端镜像公式逐字节一致 / salt 公式一致 |
| 部署初始化 | 事件与参数 / 预计算=实部署 / ERC-1967 槽指向冻结实现 / initialize 落公钥 / 实现禁二次初始化 / 多玩家无碰撞 |
| 幂等与 initCode | 重复铸同地址零事件 / EntryPoint 式 initCode 路径 |
| Fuzz | 任意 (x, y, salt)：预计算恒等于实际部署（256 runs） |

实测：`createAccount` 单次部署 ≈ **202k gas**（ERC1967 代理 + initialize），落在文档预算区间（150–300k）。

## 部署

```bash
export DEPLOYER_PRIVATE_KEY=0x...
forge script script/DeployAccounts.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --broadcast --verify
```

顺序遵循 [docs/development-phases.md §9.2](../docs/development-phases.md)：**实现先行（P1 冻结，终身不换）→ 工厂随后**。

## Roadmap（账户域）

| 阶段 | 内容 | 状态 |
|---|---|---|
| P1-A | AccountFactory + SmartAccount 骨架 | ✅ 本仓库 |
| P1-B | WebAuthnValidator（RIP-7212 precompile 0x100 验签）+ ERC-1271 实现 | ⏳ |
| P1-C | RecoveryModule（guardian 2/2 + sessionEpoch） | ⏳ |
| P1-D | GamePaymaster（新手档赞助）+ EntryPoint 集成测试 | ⏳ |
