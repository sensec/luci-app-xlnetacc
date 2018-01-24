#!/bin/sh

# 声明常量
readonly packageName='com.xunlei.vip.swjsq'
readonly protocolVersion=200
readonly businessType=68
readonly sdkVersion=177662
readonly clientVersion='2.4.1.3'
readonly agent_xl="android-async-http/xl-acc-sdk/version-2.1.1.$sdkVersion"
readonly agent_down='okhttp/3.4.1'
readonly agent_up='android-async-http/xl-acc-sdk/version-1.0.0.1'
readonly client_type_down='android-swjsq'
readonly client_type_up='android-uplink'

# 声明全局变量
_bind_ip=
_http_cmd=
_peerid=
_devicesign=
_userid=
_sessionid=
_portal_down=
_portal_up=
_cur_down=
_max_down=
_cur_up=
_max_up=
_dial_account=
_needbind=
access_url=
http_args=
user_agent=
link_en=
link_cn=
lasterr=
sequence_xl=1000000
sequence_down=$(( $(date +%s) / 6 ))
sequence_up=$sequence_down

# 包含用于解析 JSON 格式返回值的函数
. /usr/share/libubox/jshn.sh

# 读取 UCI 设置相关函数
uci_get_by_name() {
	local ret=$(uci get $NAME.$1.$2 2> /dev/null)
	echo -n ${ret:=$3}
}
uci_get_by_type() {
	local ret=$(uci get $NAME.@$1[-1].$2 2> /dev/null)
	echo -n ${ret:=$3}
}
uci_get_by_bool() {
	case $(uci_get_by_name "$1" "$2" "$3") in
		1|on|true|yes|enabled) echo -n 1;;
		*) echo -n 0;;
	esac
}

# 日志和状态栏输出。1 日志文件, 2 系统日志, 4 详细模式, 8 下行状态栏, 16 上行状态栏, 32 失败状态
_log() {
	local msg=$1
	local flag=$2
	[ -z "$msg" ] && return
	[ -z "$flag" ] && flag=1
	local timestamp=$(date +'%Y/%m/%d %H:%M:%S')

	[ $logging -eq 0 -a $(( $flag & 1 )) -ne 0 ] && flag=$(( $flag ^ 1 ))
	if [ $verbose -eq 0 -a $(( $flag & 4 )) -ne 0 ]; then
		[ $(( $flag & 1 )) -ne 0 ] && flag=$(( $flag ^ 1 ))
		[ $(( $flag & 2 )) -ne 0 ] && flag=$(( $flag ^ 2 ))
	fi
	if [ $down_acc -eq 0 -a $(( $flag & 8 )) -ne 0 ]; then
		flag=$(( $flag ^ 8 ))
		[ $up_acc -ne 0 ] && flag=$(( $flag | 16 ))
	fi
	if [ $up_acc -eq 0 -a $(( $flag & 16 )) -ne 0 ]; then
		flag=$(( $flag ^ 16 ))
		[ $down_acc -ne 0 ] && flag=$(( $flag | 8 ))
	fi

	[ $(( $flag & 1 )) -ne 0 ] && echo "$timestamp $msg" >> $LOGFILE 2> /dev/null
	[ $(( $flag & 2 )) -ne 0 ] && logger -p "daemon.info" -t "$NAME" "$msg"

	[ $(( $flag & 32 )) -eq 0 ] && local color="green" || local color="red"
	[ $(( $flag & 8 )) -ne 0 ] && echo -n "<font color=$color>$timestamp $msg</font>" > $down_state_file 2> /dev/null
	[ $(( $flag & 16 )) -ne 0 ] && echo -n "<font color=$color>$timestamp $msg</font>" > $up_state_file 2> /dev/null
}

# 清理日志
clean_log() {
	[ $logging -eq 1 -a -f "$LOGFILE" ] || return
	if [ $(wc -l "$LOGFILE" | awk '{print $1}') -gt 500 ]; then
		_log "清理日志文件"
		local logdata=$(tail -n 300 "$LOGFILE")
		echo "$logdata" > $LOGFILE 2> /dev/null
		unset logdata
	fi
}

