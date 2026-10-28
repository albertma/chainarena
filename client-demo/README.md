# ChainArena 客户端演示（Python）

`@arena/core` 建号流程的 Python 演示版——完整复现 `docs/tech/01-signup.md` 的客户端侧 7 个步骤，**地址计算与 Solidity 合约逐字节镜像**（跑起来就是 `test_GetAddress_MatchesClientMirrorFormula` 的运行时证明）。

## 前置

```bash
# 1. 编译合约（需要 out/ 里的 ERC1967Proxy 字节码与 broadcast 部署记录）
cd contracts && forge build && make demo-local
```

## 运行（uv，推荐）

```bash
uv run chainarena_client.py                # 自动创建/复用 .venv + 锁定依赖（uv.lock）
uv run chainarena_client.py --no-deploy    # 只读：生成密钥 + 本地算址 + 对账
uv run chainarena_client.py --fresh        # 换新 passkey → 地址必变
uv run chainarena_client.py --user-salt 1  # 同钥开小号（高级设置语义）
```

## 运行（pip，备用）

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python chainarena_client.py …
```

## 步骤 ↔ 设计文档映射

| 脚本步骤 | 对应 docs/tech/01-signup.md |
|---|---|
| ① passkey 生成/恢复 | Step 1（真实版：浏览器 WebAuthn + Secure Enclave；本演示用 `cryptography` 生成真 secp256r1 密钥对） |
| ② CREATE2 本地预计算（零 RPC） | Step 3：`salt = keccak(x‖y‖userSalt)`，`addr = keccak(0xff‖factory‖salt‖keccak(initCode))[12:]` |
| ③ 链上对账 `getAddress` | 测试矩阵「客户端镜像公式一致性」 |
| ④ `eth_getCode` 预检 | Step 4 重复注册预检 |
| ⑤ `createAccount` 上链 | Step 11 的简化版（funded key 模拟 Bundler；真实版走 UserOp.initCode 经 EntryPoint 原子执行，待 P1-B） |
| ⑥ 账户代码 + `pubKeyX/Y` 验证 | Step 12/16 回执核对 |
| ⑦ 幂等重放 | gas 194k → 27k 短路返回（合约幂等设计的实证） |

## 关键性质演示

- **中断续跑/重装恢复**：同 keyfile 重跑 → 同一地址（密钥存 `keys/passkey.json`，等价于 passkey 云同步）
- **换钥换址**：`--fresh` → 地址必变
- **同钥开小号**：`--user-salt N` → 地址分叉，旧地址不受影响

## 与真实客户端的差异（诚实声明）

| | 本演示 | 真实 `@arena/core`（P1） |
|---|---|---|
| 密钥 | `cryptography` 软件生成 P-256 | 浏览器 WebAuthn（Secure Enclave/TPM，不可导出） |
| 部署 | 普通交易直调工厂 | UserOp + Bundler + EntryPoint（initCode 路径，部署与首笔操作原子） |
| Gas | anvil 预置 key 代付 | GamePaymaster 赞助（策略签名器签发） |
| 验签 | 无（P1-B 之前账户尚未实现 validateUserOp） | passkey 断言 + RIP-7212 precompile 0x100 |
