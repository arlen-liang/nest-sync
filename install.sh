#!/usr/bin/env bash
# nest 安装脚本 — 在新设备上一次性执行
#
#   新设备：  bash install.sh --repo git@nest.example.com:/srv/git/nest-sync.git \
#                             --key ~/.ssh/nest_key --name <标识> [-y]
#   已有副本：bash ~/.nest/git/install.sh
#
# 流程：先本地探索已有仓库（找到就复用，绝不重复克隆）→ 找不到才显示
# 绝对目标地址并要求确认 → 克隆。仓库位置是死约定 ~/.nest/git，与当前目录无关。

set -euo pipefail

NEST_HOME_EXPLICIT="${NEST_HOME:+1}"
NEST_HOME="${NEST_HOME:-$HOME/.nest}"
NEST_BRAIN="${NEST_BRAIN:-$NEST_HOME/git}"
REPO_URL=""
DO_LINK=1
IDENT_NAME=""
KEY_PATH=""
ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO_URL="${2:-}"; shift 2 ;;
    --key)  KEY_PATH="${2:-}"; shift 2 ;;
    --name) IDENT_NAME="${2:-}"; shift 2 ;;
    --no-link) DO_LINK=0; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    *) echo "未知参数：$1" >&2; exit 1 ;;
  esac
done

# 0. 本地探索：目标位置没有仓库时，先扫全机有没有别处的副本。
# 初次接入最容易犯的错就是明明装过还再拉一份（PATH 没带上时探测会误报没装）。
# 显式设置了 NEST_HOME 视为刻意另装（如盲测），跳过这道闸。
if [ ! -d "$NEST_BRAIN/.git" ] && [ -z "$NEST_HOME_EXPLICIT" ]; then
  FOUND=""
  for d in "$HOME"/.nest*/git "$HOME"/.nest*/brain; do
    [ -d "$d/.git" ] && FOUND="$FOUND    $d"$'\n'
  done
  if [ -n "$FOUND" ]; then
    echo "✗ 本机已有 nest 仓库，不再新建：" >&2
    printf '%s' "$FOUND" >&2
    echo "  共用它（推荐）：bash <上面的路径>/install.sh" >&2
    echo "  只想把技能接进当前 harness：<上面的路径去掉 git|brain>/bin/nest link" >&2
    echo "  确要独立另装（如盲测）：NEST_HOME=~/.nest-<标识> 重跑本脚本" >&2
    exit 1
  fi
fi

# 1. 克隆或复用工作副本
if [ -d "$NEST_BRAIN/.git" ]; then
  echo "已有工作副本：$NEST_BRAIN"
elif [ -n "$REPO_URL" ]; then
  echo "本机没有 nest 仓库。将克隆到（绝对路径，全机唯一，与当前目录无关）："
  echo "    $NEST_BRAIN"
  if [ "$ASSUME_YES" != 1 ]; then
    if : 2>/dev/null </dev/tty; then
      printf '确认地址无误？[y/N] '
      REPLY=""; read -r REPLY </dev/tty || true
      case "$REPLY" in y|Y|yes|YES) ;; *) echo "已取消"; exit 1 ;; esac
    else
      echo "✗ 非交互环境：确认上面的地址无误后，加 -y 重跑" >&2
      exit 1
    fi
  fi
  mkdir -p "$(dirname "$NEST_BRAIN")"
  if [ -n "$KEY_PATH" ]; then
    GIT_SSH_COMMAND="ssh -i $KEY_PATH -o IdentitiesOnly=yes" git clone "$REPO_URL" "$NEST_BRAIN"
    # 钥匙固定到仓库级，之后所有 git 操作用它，不受 ~/.ssh/config 影响
    git -C "$NEST_BRAIN" config core.sshCommand "ssh -i $KEY_PATH -o IdentitiesOnly=yes"
  else
    git clone "$REPO_URL" "$NEST_BRAIN"
  fi
else
  echo "✗ $NEST_BRAIN 不存在，请用 --repo <url> 指定仓库地址" >&2
  exit 1
fi

mkdir -p "$NEST_HOME"
chmod 700 "$NEST_HOME"

# 中文文件名不要被 git 输出成八进制转义
git -C "$NEST_BRAIN" config core.quotepath false

