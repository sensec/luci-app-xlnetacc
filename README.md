# luci-app-xlnetacc
适用于 OpenWRT/LEDE 纯Shell实现的迅雷快鸟客户端

依赖: wget openssl-util


更新到支持快鸟新协议 300

详情见恩山论坛介绍帖 [依然是改良作品，这次的目标是 -- 迅雷快鸟](http://www.right.com.cn/forum/thread-267641-1-1.html)

# Fix
* 增加验证码获取，解决 "为了您的帐号安全，请输入图形验证码[6]" 问题，不建议开启帐号重新登录
* 适配高版本 OpenWRT
* 支持配置 ChatGPT 验证码识别（默认 OpenRoute，未配置 API Key 时使用手动输入）
