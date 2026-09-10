# nest 站点附加配置：公开发现页 + 注册页面与受理接口
# 由 /etc/nginx/conf.d/nest.conf 的 443 server 块 include

# 公开的纯文本版说明，供 agent 直接 curl 读取。
# 正则 location 优先级高于前缀 location，但 /enroll/ 下没有 .md 文件，不冲突。
location ~ \.md$ {
    root         /var/www/nest;
    default_type text/plain;
    charset      utf-8;
}

location = /enroll/api/request {
    auth_basic           "nest enrollment";
    auth_basic_user_file /etc/nginx/nest-enroll.htpasswd;

    client_max_body_size 16k;
    proxy_pass           http://127.0.0.1:3100/api/request;
    proxy_set_header     X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_read_timeout   15s;
}

location /enroll/api/status/ {
    auth_basic           "nest enrollment";
    auth_basic_user_file /etc/nginx/nest-enroll.htpasswd;

    proxy_pass         http://127.0.0.1:3100/api/status/;
    proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_read_timeout 15s;
}

location /enroll/ {
    auth_basic           "nest enrollment";
    auth_basic_user_file /etc/nginx/nest-enroll.htpasswd;

    root      /var/www/nest;
    try_files $uri $uri/ /enroll/index.html;
}
