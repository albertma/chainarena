# 用例 05：对局（Fight）—— 匹配到终局的完整生命周期

> 生命周期位置：核心循环 ｜ 参与者：双方玩家（或 Sensei/Second）、撮合器（只排序不裁决）、resolve bot
> 前置条件：已有 Fighter（用例 04）；排位需 $ARENA 入场费；已授权比赛会话
> 成功保证：对局核心循环 100% 链上；整局 0 钱包弹窗；单局成本 < $0.10
> 上游依据：产品 §2.3 / §2.4 / §2.5；技术 §1.2 / §3.2 / §4.5 / §4.6
> 单回合的逐笔数值演算见 [round-walkthrough.md](./round-walkthrough.md)

## 1. 触发与入口

大厅 → 「排位」（入场费 10 $ARENA 托管）或「休闲」（免费，Paymaster 限量赞助）

## 2. 主流程（成功路径）

### ① 匹配

```
排位：
  createMatch(mode=ranked, stake=10, fighterId)   ← 入场费托管进合约（L1 会话密钥可签）
  → Waiting 挂单；撮合器按 Elo 区间排序推送（中心化，但只排序、不裁决）
  → 对手 acceptMatch → 锁局，第 1 回合棋钟开启
  → 长时间无人接？cancelMatch 撤回托管（无损失）

休闲：
  createMatch(mode=casual) → 即撮即打
  → 对手优先匹配真人；冷启动期不足则 Sensei 垫场（AI 局占比 > 60%，随真人密度让位）
```

### ② 开局：比赛会话授权（唯一一次 L2 签名）

```
passkey 签名 grantSession(会话密钥, 规则):
  有效期 = 本局 + 30 分钟缓冲 ｜ 60 招上限 ｜ 只能出招/认输/触发裁决/levelUp
→ 之后整局全部由会话密钥自动签名（L1），0 弹窗
```

### ③ 逐回合循环（BO9，最多 9 回合）

每回合三阶段，详细演算见 [round-walkthrough.md](./round-walkthrough.md)：

```
commitMove(r, keccak(move, element, salt))    ← 双方秘密提交，mempool 零信息
revealMove(r, move, element, salt)            ← 揭示；标准节奏是批量:
     executeBatch[ revealMove(r), commitMove(r+1) ]   一笔完成"揭示+预提交"
resolveRound(matchId)                          ← 任何人触发（bot 每 2 块兜底），
                                                 纯函数结算: 伤害/属性克制/能量/回合分/超时
```

### ④ 终局（五条路径，优先级从高到低）

| 路径 | 触发 | 说明 |
|---|---|---|
| KO 胜 | 任意回合后对手 HP ≤ 0 | 当场终局 |
| 回合分胜 | 一方先拿 5 个回合分 | 主路径 |
| 判定胜 | 9 回合打满 | （回合分 → 剩余 HP）字典序 |
| 连续超时判负 | 一方连续 2 回合棋钟超时 | 防拖延 |
| 弃权 | forfeit（会话密钥可签） | 省时间 |

### ⑤ 原子结算（endMatch，与末回合 resolve 批处理为一笔）

```
奖池分配: 胜者 90% / 销毁 10%（rake）；平局双方各退 90%
Elo:     MatchEnded 事件携带 eloDelta0/1（挂账户，非 Fighter）
XP:      按对局结果发放（挂 Fighter，驱动用例 06）
掉落:    lootSeed（双方末回合 salt）roll → 命中即 Gear._mint 装备 ERC-1155（用例 07，W10+）
```

### ⑥ 赛后（可选，一笔批量）

```
executeBatch[ levelUp(fighter), createMatch(mode, stake, fighter) ]
→ 「领奖 + 升级 + 再排」零中间态，无缝开下一局
```

## 3. 状态与数据变化（以排位局为例）

| 对象 | 局前 | 局后（胜者视角） |
|---|---|---|
| $ARENA | 10 已托管 | +18（奖池 90%）；败者 −10，其中 2 销毁 |
| Elo / 段位 | R | R + eloDelta（账户级） |
| Fighter XP | X | X + 本局 XP（Fighter 级） |
| 战绩页 | — | 完整回合流水（`rounds` 表，回放即查询） |
| 链上数据量 | — | 玩家侧 ~18 UserOps/局，成本 ~$0.03–0.08 |

## 4. 体验要点

| 指标 | 目标 |
|---|---|
| 弹窗 | 0（开局会话授权 1 次除外） |
| 回合节奏 | 10–20s/回合（批量最快 ≈6s 完成一次交换） |
| 棋钟防御 | 剩余 <25% 时 UI 强提示 + 预提交默认招 |
| 掉线重连 | 客户端从事件流完全重建状态；会话密钥 30min 缓冲内免重签 |

## 5. 异常与边界（全集见产品 §2.4）

| 情形 | 处理 |
|---|---|
| 单方 commit/reveal 超时 | 当回合判负（对方 +1 回合分）；连续 2 回合 → 整局判负 |
| 双方双超时 | 平回合；连续 2 回合双超时 → 整局作废平局（退款规则） |
| 双 KO | 平局，退款规则同上 |
| 中途关闭浏览器 | 重连后续战（见上）；超时风险自担 |
| commit 后想反悔 | 不可能——commit 是承诺，reveal 必须与之一致（不一致则当回合判负） |
| resolve 没人触发 | 后台 bot 每 2 块兜底；任何人也可手动触发领"触发权"（无奖励，纯公益/观战加速） |
| 对手是 Sensei | 流程完全相同；其 UserOp 由 Sensei 自有 Safe + KMS 签名，Paymaster 走 Agent 档；链上可验证它没偷看（先 commit 后 reveal） |
| 本人离线 | 可预先雇佣 Second 代打（产品 §4.3）：以你的账户为 sender、operator key 签名，赛前透明标注 |

## 6. 权限与安全

- 出招/认输/触发裁决/升级 = **L1 会话密钥**（损失上限 = 一局入场费）
- 入场费托管在 MatchCore 合约内（非托管于任何人）；撮合器无资金权限
- 裁决 = 纯函数 + 不可升级合约（MatchCore）：服务器全部宕机也能由任何人触发继续完赛

## 7. 规格待定项

1. 撮合的 Elo 区间宽度与等待时间退让策略（现为中心化排序）
2. resolve 触发是否引入微量积分激励（当前无激励，依赖 bot/公益）
3. 观战高峰期的 priority fee 策略自动化

## 8. 关联文档

[README](./README.md) · [round-walkthrough.md](./round-walkthrough.md)（单回合数值演算） · [04 创建角色](./04-create-fighter.md) · [06 修炼升级](./06-levelup.md) · [07 战后掉落](./07-lucky-drop.md) · 产品 §2.3–§2.4 · 技术 §1.2 / §3.2
