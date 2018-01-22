# luci-app-xlnetacc
适用于 OpenWRT/LEDE 的迅雷快鸟客户端

依赖: wget openssl-util


for protocolVersion 200，测试版本，作为旧版本协议失效后的临时措施。
因无法得到快鸟帐号登录相关算法，需要抓包获取 peerID 和 devicesign 两个参数，具体操作请自行搜索。抓包只需抓取帐号登录时的SSL POST包，然后提取上述两个字段。