# 获取接口IP地址
get_bind_ip() {
	json_cleanup; json_load "$(ubus call network.interface.$network status 2> /dev/null)" >/dev/null 2>&1
	json_select "ipv4-address" >/dev/null 2>&1; json_select 1 >/dev/null 2>&1
	json_get_var _bind_ip "address"
	_log "_bind_ip is $_bind_ip" $(( 1 | 4 ))
	if [ -z "$_bind_ip" -o "$_bind_ip"x == "0.0.0.0"x ]; then
		_log "获取网络 $network IP地址失败"
		return 1
	else
		_log "绑定IP地址: $_bind_ip"
		return 0
	fi
}

# 定义基本 HTTP 命令和参数
gen_http_cmd() {
	_http_cmd="wget-ssl -nv -t 1 -O - --no-check-certificate --compression=gzip"
	_http_cmd="$_http_cmd --bind-address=$_bind_ip"
	_log "_http_cmd is $_http_cmd" $(( 1 | 4 ))
}

# 生成设备标识
gen_device_sign() {
	local ifname macaddr
	while : ; do
		ifname=$(uci get "network.$network.ifname" 2> /dev/null)
		[ "${ifname:0:1}" == "@" ] && network="${ifname:1}" || break
	done
	[ -z "$ifname" ] && { _log "获取网络 $network 信息出错"; return; }
	json_cleanup; json_load "$(ubus call network.device status {\"name\":\"$ifname\"} 2> /dev/null)" >/dev/null 2>&1
	json_get_var macaddr "macaddr"
	[ -z "$macaddr" ] && { _log "获取网络 $network MAC地址出错"; return; }
	macaddr=$(echo -n "$macaddr" | awk '{print toupper($0)}')

	# 计算peerID
	readonly _peerid="${macaddr//:/}004V"
	_log "_peerid is $_peerid" $(( 1 | 4 ))

	# 计算devicesign
	# sign = div.10?.device_id + md5(sha1(packageName + businessType + md5(a protocolVersion specific GUID)))
	local fake_device_id=$(echo -n "$macaddr" | md5sum | awk '{print $1}')
	local fake_device_sign=$(echo -n "${fake_device_id}${packageName}${businessType}c7f21687eed3cdb400ca11fc2263c998" \
		| openssl sha1 -hmac | awk '{print $2}')
	readonly _devicesign="div101.${fake_device_id}"$(echo -n "$fake_device_sign" | md5sum | awk '{print $1}')
	_log "_devicesign is $_devicesign" $(( 1 | 4 ))
}

# 快鸟帐号通用参数
swjsq_json() {
	let sequence_xl++
	# 生成POST数据
	json_init
	json_add_string protocolVersion "$protocolVersion"
	json_add_string sequenceNo "$sequence_xl"
	json_add_string platformVersion '2'
	json_add_string isCompressed '0'
	json_add_string businessType "$businessType"
	json_add_string clientVersion "$clientVersion"
	json_add_string peerID "$_peerid"
	json_add_string appName "ANDROID-$packageName"
	json_add_string sdkVersion "$sdkVersion"
	json_add_string devicesign "$_devicesign"
	json_add_string deviceModel 'MI'
	json_add_string deviceName 'Xiaomi Mi'
	json_add_string OSVersion "7.1.1"
}

# 帐号登录
swjsq_login() {
	swjsq_json
	json_add_string userName "$username"
	json_add_string passWord "$password"
	json_add_string verifyKey
	json_add_string verifyCode
	json_close_object

	local ret=$($_http_cmd --user-agent="$agent_xl" 'https://mobile-login.xunlei.com:443/login' --post-data="$(json_dump)")
	_log "ret is $ret" $(( 1 | 4 ))
	json_cleanup; json_load "$ret" >/dev/null 2>&1
	json_get_var lasterr "errorCode"
	json_get_var _userid "userID"
	_log "_userid is $_userid" $(( 1 | 4 ))
	json_get_var _sessionid "sessionID"
	_log "_sessionid is $_sessionid" $(( 1 | 4 ))

	if [ ${lasterr:=-1} -ne 0 ] || [ -z "$_userid" -o -z "$_sessionid" ]; then
		[ $lasterr -eq 0 ] && lasterr=-2
		local errorDesc
		json_get_var errorDesc "errorDesc"
		local outmsg="帐号登录失败。错误代码: ${lasterr}"; \
			[ -n "$errorDesc" ] && outmsg="${outmsg}，原因: $errorDesc"; _log "$outmsg" $(( 1 | 8 | 32 ))
	else
		local outmsg="帐号登录成功"; _log "$outmsg" $(( 1 | 8 ))
	fi

	[ $lasterr -eq 0 ] && return 0 || return 1
}