# 仓库级 git 身份：没有 author，第一次提交会被 git 打断。
# 只写本仓库（--local），不污染这台机器的其他仓库；显式 --name 时覆盖，否则已有身份不动。
if [ -n "$IDENT_NAME" ] || ! git -C "$NEST_BRAIN" var GIT_AUTHOR_IDENT >/dev/null 2>&1; then
  ident="${IDENT_NAME:-$(whoami)-$(hostname -s 2>/dev/null || hostname)}"
  ident="$(printf '%s' "$ident" | tr ' ' '-')"
  git -C "$NEST_BRAIN" config user.name "$ident"
  git -C "$NEST_BRAIN" config user.email "${ident}@nest.local"
  echo "✓ 仓库级 git 身份：$ident <${ident}@nest.local>（改名重跑 --name <名字>）"
fi

# 2. 装 pre-commit hook（密钥闸门）
if [ -f "$NEST_BRAIN/hooks/pre-commit" ]; then
  ln -sfn "$NEST_BRAIN/hooks/pre-commit" "$NEST_BRAIN/.git/hooks/pre-commit"
  chmod +x "$NEST_BRAIN/hooks/pre-commit"
  echo "✓ pre-commit 密钥扫描已启用"
fi
command -v gitleaks >/dev/null 2>&1 || echo "! 未装 gitleaks，将使用内置正则兜底（建议安装）"

# 3. 装命令到 ~/.nest/bin
mkdir -p "$NEST_HOME/bin"
chmod +x "$NEST_BRAIN/bin/nest"
ln -sfn "$NEST_BRAIN/bin/nest" "$NEST_HOME/bin/nest"
for sub in sync pull push status recall link bind; do
  ln -sfn "$NEST_BRAIN/bin/nest" "$NEST_HOME/bin/nest-$sub"
done
echo "✓ 命令已装到 $NEST_HOME/bin"

# 4. 建软链
if [ "$DO_LINK" = 1 ]; then
  "$NEST_HOME/bin/nest" link
else
  echo "! 已跳过软链，稍后手动运行：nest link"
fi

# 5. 身份自检 —— 确认这个仓库实际会用哪把钥匙
#
# 在多 agent 共用同一个 Unix 账号时，~/.ssh/config 里可能有多个同名 Host 块。
# SSH 对 IdentityFile 是累积并按顺序尝试的，排在前面的别人的钥匙一旦有效就会被采用，
# 你自己的钥匙根本轮不到 —— clone 会"成功"，但用的是别人的身份。
echo
SSHCMD="$(git -C "$NEST_BRAIN" config --get core.sshCommand || true)"
if [ -n "$SSHCMD" ]; then
  KEYPATH="$(printf '%s\n' "$SSHCMD" | sed -n 's/.*-i[[:space:]]*\([^[:space:]]*\).*/\1/p')"
  KEYPATH="$(eval echo "$KEYPATH")"
  if [ -f "$KEYPATH.pub" ]; then
    echo "✓ 本仓库固定使用：$KEYPATH"
    echo "  指纹 $(ssh-keygen -lf "$KEYPATH.pub" | awk '{print $2}')"
  else
    echo "✓ 本仓库固定使用：$KEYPATH"
  fi
else
  echo "! 本仓库未固定钥匙，依赖 ~/.ssh/config 的解析结果"
  REMOTE_HOST="$(git -C "$NEST_BRAIN" remote get-url origin 2>/dev/null | sed 's/:.*//;s/.*@//')"
  if [ -n "$REMOTE_HOST" ]; then
    DUPES="$(grep -ci "^[[:space:]]*Host[[:space:]].*\b$REMOTE_HOST\b" "$HOME/.ssh/config" 2>/dev/null || echo 0)"
    if [ "${DUPES:-0}" -gt 1 ]; then
      echo "  ⚠ ~/.ssh/config 里有 $DUPES 个 Host $REMOTE_HOST 块，很可能用错身份"
    fi
    echo "  实际会依次尝试："
    ssh -G "$REMOTE_HOST" 2>/dev/null | awk '/^identityfile /{print "    " $2}'
  fi
  echo "  建议固定到自己的钥匙，避免在共用账号上串身份："
  echo "    git -C $NEST_BRAIN config core.sshCommand \\"
  echo "        \"ssh -i ~/.ssh/你的钥匙 -o IdentitiesOnly=yes\""
fi

# 6. PATH 提示
case ":$PATH:" in
  *":$NEST_HOME/bin:"*) ;;
  *)
    echo
    echo "还差一步 — 把 nest 加进 PATH："
    echo "  echo 'export PATH=\"$NEST_HOME/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
    echo
    echo "  不需要持久化 NEST_HOME：nest 命令会从自身位置反推所属仓库。"
    ;;
esac

echo
echo "完成。开工前 nest pull，收工后 nest push。"
