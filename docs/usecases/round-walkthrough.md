# 用例：一个回合的完整生命周期（排位局 · 第 4 回合）

> 配套文档：规则依据 [`product-design.md`](../product-design.md) §2.2–§2.4；链上流程依据 [`tech-design.md`](../tech-design.md) §1.2 / §3.3 / §4.6；用例集索引：[`README.md`](./README.md)
> 说明：本用例为教学演算，所有数值严格按 §2.3 招式表与 §2.2.2 流派表推演，可逐项对表复核。合约哈希/事件值为示意值。

---

## 0. 对局背景

| | p0：Alice | p1：Bob |
|---|---|---|
| Fighter | 「赤霄」 | 「沧澜」 |
| 流派（本命） | 烈焰 Blaze（火） | 流转 Flow（水） |
| 三系招式标签 | 火 / 金 / 土 | 水 / 土 / 木 |
| 等级 | Lv.5（必杀已解锁） | Lv.5（必杀已解锁） |
| 签名方式 | MatchSession key（0 弹窗） | MatchSession key（0 弹窗） |
| 模式 | 排位局，双方各托管 10 $ARENA，奖池 90/10 | |

**前 3 回合复盘（进入第 4 回合前的状态由这三回合推出）：**

| 回合 | Alice 出招 | Bob 出招 | 结算 | 回合后状态（HP / 能量 / 比分） |
|---|---|---|---|---|
| R1 | GUARD（格挡） | STRIKE(木)：15 ×0.4 减伤 = **6** | 属性轮不触发（GUARD 非攻击招）；Bob 伤 6 > 0 → Bob 得分 | 94/100 · 能 5/3 · 0:1 |
| R2 | HEAVY(金)：30 | GUARD | HEAVY 破防：减伤 −60% 退化为 −40% → Bob 受 **18**；Alice 得分 | 94/82 · 能 4/5 · 1:1 |
| R3 | STRIKE(火)：15→**17**（烈焰被动） | HEAVY(土)：30 | 火生土 → 中性 ×1.0；互伤 17/30；Bob 伤更高得分 | 64/65 · 能 4/4 · 1:2 |

> 能量流水核对（R1 Alice）：3 起步 + GUARD 回 1 + 回合自动 +1 = 5（恰好触顶）。
> Bob（流转）若出 CHARGE 回能按 +3 计（被动），本局尚未用到。

**第 4 回合开始状态：**

| | Alice | Bob |
|---|---|---|
| HP | 64 | 65 |
| 能量 | 4 | 4 |
| 回合分 | 1 | 2（领先） |
| 手牌态势 | 双方 4 能量，均够必杀（3 能）；Bob 再拿 3 分即胜 |

---

## 1. Commit 阶段（窗口：30 块 ≈ 60s）

**块 1000**：R3 resolve 落块 → 第 4 回合棋钟开启，`roundDeadline = 1030`。双方客户端本地倒计时启动。

**双方决策（互相不可见）：**

- Alice 的读招：*"Bob 连续两回合没有动必杀，他在攒能量等第 5 回合放大。他若这回合试探，多半用木标签轻击（木克土防我重击）——我出 HEAVY(金)，金克木，打他一个 1.25 倍。"*
- Bob 的决策：*"能量 4，直接放必杀「潮汐击」，水属性，还偷 1 能量压制她的必杀节奏。她大概率 HEAVY 或 STRIKE 试探。"*

**Alice 提交（块 1002 落块）：**

```ts
// 出招 = (招式, 属性, salt)，本地随机 salt，内容被哈希隐藏
const salt  = 0x6ad1…b3;                        // 随机 32 字节
const move  = 2;  // HEAVY
const elem  = 1;  // Metal（金，Alice 三系标签之一 ✓）
commitMove(matchId, 4, keccak256(abi.encode(move, elem, salt)));
// → commitHash = 0x3f9c…d2（示意）
```

- UserOp 由 **MatchSession key 签名**（nonceKey = matchSessionId），paymasterAndData = 排位自付档策略签名——**无弹窗**。
- Bob 同样在 **块 1004** 提交 SPECIAL 的承诺。双方 commit 齐 → reveal 窗口开启，deadline = 1034。
- 公平性：mempool 里只有两个哈希，出招内容对任何人（包括 Sequencer、对手、运营）零信息量。

---

## 2. Reveal 阶段（deadline = 1034）

**Alice（块 1006，一笔批量 UserOp，`executeBatch`）：**

```ts
const userOp = encodeUserOp({
  calls: [
    // ① 揭示第 4 回合
    { target: MATCH_CORE, callData: encode('revealMove(uint256,uint16,uint8,uint8,bytes32)',
        [matchId, 4, /*HEAVY*/2, /*Metal*/1, salt]) },
    // ② 顺手预提交第 5 回合（内容继续隐藏）
    { target: MATCH_CORE, callData: encode('commitMove(uint256,uint16,bytes32)',
        [matchId, 5, nextCommitHash]) },
  ],
  nonceKey: matchSessionId,
  paymasterAndData,   // 排位自付
});
```

