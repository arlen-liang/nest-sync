#!/usr/bin/env python3
"""nest 注册受理服务 —— 只负责收申请，不负责放行。

安全边界（重要）：
  本服务以无权限用户 nest-enroll 运行，唯一的写权限是 PENDING_DIR。
  它碰不到 authorized_keys。真正写入钥匙名单的是 nest-keys（只能在服务器本地用 root 跑）。
  即使本服务被完全攻破，攻击者也只能往待批队列里塞垃圾。

只用标准库，无第三方依赖。
"""

import json
import os
import re
import secrets
import subprocess
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN = ("127.0.0.1", 3100)
STATE_DIR = os.environ.get("NEST_ENROLL_STATE", "/var/lib/nest-enroll")
PENDING_DIR = os.path.join(STATE_DIR, "pending")
DECIDED_DIR = os.path.join(STATE_DIR, "decided")

MAX_BODY = 8 * 1024          # 请求体上限
MAX_PENDING = 50             # 待批队列上限，防止刷爆磁盘
RATE_WINDOW = 3600           # 单 IP 限流窗口（秒）
RATE_MAX = 10                # 窗口内最多提交次数

# 只收 ed25519：格式单一、无弱密钥问题，agent 也都能生成
PUBKEY_RE = re.compile(r"^ssh-ed25519 [A-Za-z0-9+/]{43,86}={0,3}(?: [\x20-\x7e]{0,100})?$")
NAME_RE = re.compile(r"^[a-zA-Z0-9._-]{2,32}$")

_rate = {}


def log(msg):
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)


def fingerprint(pubkey: str):
    """用 ssh-keygen 验证并取指纹。格式不合法则返回 None。"""
    tmp = None
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".pub", delete=False) as f:
            f.write(pubkey + "\n")
            tmp = f.name
        out = subprocess.run(
            ["ssh-keygen", "-l", "-f", tmp],
            capture_output=True, text=True, timeout=5,
        )
        if out.returncode != 0:
            return None
        parts = out.stdout.split()
        # 形如: 256 SHA256:xxxx comment (ED25519)
        return parts[1] if len(parts) >= 2 else None
    except Exception:
        return None
    finally:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass


def validate(payload):
    """返回 (name, pubkey, note) 或抛 ValueError。所有字段都当敌意输入处理。"""
    if not isinstance(payload, dict):
        raise ValueError("请求体必须是 JSON 对象")

    name = payload.get("name")
    pubkey = payload.get("pubkey")
    note = payload.get("note", "")

    if not isinstance(name, str) or not NAME_RE.match(name):
        raise ValueError("name 需为 2-32 位的字母、数字、点、下划线或连字符")
    if not isinstance(pubkey, str):
        raise ValueError("缺少 pubkey")
    if not isinstance(note, str) or len(note) > 200:
        raise ValueError("note 最长 200 字")

    pubkey = pubkey.strip()
    # 关键：authorized_keys 是按行解析的，任何换行都可能被用来注入额外的钥匙行
    if "\n" in pubkey or "\r" in pubkey or len(pubkey) > 512:
        raise ValueError("pubkey 必须是单行且不超过 512 字符")
    if not PUBKEY_RE.match(pubkey):
        raise ValueError("只接受 ed25519 公钥，请用 ssh-keygen -t ed25519 生成")

    fp = fingerprint(pubkey)
    if not fp:
        raise ValueError("公钥格式校验未通过")

    return name, pubkey, fp, note


def rate_limited(ip):
    now = time.time()
    hits = [t for t in _rate.get(ip, []) if now - t < RATE_WINDOW]
    if len(hits) >= RATE_MAX:
        _rate[ip] = hits
        return True
    hits.append(now)
    _rate[ip] = hits
    return False


def already_known(fp):
    """同一把钥匙重复提交时，返回原申请，避免队列里堆重复项。"""
    for d in (PENDING_DIR, DECIDED_DIR):
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for fn in names:
            if not fn.endswith(".json"):
                continue
            try:
                with open(os.path.join(d, fn)) as f:
                    rec = json.load(f)
            except Exception:
                continue
            if rec.get("fingerprint") == fp:
                return rec
    return None


