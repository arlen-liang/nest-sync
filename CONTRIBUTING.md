# 参与贡献

这是一个个人展示项目：把一套自用的跨设备技能库与日志库整理成可读的开源形态，
主要用来展示设计思路与实现细节。

## 关于 issue 与 PR

- **Issue 欢迎**。设计上的疑问、指向明确的 bug、文档里的错误，都值得提
- **不保证响应时间，也不承诺持续维护**。项目按我自己的节奏走，没有路线图，
  没有服务等级，可能长时间不更新
- **PR 请先开 issue 讨论**。未经讨论的大改动很可能被直接关闭 —— 不是不欢迎，
  而是这个项目的取舍有很强的上下文（见 `docs/decisions.md`），
  没读过决策记录就动手容易撞上已经明确排除的方案

## 改动前请先读

| 想改什么 | 先读 |
|---|---|
| 架构、子命令行为 | `docs/architecture.md` |
| 密钥闸门、准入流程、数据分级 | `docs/security-model.md` |
| 任何"为什么不这样做" | `docs/decisions.md` |

`docs/decisions.md` 末尾有一张"明确不做的事"清单，里面列的东西不接受 PR。

## 本地检查

提交前请确认：

```bash
# shell 语法
bash -n bin/nest install.sh hooks/pre-commit hooks/pre-receive

# shellcheck（CI 会跑）
shellcheck --severity=warning bin/nest install.sh hooks/pre-commit hooks/pre-receive

# python 语法
python3 -m py_compile deploy/server/nest-enroll.py deploy/server/nest-keys

# 密钥扫描（装了就自动启用）
gitleaks detect --source . --redact -v
```

## 红线

**任何情况下都不要提交：** API key、token、密码、证书私钥、个人隐私资料、
真实的服务器地址与域名。

示例与文档一律使用保留域名（`nest.example.com`）和文档专用 IP 段
（`192.0.2.0/24`、`198.51.100.0/24`、`203.0.113.0/24`）。

## 许可证

贡献的内容按 MIT 许可证授权，见 `LICENSE`。