# 帐号注销
swjsq_logout() {
	swjsq_json
	json_add_string userID "$_userid"
	json_add_string sessionID "$_sessionid"
	json_close_object

	local ret=$($_http_cmd --user-agent="$agent_xl" 'https://mobile-login.xunlei.com:443/logout' --post-data="$(json_dump)")
	_log "ret is $ret" $(( 1 | 4 ))
	json_cleanup; json_load "$ret" >/dev/null 2>&1
	json_get_var lasterr "errorCode"

	if [ ${lasterr:=-1} -ne 0 ]; then
		local errorDesc
		json_get_var errorDesc "errorDesc"
		local outmsg="帐号注销失败。错误代码: ${lasterr}"; \
			[ -n "$errorDesc" ] && outmsg="${outmsg}，原因: $errorDesc"; _log "$outmsg" $(( 1 | 8 | 32 ))
	else
		local outmsg="帐号注销成功"; _log "$outmsg" $(( 1 | 8 ))
		_userid=; _sessionid=
	fi

	[ $lasterr -eq 0 ] && return 0 || return 1
}

# 获取用户信息
swjsq_getuserinfo() {
	[ $1 -eq 1 ] && local _vasid=14 || local _vasid=33
	swjsq_json
	json_add_string userID "$_userid"
	json_add_string sessionID "$_sessionid"
	json_add_string vasid "$_vasid"
	json_close_object

	local ret=$($_http_cmd --user-agent="$agent_xl" 'https://mobile-login.xunlei.com:443/getuserinfo' --post-data="$(json_dump)")
	_log "ret is $ret" $(( 1 | 4 ))
	json_cleanup; json_load "$ret" >/dev/null 2>&1
	local vasid isvip isyear expiredate index
	json_get_var lasterr "errorCode"
	json_select "vipList" >/dev/null 2>&1
	until [ ${vasid:-0} -eq $_vasid ]; do
		json_select ${index:=1} >/dev/null 2>&1
		[ $? -ne 0 ] && break
		json_get_var vasid "vasid"
		json_get_var isvip "isVip"
		json_get_var isyear "isYear"
		json_get_var expiredate "expireDate"
		json_select ".." >/dev/null 2>&1
		let index++
	done

	[ $1 -eq 1 ] && link_cn="下行" || link_cn="上行"
	if [ ${lasterr:=-1} -ne 0 ]; then
		local errorDesc
		json_get_var errorDesc "errorDesc"
		local outmsg="获取${link_cn}提速会员信息失败。错误代码: ${lasterr}"; \
			[ -n "$errorDesc" ] && outmsg="${outmsg}，原因: $errorDesc"; _log "$outmsg" $(( 1 | $1 * 8 | 32 ))
	elif [ ${vasid:-0} -ne $_vasid ] || [ ${isvip:-0} -eq 0 -a ${isyear:-0} -eq 0 ] || [ "${expiredate:-00000000}" \< "$(date +'%Y%m%d')" ]; then
		local outmsg="${link_cn}提速会员无效或已到期。"; _log "$outmsg" $(( 1 | $1 * 8 | 32 ))
		[ $1 -eq 1 ] && down_acc=0 || up_acc=0
	else
		local outmsg="获取${link_cn}提速会员信息成功。会员到期时间：${expiredate:0:4}-${expiredate:4:2}-${expiredate:6:2}"; \
			_log "$outmsg" $(( 1 | $1 * 8 ))
	fi

	[ $lasterr -eq 0 ] && return 0 || return 1
}

