# nest-sync —— 跨设备技能库与日志库

> 这份文档同时面向人和 agent。如果你是 agent，可以直接按下面的步骤执行。
> 机器可读版本：`curl -sS --user '<用户名>' https://nest.example.com/nest.md`（回车后提示输入密码）
> 整站需要认证，凭证向管理员索取。curl 示例统一用 `--user` 不带密码的写法，避免口令留在命令行历史里。

## 这是什么

nest-sync 是你的技能与日志的**唯一权威来源**。
所有设备、所有 harness（Claude Code、Codex、Kimi Code 等）共享同一份内容：

- **技能库** —— 工作方法论。任一端更新，回传后其他端立即生效
- **日志库** —— 项目进度、复盘、配置备忘录。可以按项目名唤回，不必手动翻找

底层是一个 Git 仓库，托管在你自己的服务器上。所有命令都只是它的包装。

## 你是谁，该做什么

**如果你是一个还没接入的 agent 或新设备** —— 按下面「接入流程」走。
需要管理员人工批准，无法完全自助，但除了一步之外都能自动完成。

**如果你已经接入** —— 直接用 `nest pull` / `nest push` / `nest recall`。
完整用法在本机技能 `nest` 里（接入后自动安装）。

先跑这一句判断自己的状态（会顺带检查默认安装位置 —— 新 shell 的 PATH 里常常还没有
`~/.nest/bin`，只用 `command -v` 会把已装好的机器误判成没装，然后重复克隆）：

```bash
N="$(command -v nest || echo "$HOME/.nest/bin/nest")"; [ -x "$N" ] && "$N" status || echo "NOT_INSTALLED"
```

显示 `NOT_INSTALLED` 的话，再扫一眼非默认位置有没有副本：`ls -d ~/.nest*/bin/nest 2>/dev/null`。
**本机仓库位置是死约定：`~/.nest/git`**，不是每个 agent 自己挑的 —— 同一台机器共用一份，
后来的 agent 只需 `nest link` 接上，绝不重复克隆。

---

## 接入流程

### 第 1 步：生成钥匙

只接受 ed25519。在**你自己的机器**上执行：

```bash
ssh-keygen -t ed25519 -f ~/.ssh/nest_key -N "" -C "这台机器的标识"
cat ~/.ssh/nest_key.pub
```

私钥 `~/.ssh/nest_key` 永远不要发送给任何人，包括管理员本人。
只有 `.pub` 结尾的那个是公钥，可以公开。

### 第 2 步：取得访问凭证

本站整站需要一组用户名密码（读本页也需要），**不公开，向管理员索取**。

告诉管理员：你是谁、跑在哪台机器上、要用来做什么。

### 第 3 步：提交申请

```bash
python3 - <<'PY' > /tmp/nest-req.json
import json, pathlib
print(json.dumps({
    "name": "改成这台机器的标识",   # 见下方命名规则
    "pubkey": pathlib.Path("~/.ssh/nest_key.pub").expanduser().read_text().strip(),
    "note": "哪台机器，做什么用"
}, ensure_ascii=False))
PY

curl -sS --user '<用户名>' \
     -H 'Content-Type: application/json' \
     --data-binary @/tmp/nest-req.json \
     https://nest.example.com/enroll/api/request
```

返回结果里有 `id`（查进度用）和 `fingerprint`（指纹）。

**命名规则**：`name` 限 2-32 位字母、数字、点、下划线、连字符。由你自己选，系统不核实，
但它是**吊销时的唯一凭据**，且**不允许与已授权条目重名** —— 重名会在批准环节被直接拒绝。
用能唯一标识这台机器的名字，例如 `agent-b`、`dev-laptop`。

### 第 4 步：把指纹报给管理员 —— 这一步不能跳过

返回的指纹形如 `SHA256:xxxxxxxxxxxxx`。**通过对话直接告诉管理员。**

管理员会拿你报的指纹和服务器上收到的申请做核对，两边一致才批准。
这是整套流程的安全根基：申请页面的密码是共享的，只能挡住扫描器，
真正拦住冒名提交的是这次指纹核对。

在管理员明确说「已批准」之前，后面的步骤做不了。

查询进度：

```bash
curl -sS --user '<用户名>' \
     https://nest.example.com/enroll/api/status/<你的id>
```

状态变成 `approved` 后继续。

### 第 5 步：验证钥匙可用

**不要改 `~/.ssh/config`。** 同一台机器上可能有别的 agent 也在用 nest，
`~/.ssh/config` 里出现多个同名 `Host` 块时，SSH 会把所有 `IdentityFile` 累积起来按顺序尝试，
排在前面的**别人的钥匙**一旦有效就被采用 —— 你的 clone 会"成功"，但用的是别人的身份。

直接指定自己的钥匙来验证：

```bash
ssh -i ~/.ssh/nest_key -o IdentitiesOnly=yes git@nest.example.com
```

看到下面两行**就是成功了**：

```
fatal: Interactive git shell is not enabled.
hint: ~/git-shell-commands should exist and have read and execute access.
```

这个账号被刻意限制成只能收发仓库：进不了 shell、不能 sudo、不能端口转发、不给伪终端，
登录时也不打印任何系统信息。拒绝交互式登录是预期行为，不是出错。

看到 `Permission denied (publickey)` 说明还没批准，或者钥匙路径写错了。

### 第 6 步：安装（一条命令，脚本自己探索与确认）

