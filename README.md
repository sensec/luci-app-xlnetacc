# luci-app-xlnetacc

适用于 OpenWrt / ImmortalWrt 的迅雷快鸟客户端（纯 Shell 实现，支持快鸟新协议 300）。

本项目基于 [sensec/luci-app-xlnetacc](https://github.com/sensec/luci-app-xlnetacc)，在此基础上增加了验证码登录、会话持久化、主动注销等实用功能。

## 功能

- 迅雷快鸟上下行提速（是否支持取决于运营商）
- 后台守护进程自动登录、保活
- **手动登录按钮 + 图形验证码**：账号被风控要求验证码时，直接在 LuCI 页面查看并输入
- **会话持久化**：登录成功后保存会话，重启服务 / 重启路由器 / WAN 重连时自动复用，减少验证码
- **主动注销按钮**：注销迅雷账号并撤销运营商侧提速
- **请求超时配置**：默认 20 秒（提速接口通常需要 10 秒以上）
- 状态页显示运行状态、登录状态、会员到期时间、上下行提速状态

## 依赖

- `jshn`
- `wget`（需提供 `wget-ssl`）
- `openssl-util`

## 安装

### 方式一：Release 安装包

从 [Releases](https://github.com/Talesxx/luci-app-xlnetacc/releases) 下载对应固件的包：

- OpenWrt / ImmortalWrt 21.02 – 24.10（opkg）：`luci-app-xlnetacc_*_all.ipk`

```bash
opkg install luci-app-xlnetacc_*.ipk
```

> 24.10 的 SDK 默认仍使用 opkg，产物为 `.ipk`。如果你的固件使用 apk（部分 24.10 / 25.x 快照），需要用 apk 工具链重新打包。

安装后在 LuCI「服务 → 迅雷快鸟」中配置账号密码并启用。

### 方式二：源码编译

```bash
# 在 OpenWrt SDK 中
git clone https://github.com/Talesxx/luci-app-xlnetacc.git package/luci-app-xlnetacc
./scripts/feeds update -a
./scripts/feeds install -a
make package/luci-app-xlnetacc/compile V=s
```

> 包为 `PKGARCH:=all`，一个安装包通用所有架构。

## 使用说明

1. 填写迅雷账号、密码，点击「保存并应用」。
2. 点击「登录」：
   - 正常情况直接提示登录成功，并自动勾选「启用」、启动服务；
   - 如果迅雷要求验证码，图片和输入框会出现，输入后再次点击「登录」。
3. 登录成功后会话会保存到 `/var/run/xlnetacc_session`，之后重启服务、重启路由器或 WAN 重连会自动复用，不再要求验证码。
4. 点击验证码图片可以重新获取一张验证码。
5. 点击「注销」会停止服务、注销账号并撤销运营商提速，同时取消勾选「启用」。

### 配置项

| 选项 | 说明 |
|---|---|
| 启用 | 是否运行守护进程 |
| 开启下行提速 / 上行提速 | 是否申请对应方向的提速，取决于运营商支持 |
| 指定提速接口 | 选择 WAN 接口，一般保持 `wan` |
| 保持连接周期 | 心跳间隔，5–60 分钟 |
| 帐号重新登录 | 定期重新登录；设为「未启用」可减少验证码触发 |
| 请求超时 | 单次 HTTP 请求超时，5–120 秒，默认 20 秒 |

## 安全提示

- 账号密码以明文保存在 `/etc/config/xlnetacc`，建议执行 `chmod 600 /etc/config/xlnetacc`。
- 会话文件 `/var/run/xlnetacc_session` 权限为 600，仅 root 可读。

## 常见问题

- **运营商服务器未响应**：通常是请求超时太短。提速接口实际可能需要 10 秒以上，默认已调整为 20 秒。
- **一直提示需要图形验证码**：迅雷账号触发了风控。使用页面上的「登录」按钮完成一次验证码登录即可，之后会话会被持久化复用。
- **重启后需要重新登录**：确认会话文件 `/var/run/xlnetacc_session` 是否存在；若不存在，完成一次手动登录后即可持久化。

## 许可证

GPL-2.0，与原项目一致。

## 致谢

- 原项目：[sensec/luci-app-xlnetacc](https://github.com/sensec/luci-app-xlnetacc)
- 原始讨论帖：[恩山论坛](https://www.right.com.cn/forum/thread-267641-1-1.html)