# 获取提速入口
swjsq_portal() {
	xlnetacc_var $1

	[ $1 -eq 1 ] && access_url='http://api.portal.swjsq.vip.xunlei.com:81/v2/queryportal' || \
		access_url='http://api.upportal.swjsq.vip.xunlei.com/v2/queryportal'
	local ret=$($_http_cmd --user-agent="$user_agent" "$access_url")
	_log "$link_en portal is $ret" $(( 1 | 4 ))
	json_cleanup; json_load "$ret" >/dev/null 2>&1
	local portal_ip portal_port
	json_get_var lasterr "errno"
	json_get_var portal_ip "interface_ip"
	json_get_var portal_port "interface_port"
	json_get_var province "province_name"
	json_get_var sp "sp_name"

	if [ ${lasterr:=-1} -ne 0 ] || [ -z "$portal_ip" -o -z "$portal_port" ]; then
		[ $lasterr -eq 0 ] && lasterr=-2
		local message
		json_get_var message "message"
		local outmsg="获取${link_cn}入口失败。错误代码: ${lasterr}"; \
			[ -n "$message" ] && outmsg="${outmsg}，原因: $message"; _log "$outmsg" $(( 1 | $1 * 8 | 32 ))
	else
		if [ $1 -eq 1 ]; then
			_portal_down="http://$portal_ip:$portal_port/v2"
			_log "_portal_down is $_portal_down" $(( 1 | 4 ))
		else
			_portal_up="http://$portal_ip:$portal_port/v2"
			_log "_portal_up is $_portal_up" $(( 1 | 4 ))
		fi
	fi

	[ $lasterr -eq 0 ] && return 0 || return 1
}

get_portal() {
	local province sp
	xlnetacc_retry 'swjsq_portal' 1
	xlnetacc_retry 'swjsq_portal' 2 1
	local outmsg="获取提速入口成功"; \
		[ -n "$province" -a -n "$sp" ] && outmsg="${outmsg}。运营商：${province}${sp}"; _log "$outmsg" $(( 1 | 8 ))
}

get_bandwidth() {
	local can_upgrade stream speedup cur_bandwidth max_bandwidth
	[ $1 -eq 1 ] && { can_upgrade="can_upgrade"; stream="downstream"; } || { can_upgrade="can_upspeedup"; stream="upstream"; }
	json_cleanup; json_load "$2" >/dev/null 2>&1

	# 获取带宽数据
	json_get_var speedup "$can_upgrade"
	json_select; json_select "bandwidth" >/dev/null 2>&1
	json_get_var cur_bandwidth "$stream"
	json_select; json_select "max_bandwidth" >/dev/null 2>&1
	json_get_var max_bandwidth "$stream"
	cur_bandwidth=$(expr ${cur_bandwidth:-0} / 1024)
	max_bandwidth=$(expr ${max_bandwidth:-0} / 1024)

	[ $1 -eq 1 ] && link_cn="下行" || link_cn="上行"
	if [ $speedup -eq 0 ]; then
		local richmessage
		json_select; json_get_var richmessage "richmessage"
		local outmsg="${link_cn}无法提速"; \
			[ -n "$richmessage" ] && outmsg="${outmsg}，原因: $richmessage"; _log "$outmsg" $(( 1 | $1 * 8 | 32 ))
		[ $1 -eq 1 ] && down_acc=0 || up_acc=0
	elif [ $cur_bandwidth -ge $max_bandwidth ]; then
		local outmsg="${link_cn}无需提速。当前带宽 ${cur_bandwidth}M，超过最大可提升带宽 ${max_bandwidth}M"; \
			_log "$outmsg" $(( 1 | $1 * 8 ))
		[ $1 -eq 1 ] && down_acc=0 || up_acc=0
	else
		local outmsg="${link_cn}可以提速。当前带宽 ${cur_bandwidth}M，可提升至 ${max_bandwidth}M"; _log "$outmsg" $(( 1 | $1 * 8 ))
		if [ $1 -eq 1 ]; then
			_cur_down=$cur_bandwidth
			_log "_cur_down is $_cur_down" $(( 1 | 4 ))
			_max_down=$max_bandwidth
			_log "_max_down is $_max_down" $(( 1 | 4 ))
		else
			_cur_up=$cur_bandwidth
			_log "_cur_up is $_cur_up" $(( 1 | 4 ))
			_max_up=$max_bandwidth
			_log "_max_up is $_max_up" $(( 1 | 4 ))
		fi
	fi
}

