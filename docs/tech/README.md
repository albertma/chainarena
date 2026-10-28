# P1 技术详设目录（Signup / Signin / Recover）

> Phase 1 三个 story 的实现级技术设计，是[分期开发计划 §3](../development-phases.md)的细化。
> 上游：[架构设计](../architecture.md) · [技术设计 §4](../tech-design.md) · [用例 01/02/03](../usecases/README.md)

| 文档 | Story | 一句话范围 |
|---|---|---|
| [01-signup.md](./01-signup.md) | 注册 | passkey → CREATE2 预计算 → 赞助 UserOp 部署账户（1 弹窗/0 Gas/p95≤15s） |
| [02-signin.md](./02-signin.md) | 登录 | nonce + ERC-1271 断言 + JWT（0 链上写入/后端无法冒签） |
| [03-recover.md](./03-recover.md) | 找回 | 场景 A 备用钥匙即时轮换；场景 B guardians 阈值 + 24h 延时窗口社交恢复 |

三文档共享的契约（EntryPoint v0.7 结构、WebAuthn 断言编码、paymasterAndData 编码、错误码体系）以 [01-signup.md §2](./01-signup.md) 为准，其余文档直接引用。
