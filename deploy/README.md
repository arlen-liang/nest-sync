# 服务端部署件

nest 的服务端组件。版本化保存在仓库里，改完用下面的方式重新部署。

## 组成

| 文件 | 部署位置 | 作用 |
|---|---|---|
| `server/nest-enroll.py` | `/opt/nest-enroll/` | 注册受理服务，以无权限用户 `nest-enroll` 运行，监听 127.0.0.1:3100 |
| `server/nest-keys` | `/usr/local/sbin/` | 钥匙名单管理，只能在服务器本地用 root 跑 |
| `server/nest-enroll.service` | `/etc/systemd/system/` | systemd 单元，已收紧文件系统权限 |
| `server/nest-enroll.nginx.inc` | `/etc/nginx/nest-enroll.inc` | 由 `conf.d/nest.conf` 的 443 块 include |
| `web/enroll.html` | `/var/www/nest/enroll/index.html` | 接入申请页面 |

## 安全边界

**受理服务写不了钥匙名单。** 它唯一的写权限是 `/var/lib/nest-enroll/`（待批队列）。
真正写 `authorized_keys` 的是 `nest-keys`，需要 root 且只能在服务器本地执行。
即使受理服务被完全攻破，攻击者也只能往队列里塞垃圾。

批准时必须显式抄一遍指纹，指纹应由申请方通过**另一个渠道**告知。
这道人工核对是整套流程的安全根基 —— 设计取舍见 `docs/security-model.md`。

## 重新部署

下面用 `prod-server` 代表你在 `~/.ssh/config` 里给服务器起的别名，按自己的实际情况替换。

```bash
scp deploy/server/nest-enroll.py  prod-server:/tmp/ && ssh prod-server 'install -m 755 /tmp/nest-enroll.py /opt/nest-enroll/nest-enroll.py && systemctl restart nest-enroll'
scp deploy/server/nest-keys       prod-server:/tmp/ && ssh prod-server 'install -m 750 /tmp/nest-keys /usr/local/sbin/nest-keys'
scp deploy/web/enroll.html        prod-server:/tmp/ && ssh prod-server 'install -m 644 /tmp/enroll.html /var/www/nest/enroll/index.html'
scp deploy/web/nest.md            prod-server:/tmp/ && ssh prod-server 'install -m 644 /tmp/nest.md /var/www/nest/nest.md'
scp deploy/web/index.html         prod-server:/tmp/ && ssh prod-server 'install -m 644 /tmp/index.html /var/www/nest/index.html'
scp install.sh                    prod-server:/tmp/ && ssh prod-server 'install -m 644 /tmp/install.sh /var/www/nest/install.sh'   # 接入第 6 步 curl 的就是它
```

## 管理命令（在服务器上）

```bash
nest-keys list                                   # 看待批申请
nest-keys approve <id> --fingerprint SHA256:xxx  # 批准，指纹必须对上
nest-keys reject <id> [理由]                     # 驳回
nest-keys authorized                             # 看当前名单
nest-keys revoke <name>                          # 吊销
```

审计日志：`/var/lib/nest-enroll/audit.log`