# 获取网络带宽信息
isp_bandwidth() {
	xlnetacc_var 1

	local ret=$($_http_cmd --user-agent="$user_agent" "$access_url/bandwidth?$http_args")
	_log "bandwidth is $ret" $(( 1 | 4 ))
	json_cleanup; json_load "$ret" >/dev/null 2>&1
	local bind_dial_account dial_account
	json_get_var lasterr "errno"
	json_get_var bind_dial_account "bind_dial_account"
	json_get_var dial_account "dial_account"

	if [ ${lasterr:=-1} -ne 0 ]; then
		local richmessage
		json_get_var richmessage "richmessage"
		local outmsg="获取网络带宽信息失败。错误代码: ${lasterr}"; \
			[ -n "$richmessage" ] && outmsg="${outmsg}，原因: $richmessage"; _log "$outmsg" $(( 1 | 8 | 32 ))
	elif [ -n "$bind_dial_account" -a "$bind_dial_account" != "$dial_account" ]; then
		local outmsg="绑定宽带账号 $bind_dial_account 与当前宽带账号 $dial_account 不一致，请联系迅雷客服解绑（每月仅一次）。"; \
			_log "$outmsg" $(( 1 | 8 | 32 ))
		down_acc=0; up_acc=0
	else
		[ $down_acc -eq 1 ] && get_bandwidth 1 "$ret"
		[ $up_acc -eq 1 ] && get_bandwidth 2 "$ret"
		[ -z "$bind_dial_account" ] && _needbind=1
		_dial_account=$dial_account
		_log "_dial_account is $_dial_account" $(( 1 | 4 ))
	fi

	[ $lasterr -eq 0 ] && return 0 || return 1
}

# 发送带宽提速信号
isp_upgrade() {
	xlnetacc_var $1

	local ret=$($_http_cmd --user-agent="$user_agent" "$access_url/upgrade?$http_args")
	_log "$link_en upgrade is $ret" $(( 1 | 4 ))
	json_cleanup; json_load "$ret" >/dev/null 2>&1
	json_get_var lasterr "errno"

	if [ ${lasterr:=-1} -ne 0 ]; then
		local richmessage
		json_get_var richmessage "richmessage"
		local outmsg="${link_cn}提速失败。错误代码: ${lasterr}"; \
			[ -n "$richmessage" ] && outmsg="${outmsg}，原因: $richmessage"; _log "$outmsg" $(( 1 | $1 * 8 | 32 ))
	else
		[ $1 -eq 1 ] && local cur_bandwidth=$_cur_down || local cur_bandwidth=$_cur_up
		[ $1 -eq 1 ] && local max_bandwidth=$_max_down || local max_bandwidth=$_max_up
		local outmsg="${link_cn}提速成功，带宽已从 ${cur_bandwidth}M 提升到 ${max_bandwidth}M"; _log "$outmsg" $(( 1 | $1 * 8 ))
		[ $1 -eq 1 ] && down_acc=2 || up_acc=2
	fi

	[ $lasterr -eq 0 ] && return 0 || return 1
}

# 发送提速心跳信号
isp_keepalive() {
	xlnetacc_var $1

	local ret=$($_http_cmd --user-agent="$user_agent" "$access_url/keepalive?$http_args")
	_log "$link_en keepalive is $ret" $(( 1 | 4 ))
	json_cleanup; json_load "$ret" >/dev/null 2>&1
	json_get_var lasterr "errno"

	if [ ${lasterr:=-1} -ne 0 ]; then
		local richmessage
		json_get_var richmessage "richmessage"
		local outmsg="${link_cn}提速失效。错误代码: ${lasterr}"; \
			[ -n "$richmessage" ] && outmsg="${outmsg}，原因: $richmessage"; _log "$outmsg" $(( 1 | $1 * 8 | 32 ))
		[ $1 -eq 1 ] && down_acc=1 || up_acc=1
	else
		_log "${link_cn}心跳信号返回正常"
	fi

	[ $lasterr -eq 0 ] && return 0 || return 1
}