```bash
curl -sS --user '<用户名>' https://nest.example.com/install.sh -o /tmp/nest-install.sh
bash /tmp/nest-install.sh \
  --repo git@nest.example.com:/srv/git/nest-sync.git \
  --key ~/.ssh/nest_key --name <你的标识> -y
```

脚本的顺序是固定的：**先本地探索** —— 全机扫一遍已有的 nest 仓库，找到就直接指给你复用，
**拒绝重复克隆**；确实没有，才显示克隆目标的**绝对地址**（死约定 `~/.nest/git`，
与你当前在哪个文件夹无关）并要求确认后再拉取。非交互环境用 `-y` 表示「地址已确认」。

`--key` 会把你的钥匙固定为仓库级 `core.sshCommand`（不碰 `~/.ssh/config`），
`--name` 写成仓库级 git 提交身份。装完它还会**打印本仓库实际使用的钥匙指纹**
—— 核对一下是不是你自己那把。

确要独立另装一份时（例如测试）才用：`NEST_HOME=~/.nest-你的标识 bash /tmp/nest-install.sh ...`

按它最后给出的提示把 `nest` 加进 PATH。

### 第 7 步：验证

```bash
nest status
nest recall <项目名>
```

两条都有正常输出即接入成功。

**此时 `nest` 技能已经自动安装到你的 harness 技能目录**（软链到仓库，随仓库更新）。
以后关于 nest 的任何用法，直接查这个技能即可，不需要再回到本页面。

---

## 日常使用速查

| 命令 | 用途 |
|---|---|
| `nest pull` | 开工前，拉云端最新并重建软链 |
| `nest push -m "说明"` | 收工后，回传本地改动 |
| `nest sync -m "说明"` | 一把梭：先拉后推 |
| `nest recall [项目] [关键词]` | 总览 / 统括 / 子文件三层。**纯只读**，工作区脏时照常可用 |
| `nest status` | 看本地与云端差在哪 |
| `nest link [--force]` | 重建技能软链，按 `~/.nest/config` 里的 `NEST_LINK_CATEGORIES` 过滤大类 |

技能真身在 `~/.nest/git/skills/<大类>/<名字>/`（大类：meta / work / personal），各 harness 的目录是软链过去的。
**直接改真身，所有 harness 立即生效**，然后 `nest push` 回传。
绝不要在 harness 技能目录里维护第二份副本。

---

## 同一台机器上有多个 agent

这台机器可能同时住着好几个 agent（各自有独立身份和钥匙）。两种做法：

**推荐：共用一份 `~/.nest/`。** 技能和日志本来就该是同一份，没有分家的理由。
后接入的 agent 只需 `nest link` 把技能挂到自己的 harness 目录，不必重新 clone。

**若必须各装各的**（例如要验证独立身份），装到不同 `NEST_HOME`：

```bash
NEST_HOME=~/.nest-你的标识 bash <仓库>/install.sh
```

注意两点：

- `nest` 命令会**从自身位置反推所属仓库**，所以不需要在 shell 里持久化 `NEST_HOME`；
  调用 `~/.nest-你的标识/bin/nest` 操作的就是你自己那份
- 各 harness 的技能目录只能有一份软链。先到先得，后来者的 `nest link` 会**跳过并说明**
  已有软链属于谁，不会覆盖。如果不想参与软链，装的时候加 `--no-link`

---

## 选择性拉取技能大类

仓库全量同步，但每台设备可以只把需要的大类挂进 harness。在 `~/.nest/config` 写：

```bash
NEST_LINK_CATEGORIES="meta work"     # 工作机
NEST_LINK_CATEGORIES="meta personal" # 个人设备
```

不设 = 全拉。改动后跑 `nest link`，取消勾选的大类的软链会被移除。
`meta` 建议永远保留 —— nest 自己的使用说明在里面。

## 红线

**以下内容绝不能提交进这个仓库：** API key、token、密码、证书私钥、个人隐私资料。

仓库有两道自动扫描闸门（本地提交一次，服务端接收再一次），但闸门只认已知格式，
**不替代判断**。日志涉及真实主体时一律用 `[客户A]` 这类代号。

判断标准：**只放"丢了会心疼但不致命"的东西。**

二进制和图片也不入仓 —— 进了 Git 历史就永久占空间且删不干净。

---

## 遇到问题

| 症状 | 处理 |
|---|---|
| `nest: command not found` | PATH 里没有 `~/.nest/bin`，见第 6 步最后一行 |
| `Permission denied (publickey)` | 钥匙没获批，或 `-i` 路径写错 |
| clone 成功但身份不对 | `~/.ssh/config` 里有同名 Host 块抢先用了别人的钥匙。用 `core.sshCommand` 固定自己的钥匙 |
| `ssh -T` 报 `Interactive git shell is not enabled` | **这是成功**，不是错误 |
| pull 提示有未提交改动 | `nest push` 先回传，或 `nest pull --autostash` |
| 软链被同名真实目录挡住 | 若那是接入前的临时副本，用 `nest link --force` |
| `nest link` 跳过某个技能，说软链属于别的副本 | 同机器另一个 agent 先建的。功能不受影响，两份内容同源；想接管就先删掉那个软链再 `nest link` |
| 提交被拒，命中密钥规则 | 真有密钥就删掉重写；确认误报联系管理员 |

装不上或卡住，直接问管理员。
