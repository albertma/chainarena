# ChainArena ⚔️

**全链 1v1 格斗游戏** —— Base L2 · ERC-4337 账户抽象 · Passkey 无助记词登录 · 玩家零 Gas。

> 玩家用指纹/面容注册，60 秒内打完第一局；资产全在玩家自己的智能账户里，游戏方碰不到。

## 技术栈

| 层 | 选型 |
|---|---|
| 链 | Base L2（支持 RIP-7212 P-256 预编译 `0x100`，passkey 链上验签 ~3.5k gas） |
| 账户 | ERC-4337 EntryPoint v0.7 + SmartAccount（Safe 变体，实现 P1 冻结）+ 三模块 |
| 基础设施 | OpenZeppelin Contracts v5.1（CREATE2 / ERC1967Proxy / Initializable） |
| 工具链 | Foundry（forge 1.8 / solc 0.8.28）· Python 客户端演示 |

## 仓库结构

```
chainarena/
├── docs/                    # 全部设计文档（中文）
│   ├── product-design.md    #   产品设计
│   ├── architecture.md      #   系统架构（客户端/后端/Bundler/合约/L1-L2）
│   ├── tokenomics.md        #   $ARENA 代币经济
│   ├── development-phases.md#   P0–P4 分期计划（P1 = 账户栈）
│   ├── tech-design.md       #   技术设计总纲
│   ├── tech/                #   P1 三大 story 实现级详设（signup/signin/recover）
│   └── usecases/            #   用例 01–07（注册/登录/恢复/建角色/对战/升级/掉落）
├── contracts/               # 智能合约（Foundry 工程）
│   ├── src/account/         #   AccountFactory + SmartAccount（P1-A ✅）
│   ├── test/account/        #   15 个测试全绿（含 fuzz）
│   └── Makefile             #   make demo-local 一键演示
└── client-demo/             # Python 客户端演示（uv 管理，地址公式与合约逐字节镜像）
```

## 快速开始

```bash
# ── 合约：测试 ──
cd contracts && forge test                    # 15 passed

# ── 合约：本地链部署 + 一键演示（预计算→部署→幂等重放）──
make demo-local

# ── 客户端：完整建号流程（生成 passkey → 本地算址 → 链上对账 → 部署 → 验证）──
cd ../client-demo && uv run chainarena_client.py
```

## 核心设计：地址确定性

```
salt     = keccak256(pubKeyX ‖ pubKeyY ‖ userSalt)        # passkey 公钥 + 用户盐(默认0)
initCode = ERC1967Proxy creationCode ‖ abi.encode(impl, initialize(x,y) calldata)
addr     = keccak256(0xff ‖ factory ‖ salt ‖ keccak256(initCode))[12:]
```

**同 passkey ⇒ 永远同地址**——中断续跑、重装恢复、跨设备（passkey 云同步）的根基。合约侧 `getAddress`、Solidity 测试、Python 客户端三处逐字节一致，CI 常跑断言。

实测（anvil）：账户部署 ~194k gas，幂等重放 ~27k gas。

## 关键决策速览

| 决策 | 理由 |
|---|---|
| passkey 用 secp256r1（P-256） | WebAuthn 标准强制；Secure Enclave/TPM 只支持 NIST 曲线；Base 有 RIP-7212 预编译 |
| 账户实现 P1 冻结，扩展走「启用模块」 | impl/工厂/代理码都进地址哈希——换实现 = 全量地址漂移，玩家零迁移是铁律 |
| 工厂幂等部署 | 同参数重放返回既有账户、零事件；调用者无关（EntryPoint ≡ 任何人） |
| 公钥不上链，只上 `keccak(x‖y)` | 隐私 + 防链下抢跑；事件 `AccountCreated` 供索引器建读模型 |
| userSalt 默认 0 | 地址唯一确定的输入是密钥本身；随机盐 = 重演助记词之痛 |

## Roadmap

| 阶段 | 内容 | 状态 |
|---|---|---|
| P1-A | AccountFactory + SmartAccount 骨架 + Python 客户端演示 | ✅ |
| P1-B | WebAuthnValidator（RIP-7212 验签）+ validateUserOp + ERC-1271 | ⏳ |
| P1-C | RecoveryModule（guardian 2/2 + 24h 窗口 + sessionEpoch） | ⏳ |
| P1-D | GamePaymaster（新手档赞助）+ EntryPoint 集成测试 | ⏳ |
| P2+ | FighterNFT / MatchCore / VRF 铸角色 / 会话密钥 / 代币经济 | 设计完成 |

## 文档导航

- 产品：[docs/product-design.md](docs/product-design.md)
- 架构：[docs/architecture.md](docs/architecture.md)
- 代币：[docs/tokenomics.md](docs/tokenomics.md)
- 分期：[docs/development-phases.md](docs/development-phases.md)
- P1 详设：[docs/tech/README.md](docs/tech/README.md)（signup / signin / recover）
- 用例：[docs/usecases/README.md](docs/usecases/README.md)

## License

TBD（P1 验收前不对外公开）· © ChainArena Team