# 发送带宽恢复信号
isp_recover() {
	xlnetacc_var $1

	local ret=$($_http_cmd --user-agent="$user_agent" "$access_url/recover?$http_args")
	_log "$link_en recover is $ret" $(( 1 | 4 ))
	json_cleanup; json_load "$ret" >/dev/null 2>&1
	json_get_var lasterr "errno"

	if [ ${lasterr:=-1} -ne 0 ]; then
		local richmessage
		json_get_var richmessage "richmessage"
		local outmsg="${link_cn}带宽恢复失败。错误代码: ${lasterr}"; \
			[ -n "$richmessage" ] && outmsg="${outmsg}，原因: $richmessage"; _log "$outmsg" $(( 1 | $1 * 8 | 32 ))
	else
		_log "${link_cn}带宽已恢复"
		[ $1 -eq 1 ] && down_acc=1 || up_acc=1
	fi

	[ $lasterr -eq 0 ] && return 0 || return 1
}

# 查询提速信息，未使用
isp_query() {
	xlnetacc_var $1

	local ret=$($_http_cmd --user-agent="$user_agent" "$access_url/query_try_info?$http_args")
	_log "$link_en query_try_info is $ret" $(( 1 | 4 ))
	json_cleanup; json_load "$ret" >/dev/null 2>&1
	json_get_var lasterr "errno"

	[ $lasterr -eq 0 ] && return 0 || return 1
}

# 设置参数变量
xlnetacc_var() {
	if [ $1 -eq 1 ]; then
		let sequence_down++
		access_url=$_portal_down
		http_args="sequence=${sequence_down}&client_type=${client_type_down}-${clientVersion}&client_version=${client_type_down//-/}-${clientVersion}&chanel=umeng-10900011&time_and=$(date +%s)000"
		user_agent=$agent_down
		link_en="DownLink"
		link_cn="下行"
	else
		let sequence_up++
		access_url=$_portal_up
		http_args="sequence=${sequence_up}&client_type=${client_type_up}-${clientVersion}&client_version=${client_type_up//-/}-${clientVersion}"
		user_agent=$agent_up
		link_en="UpLink"
		link_cn="上行"
	fi
	http_args="${http_args}&peerid=${_peerid}&userid=${_userid}&sessionid=${_sessionid}&user_type=1&os=android-7.1.1"
	if [ -n "$_dial_account" ]; then
		http_args="${http_args}&dial_account=${_dial_account}"
		[ ${_needbind:-0} -ne 0 ] && { http_args="${http_args}&needbind=1"; _needbind=0; }
	fi
	_log "http_args is $http_args" $(( 1 | 4 ))
}

