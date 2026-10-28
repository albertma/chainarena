# 用例 04：创建角色（Create Fighter —— ERC-721）

> 生命周期位置：注册后 / 商城购买 / 市场购入 ｜ 参与者：玩家、Chainlink VRF、（市场路径）第三方市场合约
> 前置条件：已注册（用例 01）；付费铸造需持有 $ARENA
> 成功保证：配置由 VRF 决定，**任何人（含运营）都无法操纵或预测**；揭晓过程可独立验证；Fighter 是完整 ERC-721，可自由交易
> 上游依据：产品 §2.2.2（流派）、§2.6（经济：Fighter 可交易）；技术 §3.1（FighterNFT.sol）、§3.3（mint/claimStarter）、§5.5（VRF）

## 0. 术语对齐：「角色」= Fighter

选手身份 = 智能账户（段位挂账户）；游戏角色 = Fighter（**ERC-721 NFT**，FighterNFT.sol，配置/XP/等级挂 tokenId）。本用例即 Fighter 的诞生与流转流程。

**双资产标准对照**：Fighter = **ERC-721**（每一个都是独一无二的非同质化资产，配置/等级随 NFT 走）；装备 = **ERC-1155**（武器/护甲同质化可堆叠，见用例 07）。

## 1. 触发与入口

| 入口 | 路径 | 费用 | 频率 |
|---|---|---|---|
| 新手领取 | 注册流程内 `claimStarter`（用例 01 第③步批内） | 免费（新手赞助） | 1 次/玩家 |
| 商城铸造 | 大厅 →「铸造 Fighter」→ `mint` | 固定价 $ARENA（运营配置） | 不限（消耗即 sink） |
| 市场购入 | 从其他玩家处购入 ERC-721（transfer） | 市场价 | 不限 |

## 2. 主流程（成功路径，以付费铸造为例）

```
① 大厅点「铸造」→ 客户端展示费率（含 Gas 的 $ARENA 总价，Token 代付）

② 一笔 UserOp（passkey 签名，L2 价值操作）：
   mint() → 合约请求 Chainlink VRF（requestRandomness）

③ VRF 回调（fulfillRandomWords，1–2 个块）：
   kitSeed = VRF 随机数
   → 本命属性 = kitSeed mod 5          （金/木/水/火/土 → 流派）
   → 三系标签 = kitSeed 派生的 C(5,3) 组合（10 种配置）

④ 事件 FighterMinted(fighterId, owner, kitSeed) 上链
   → 客户端触发开包式揭晓动画
   → 任何人可用 VRF proof 独立复核（运营无法"洗配置"）

⑤ Fighter 卡面展示：
   流派定位 / 被动 / 必杀特效 / 三系标签 / 克制关系图（克谁·被谁克·两个空档）
```

**揭晓示例**：kitSeed → 本命 = 金 → **锋刃 Blade**；标签 = {金, 水, 火}
→ 克制强项：金克木（木系对手 ×0.75）
→ 被克盲区：火克金（火系对手打你 ×1.25）
→ 空档：无土、无木标签 → STRIKE/HEAVY 永远带不出土/木属性

### ⑥ ERC-721 生命周期：持有 → 交易 → 授权

```
铸造:   mint / claimStarter 即标准 ERC-721 _mint，owner = 玩家智能账户
持有:   ownerOf(fighterId) 随时可宣示权属；配置/等级/XP 全部挂在 tokenId（链上）
卖出:   第三方市场（Base 生态 Seaport 类）或熟人直接 transfer
        → 挂单: setApprovalForAll(市场合约) 或 approve(fighterId)   ← L2 passkey
        → 成交: 市场合约 transferFrom → $ARENA/ETH 到手，NFT 到买方
买入:   市场购入 = 普通 ERC-721 购买（见 §1 表第 3 行）
        → 配置/等级/XP 随 tokenId 自动到手；段位不随（挂账户）——买号买不来天梯分
```

- **所有 ERC-721 写操作（transfer / approve / setApprovalForAll）= L2 passkey 签名**——资产转移语义，与铸造同级（§6）
- 元数据：数值与配置由 `FighterMinted` 事件 + configHash 锚定；`tokenURI`（Metadata 扩展）返回动态元数据（等级/XP/战绩）——渲染前客户端本地校验，防配置黑箱
- 转让不改变 Fighter 的任何游戏内数据——ERC-721 的权属与游戏状态解耦但同源