> 批量的价值：揭示与下一招一气呵成，消除"揭示后忘提交"被抢节奏的窗口（技术设计 §4.6）。

**Bob（块 1008）**：`revealMove(matchId, 4, SPECIAL, Water, salt')`——任何人可当场校验 `keccak` 与其 commit 一致，证明没换招。

---

## 3. resolveRound 结算（块 1010，后台 bot 触发，任何人可触发）

**裁决纯函数逐步推演：**

| 步骤 | 计算 | 结果 |
|---|---|---|
| ① 属性轮判定 | Alice 金 vs Bob 水 → **金生水 = 相生 → 中性 ×1.0**（Alice 赌的"金克木"落空：Bob 根本没出木） | 双方无克制修正 |
| ② Alice 伤害 | HEAVY 基础 30 ×1.0（烈焰被动只加成 STRIKE，本招不生效） | Bob 受 **30**：65 → **35** |
| ③ Bob 伤害 | SPECIAL「潮汐击」40 ×1.0 | Alice 受 **40**：64 → **24** |
| ④ 能量结算 | Alice：4 +1(自动) −2(HEAVY) −1(被偷) = **2**；Bob：4 +1 −3(SPECIAL) +1(偷取) = **3** | Bob「偷 1 能量」把 Alice 拖离必杀线（3 能） |
| ⑤ 回合分 | 造成伤害对比：Bob 40 > Alice 30（回复/偷能不计入比较） | **Bob +1 → 1:3** |
| ⑥ 终局检查 | 无 KO、无人到 5 分、未满 9 回合 | 开启第 5 回合棋钟 |

**链上事件（观战/回放/AI 感知同源，零模拟渲染）：**

```solidity
RoundResolved(matchId, 4,
    moves  = [HEAVY, SPECIAL],
    dmg0   = 40, dmg1 = 30,      // p0/p1 本回合所受伤害
    hp0    = 24, hp1  = 35,
    score0 = 1,  score1 = 3);
```

**本回合耗时**：块 1000 → 1010，共 10 块 ≈ **20 秒**；玩家侧全程 0 弹窗。
**本回合链上成本**：2 commit + 2 reveal（约 $0.002–0.005/笔）+ 1 resolve（约 $0.001，bot 批量摊薄）≈ **$0.01 量级**。

---

## 4. 第 5 回合态势（用例收尾）

| | Alice | Bob |
|---|---|---|
| HP | 24（危险区） | 35 |
| 能量 | 2（**不够必杀**） | 3（下一回合即可再放大） |
| 回合分 | 1 | 3（再拿 2 分即胜） |

Alice 的困境正是「流转」流派的战术模板：潮汐击的偷能让她必须先用 CHARGE 攒能量（且 CHARGE 受伤 +50%），或赌一个 STRIKE/HEAVY 的属性克制翻回合分——**属性读招 + 能量节奏的双博弈**在此回合后完全摊开。

---

## 5. 变体对比（同一局面，不同选择）

| 变体 | Alice 改出 | 结算差异 | 教学点 |
|---|---|---|---|
| **A. 读对属性** | HEAVY(土)（土克水） | Alice 30×1.25 = 37.5 → **37**（整数截断），Bob 40×0.75 = **30**；Alice 64−30=34，Bob 65−37=28，**回合分归 Alice（2:2）** | 属性轮读对 = 伤害与回合分双翻转，本游戏的核心心战 |
| **B. reveal 超时** | commit 了 HEAVY(金) 但 30 块内未 reveal | Alice 当回合判负：Bob +1（1:3），**跳过伤害结算**（Bob 保持 65 HP）；若 R5 再超时 → 整局判负 | 棋钟是硬约束；客户端剩余 <25% 时会强提示 + 预提交默认招 |
| **C. 对手是 Sensei-白银** | 流程完全相同 | 区别仅在：Bob 的 UserOp 由 Sensei 自有 Safe + KMS 热钥签名、Paymaster 走 Agent 档 | AI 与人同管道、同 commit-reveal——链上可验证它没偷看 |

---

## 6. 本用例暴露的规格待定项（设计评审清单）

1. **整数舍入约定**：30×1.25=37.5、15×0.75=11.25 等情况会出现小数——合约需明确截断/四舍五入规则（本用例变体 A 按 floor 演算）。主用例数值均为整数，不受影响。
2. **`RoundResolved.dmg0/dmg1` 语义**：需明确是"所受伤害"还是"造成伤害"（本用例按所受伤害示意）。
3. **能量结算顺序**：自动 +1、招式消耗、偷取/回能的先后次序需在 `resolveRound` 实现中固定（本回合三种口径结果恰好相同，不具一般性）。
4. **HEAVY 破防语义**：本用例按"GUARD 减伤 −60% 退化为 −40%"（即穿透后仍吃 40% 减伤）演算，需在合约测试中固化为不变量。