# 重试循环
xlnetacc_retry() {
	if [ $# -ge 3 ]; then
		[ $2 -eq 1 -a $down_acc -ne $3 ] && return 0
		[ $2 -eq 2 -a $up_acc -ne $3 ] && return 0
	fi
	local retry=0
	while : ; do
		lasterr=
		eval $1 $2 && break # 成功
		let retry++
		[ $# -ge 4 -a $retry -ge $4 ] && break # 重试超时
		sleep 3s
	done
	[ ${lasterr:-0} -eq 0 ] && return 0 || return 1
}

# 注销已登录帐号
xlnetacc_logout() {
	[ -z "$_sessionid" ] && return 2
	[ $# -ge 1 ] && local retry=$1 || local retry=1

	xlnetacc_retry 'isp_recover' 1 2 $retry
	xlnetacc_retry 'isp_recover' 2 2 $retry
	xlnetacc_retry 'swjsq_logout' 0 0 $retry
	[ $down_acc -ne 0 ] && down_acc=1; [ $up_acc -ne 0 ] && up_acc=1
	_userid=; _sessionid=; _dial_account=

	[ $lasterr -eq 0 ] && return 0 || return 1
}

# 中止信号处理
sigterm() {
	_log "trap sigterm, exit" $(( 1 | 4 ))
	xlnetacc_logout
	rm -f "$down_state_file" "$up_state_file"
	exit 0
}

# 初始化
xlnetacc_init() {
	[ "$1" != "--start" ] && return 1

	# 防止重复启动
	local pid
	for pid in $(pidof "${0##*/}"); do
		[ $pid -ne $$ ] && return 1
	done

	# 读取设置
	readonly NAME=xlnetacc
	readonly LOGFILE=/var/log/${NAME}.log
	readonly down_state_file=/var/state/${NAME}_down_state
	readonly up_state_file=/var/state/${NAME}_up_state
	down_acc=$(uci_get_by_bool "general" "down_acc" 0)
	up_acc=$(uci_get_by_bool "general" "up_acc" 0)
	readonly logging=$(uci_get_by_bool "general" "logging" 1)
	readonly verbose=$(uci_get_by_bool "general" "verbose" 0)
	readonly network=$(uci_get_by_name "general" "network" "wan")
	readonly username=$(uci_get_by_name "general" "account")
	readonly password=$(uci_get_by_name "general" "password")
	local enabled=$(uci_get_by_bool "general" "enabled" 0)
	( [ $enabled -eq 0 ] || [ $down_acc -eq 0 -a $up_acc -eq 0 ] || [ -z "$username" -o -z "$password" -o -z "$network" ] ) && return 2

	[ $logging -eq 1 ] && [ ! -d /var/log ] && mkdir -p /var/log
	[ -f "$LOGFILE" ] && _log "------------------------------"
	_log "迅雷快鸟正在启动..."

	# 检查外部调用工具
	command -v wget-ssl >/dev/null || { _log "GNU Wget 工具不存在"; return 3; }
	command -v md5sum >/dev/null || { _log "md5sum 工具不存在"; return 3; }
	command -v openssl >/dev/null || { _log "openssl 工具不存在"; return 3; }

	# 捕获中止信号
	trap 'sigterm' INT # Ctrl-C
	trap 'sigterm' QUIT # Ctrl-\
	trap 'sigterm' TERM # kill

	# 生成设备标识
	gen_device_sign
	[ -z "$_peerid" -o -z "$_devicesign" ] && return 4

	clean_log
	[ -d /var/state ] || mkdir -p /var/state
	return 0
}

# 程序主体
xlnetacc_main() {
	while : ; do
		# 获取外网IP地址
		xlnetacc_retry 'get_bind_ip'
		gen_http_cmd

		# 注销快鸟帐号
		xlnetacc_logout 3 && sleep 3s

		# 登录快鸟帐号
		while : ; do
			lasterr=
			swjsq_login
			case $lasterr in
				0) break;; # 登录成功
				-1) sleep 3s;; # 未返回任何数据，等待3秒后重试
				-2) sleep 3m;; # 未返回有效数据，等待3分钟后重试
				6) sleep 130m;; # 需要输入验证码，等待130分钟后重试
				*) return 5;; # 登录失败
			esac
		done

		# 获取用户信息
		xlnetacc_retry 'swjsq_getuserinfo' 1 1
		xlnetacc_retry 'swjsq_getuserinfo' 2 1
		[ $down_acc -eq 0 -a $up_acc -eq 0 ] && break
		# 获取提速入口
		get_portal
		# 获取带宽信息
		xlnetacc_retry 'isp_bandwidth'
		[ $down_acc -eq 0 -a $up_acc -eq 0 ] && break
		# 带宽提速
		xlnetacc_retry 'isp_upgrade' 1 1
		xlnetacc_retry 'isp_upgrade' 2 1

		# 心跳保持
		while : ; do
			clean_log # 清理日志
			sleep 10m
			xlnetacc_retry 'isp_keepalive' 1 2 3 || break
			xlnetacc_retry 'isp_keepalive' 2 2 3 || break
		done
	done
	xlnetacc_logout
	_log "无法提速，迅雷快鸟已停止。"
	return 6
}

# 程序入口
xlnetacc_init "$@" && xlnetacc_main
exit $?
