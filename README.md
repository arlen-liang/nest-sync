# nest-sync

**中文** | [English](README.en.md)

nest-sync 把 agent 的技能与项目日志收进同一个 Git 仓库。第一版在 2026 年 8 月上服务器
跑通，此后一直在几台机器上日常使用。

它针对的场景是：同一批 agent，跑在不同的服务器上。

## 为什么

起点是备忘录。起初笔者用备忘录唤回 agent 的上下文，一个 agent 一段记录，agent 多起来
之后，同步备忘录就成了体力活：同一份上下文要在几个地方各存一份，改了一处，其余几处
并不知情。

技能上的麻烦更多一层。技能靠迭代，而迭代的灵感往往结伴而来，同时开着几个任务，同一段
时间里可能冒出好几个改进想法，各自躺在各自的会话里，攒不到一起。攒起来了还要分发，
各 harness 的技能目录互不相通，一台机器一处，手工铺一遍就是半天。

再往后是连接上的约束：本地电脑上的 agent 不常在线，云端的 agent 拿不到本地那些更新最快
的文件，两边彼此够不着。agent 之间要通信，同样没有可依托的地方。

这几件事指向同一个缺口：上下文、技能、材料各待在自己的角落。nest-sync 的做法是给它们
一个共同落点——自托管的 Git 仓库做唯一的事实来源，其余一切都只是它的包装。

## 架构速览

```
设备
  ~/.nest/git               Git 工作副本，连接用的钥匙由仓库级 core.sshCommand 固定
  ~/.nest/bin/nest          单个 bash 脚本，七个子命令
  <harness>/skills/<名字>    单层软链 → 仓库 skills/<大类>/<技能>
        │
        │  ssh git@<你的服务器>（git 用户只被允许收发仓库）
        ▼
服务器
  /srv/git/nest-sync.git        裸仓库，唯一权威副本
    hooks/pre-receive           服务端密钥闸门，绕不过
  /opt/nest-enroll/             注册受理服务（无权限用户，仅监听回环地址）
  /usr/local/sbin/nest-keys     钥匙名单管理（root，只能在服务器本地执行）
  /var/www/nest/                说明页与接入申请页
  /var/lib/nest-enroll/         待批队列、已决记录、审计日志
```

三处设计值得单独点名。

| 机制 | 作用 |
|---|---|
| 技能用软链分发 | 真身只有仓库里一份，各 harness 的技能目录放的是软链。改真身，所有 harness 立即生效，"第二份副本漂移"从结构上就不存在 |
| 工作目录用门牌对接 | 素材、附件这类项目资料住在各自的项目文件夹里，不进仓库；`.nest` 指针文件记录它对应 `logs/<节点>/`。指针可以嵌套，目录嵌套即节点嵌套。因为那些文件夹根本不是 Git 仓库，项目资料物理上推不上云端 |
| 两道密钥闸门 | 本地 `pre-commit` 与服务端 `pre-receive` 各扫一遍。本地那道允许用 `--no-verify` 绕过，服务端那道不能：前者管住手滑，后者管住有意 |

## 命令

| 命令 | 用途 |
|---|---|
| `nest pull` | 开工前，拉取云端最新并重建技能软链 |
| `nest push -m "说明"` | 收工后，回传本地改动；被拒时自动 rebase 重试一次 |
| `nest sync -m "说明"` | 先拉后推，一把梭 |
| `nest recall [项目] [关键词]` | 唤回日志。纯只读，离线与工作区脏时照常可用 |
| `nest bind [slug]` | 把当前工作目录绑定到 `logs/` 下的节点 |
| `nest status` | 看本地与云端差在哪 |
| `nest link [--force]` | 重建技能软链，按大类过滤 |

## 快速开始

需要一台能跑 SSH 与 Git 的服务器。自托管的完整步骤见 `deploy/web/nest.md`。

```bash
# 1. 生成专用钥匙（只接受 ed25519）
ssh-keygen -t ed25519 -f ~/.ssh/nest_key -N "" -C "这台机器的标识"

# 2. 提交接入申请，拿到指纹后通过另一个渠道报给管理员
#    这一步不能跳过：站点的共享密码只挡扫描器，
#    真正拦住冒名提交的是跨渠道的指纹核对

# 3. 批准后安装
curl -sS https://nest.example.com/install.sh -o /tmp/nest-install.sh
bash /tmp/nest-install.sh \
  --repo git@nest.example.com:/srv/git/nest-sync.git \
  --key ~/.ssh/nest_key --name <这台机器的标识> -y

# 4. 验证
nest status && nest recall <项目名>
```

日常只有两条约定：开工前 `nest pull`，收工后 `nest push`。懒得分的话 `nest sync`。

## 文档

| 文件 | 内容 |
|---|---|
| `docs/architecture.md` | 系统架构：Git 为中枢、子命令、软链分发、门牌机制、注册受理流程 |
| `docs/security-model.md` | 信任边界与数据分级、两道闸门、为什么密钥不做多端同步 |
| `docs/decisions.md` | 关键设计决策及其取舍，含一张"明确不做的事"清单 |
| `examples/nest-skill/` | 示例技能：一个 nest 技能该长什么样，含 references 渐进加载 |
| `examples/skill-authoring/` | 示例技能：把一次实操沉淀为可复用技能的编写规范 |
| `deploy/README.md` | 服务端部署件的组成与重新部署方式 |

## 隐患

此方案需要考虑的最大隐患是**单点**：服务器上的裸仓库是唯一权威副本，各设备的工作
副本最终都回落到它，因此不构成独立备份。仓库本身可以随时 clone 到别处，但"什么时候
想起去 clone 一次"没有机制保证。真要上生产，第三个物理位置是必须补的一环。

其次是**不适合大文件**。二进制与 Office 文档一律不入仓，进了 Git 历史就永久占空间
且删不干净。仓库的定位是纯文本内容库，需要共享图片或附件时得另想办法。

再次是同步全靠手动，没有文件监听，也没有后台进程。忘了 push 就等于没写。

## 许可与维护

MIT，见 `LICENSE`。

这是一个个人展示项目，用来把笔者自用的一套东西整理成可读的形态。issue 欢迎，
但不保证响应时间，也不承诺持续维护；未经讨论的大改动很可能被直接关闭，原因见
`docs/decisions.md`。贡献前请读 `CONTRIBUTING.md`。