class Handler(BaseHTTPRequestHandler):
    server_version = "nest-enroll"
    sys_version = ""

    def log_message(self, fmt, *args):
        log(f"{self.client_ip()} {fmt % args}")

    def client_ip(self):
        # nginx 反代，真实 IP 在 X-Forwarded-For 里
        xff = self.headers.get("X-Forwarded-For", "")
        return xff.split(",")[0].strip() if xff else self.client_address[0]

    def reply(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path.rstrip("/") != "/api/request":
            return self.reply(404, {"error": "not found"})

        ip = self.client_ip()
        if rate_limited(ip):
            log(f"限流拦截 {ip}")
            return self.reply(429, {"error": "提交过于频繁，请稍后再试"})

        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            return self.reply(400, {"error": "Content-Length 无效"})
        if length <= 0 or length > MAX_BODY:
            return self.reply(413, {"error": "请求体过大或为空"})

        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except Exception:
            return self.reply(400, {"error": "JSON 解析失败"})

        try:
            name, pubkey, fp, note = validate(payload)
        except ValueError as e:
            return self.reply(400, {"error": str(e)})

        dup = already_known(fp)
        if dup:
            return self.reply(200, {
                "id": dup["id"],
                "name": dup["name"],
                "fingerprint": fp,
                "status": dup.get("status", "pending"),
                "message": "这把钥匙已提交过，返回原申请",
            })

        try:
            if len(os.listdir(PENDING_DIR)) >= MAX_PENDING:
                return self.reply(503, {"error": "待批队列已满，请联系管理员"})
        except OSError:
            return self.reply(500, {"error": "服务端状态目录不可用"})

        req_id = secrets.token_urlsafe(12)
        rec = {
            "id": req_id,
            "name": name,
            "pubkey": pubkey,
            "fingerprint": fp,
            "note": note,
            "ip": ip,
            "submitted_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "status": "pending",
        }
        path = os.path.join(PENDING_DIR, f"{req_id}.json")
        with open(path, "w") as f:
            json.dump(rec, f, ensure_ascii=False, indent=2)
        os.chmod(path, 0o600)

        log(f"新申请 id={req_id} name={name} fp={fp} ip={ip}")
        return self.reply(201, {
            "id": req_id,
            "name": name,
            "fingerprint": fp,
            "status": "pending",
            "message": "申请已提交。请把上面这串指纹通过其他渠道告知管理员，核对后才会批准。",
        })

    def do_GET(self):
        path = self.path.rstrip("/")
        if path == "/api/health":
            return self.reply(200, {"ok": True})

        prefix = "/api/status/"
        if not self.path.startswith(prefix):
            return self.reply(404, {"error": "not found"})

        req_id = self.path[len(prefix):].strip("/")
        # 只接受自己发出去的 token 字符集，杜绝路径穿越
        if not re.match(r"^[A-Za-z0-9_-]{1,32}$", req_id):
            return self.reply(400, {"error": "id 无效"})

        for d in (PENDING_DIR, DECIDED_DIR):
            p = os.path.join(d, f"{req_id}.json")
            if os.path.exists(p):
                with open(p) as f:
                    rec = json.load(f)
                return self.reply(200, {
                    "id": rec["id"],
                    "name": rec["name"],
                    "fingerprint": rec["fingerprint"],
                    "status": rec.get("status", "pending"),
                    "decided_at": rec.get("decided_at"),
                })
        return self.reply(404, {"error": "查无此申请"})


def main():
    for d in (PENDING_DIR, DECIDED_DIR):
        os.makedirs(d, mode=0o700, exist_ok=True)
    log(f"nest-enroll 启动，监听 {LISTEN[0]}:{LISTEN[1]}，状态目录 {STATE_DIR}")
    ThreadingHTTPServer(LISTEN, Handler).serve_forever()


if __name__ == "__main__":
    main()