## 3. 状态与数据变化

| 对象 | 之前 | 之后 |
|---|---|---|
| Fighter NFT | 不存在 | 铸出，ERC-721 owner = 玩家智能账户，配置定档（不可更改） |
| ERC-721 权属 | — | 交易后 owner = 买方账户；tokenId 数据（配置/等级/XP）不变 |
| $ARENA | 余额 X | X − 铸造费（固定价 + Gas 代付） |
| 链上事件 | — | FighterMinted（索引器入 `players`，天梯页可见） |

## 4. 体验要点

- 签名：铸造 1 次 passkey（L2，铸造属价值操作，**不可**用会话密钥）；交易/授权同为 1 次 passkey（资产操作）
- 等待：VRF 请求→回调 ≈ 2–4s，正好填充揭晓动画
- Gas：~250k ≈ $0.005，走 $ARENA 代付（排位自付档规则）
- 克制关系图是核心新手教育点：直接回答"我这只克谁、怕谁"

## 5. 异常与边界

| 情形 | 处理 |
|---|---|
| VRF 请求超时/失败 | 两段式：请求费退还，客户端引导重试；不会有"付了钱没 Fighter"状态（回调缺失可 claim 退款——参数待定） |
| 「洗配置」（不满意重铸） | 允许（就是再 mint 一次），但铸造费照付且旧 Fighter 不回收 → 经济上自我限制；强度平衡由流派胜率回归（±3% 门）保证，不存在"神配置" |
| 市场购入的 Fighter | 配置/等级/XP 随 NFT 走；**段位不随 Fighter 走**（挂账户）——买号买不来天梯分 |
| Fighter 转出到外部钱包（非本游戏智能账户） | NFT 权属与数据完整，但**不能参赛**（createMatch 校验 owner = 参赛智能账户）；转回即可再战 |
| setApprovalForAll 被钓鱼诱导 | UI 明示授权对象与范围，仅玩家主动挂单时引导；任何授权变动发链上事件 + 客户端推送提醒 |
| 交易中的 Fighter | 挂单/成交不受对局状态影响（Fighter 未在局中才可转移？——规格待定，见 §7） |
| 并发铸造 | VRF 请求按 fighterId 隔离，无竞态 |

## 6. 权限与安全

- 签名层级：L2 passkey（mint）；新手领取在注册批内（同为 L2）；**transfer/approve/setApprovalForAll 同为 L2**——均不在会话密钥 selector 白名单（技术 §3.4），会话密钥/代打 operator 密钥泄露也偷不走 Fighter
- 防操纵：VRF 请求与区块状态绑定，运营/Sequencer 均不可预知 kitSeed；配置结果事件可独立复核（技术 §9.1 威胁表「VRF 操纵」行）
- 防"配置黑箱"：game-config 数值全部 configHash 锚定，tokenURI/元数据与链上事件对齐，客户端本地校验后才渲染卡面
- 交易安全：不设自建托管——交易走成熟第三方市场合约，游戏侧只依赖 ERC-721 标准语义（权属即真相）

## 7. 规格待定项

1. 铸造固定价数额与是否有每日/每周铸造上限（防 sink 失衡）
2. VRF 回调失败的超时退款参数
3. 赛季性"配置池轮换"是否影响已铸 Fighter（倾向不影响，仅影响新铸）
4. tokenURI 元数据方案：静态 JSON vs 动态渲染服务；等级/XP 等动态字段上链 vs 事件重建
5. 是否实现 ERC-721Enumerable（倾向不实现：背包/市场走索引器事件流，省 Gas）；是否附 ERC-2981 版税（运营/玩家分成比例）
6. 对局中的 Fighter 能否转移（建议锁局内冻结，防"赛中卖号"争议）

## 8. 关联文档

[README](./README.md) · [01 注册](./01-signup.md) · [06 修炼升级](./06-levelup.md) · [07 战后掉落](./07-lucky-drop.md)（ERC-1155 对照） · 产品 §2.2.2 / §2.6 · 技术 §3.1 / §5.5
