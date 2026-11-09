module("luci.controller.xlnetacc", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/xlnetacc") then
		return
	end

	entry({"admin", "services", "xlnetacc"},
		firstchild(), _("XLNetAcc")).dependent = false

	entry({"admin", "services", "xlnetacc", "general"},
		cbi("xlnetacc"), _("Settings"), 1)

	entry({"admin", "services", "xlnetacc", "log"},
		template("xlnetacc/logview"), _("Log"), 2)

	entry({"admin", "services", "xlnetacc", "status"}, call("action_status"))
	entry({"admin", "services", "xlnetacc", "logdata"}, call("action_log"))
	entry({"admin", "services", "xlnetacc", "login"}, call("action_login"))
	entry({"admin", "services", "xlnetacc", "logout"}, call("action_logout"))
	entry({"admin", "services", "xlnetacc", "captcha"}, call("action_captcha"))
end

local function is_running(name)
	return luci.sys.call("pidof %s >/dev/null" %{name}) == 0
end

function action_status()
	luci.http.prepare_content("application/json")
	luci.http.write_json({
		run_state = is_running("xlnetacc.sh"),
		login_state = nixio.fs.readfile("/var/state/xlnetacc_login_state") or "",
		vip_state = nixio.fs.readfile("/var/state/xlnetacc_vip_state") or "",
		down_state = nixio.fs.readfile("/var/state/xlnetacc_down_state") or "",
		up_state = nixio.fs.readfile("/var/state/xlnetacc_up_state") or ""
	})
end

-- 读取当前待输入的验证码图片
function action_captcha()
	local data = nixio.fs.readfile("/tmp/xlnetacc_captcha.png")
	if not data or data == "" then
		luci.http.status(404, "Not Found")
		return
	end
	luci.http.prepare_content("image/png")
	luci.http.header("Cache-Control", "no-store, no-cache, must-revalidate")
	luci.http.write(data)
end

-- 手动登录：账号密码 + 可选验证码，调用 xlnetacc.sh --login
function action_login()
	local uci = require "luci.model.uci".cursor()
	local util = require "luci.util"
	local account = luci.http.formvalue("account") or ""
	local password = luci.http.formvalue("password") or ""
	local captcha = luci.http.formvalue("captcha") or ""
	local result = { status = "error", message = "" }

	local function reply()
		luci.http.prepare_content("application/json")
		luci.http.write_json(result)
	end

	if account == "" or password == "" then
		result.message = "账号或密码为空"
		return reply()
	end

	-- 保存账号密码，守护进程与登录脚本都从 uci 读取
	uci:set("xlnetacc", "general", "account", account)
	uci:set("xlnetacc", "general", "password", password)
	uci:commit("xlnetacc")
	uci:unload("xlnetacc")

	-- 清掉上一次的验证码图片
	nixio.fs.unlink("/tmp/xlnetacc_captcha.png")
	nixio.fs.unlink("/tmp/xlnetacc_captcha.hdr")

	if captcha == "" then
		nixio.fs.unlink("/tmp/xlnetacc_captcha.key")
	else
		if not captcha:match("^[%w]+$") then
			result.message = "验证码格式不正确"
			return reply()
		end
		local key = nixio.fs.readfile("/tmp/xlnetacc_captcha.key")
		if not key or key == "" then
			result.message = "验证码已失效，请重新登录"
			return reply()
		end
		key = key:gsub("%s+$", "")
		nixio.fs.writefile("/tmp/xlnetacc_captcha.key", key .. "\n" .. captcha .. "\n")
	end

	local out = util.exec("/usr/bin/xlnetacc.sh --login 2>/dev/null") or ""
	if out:find('"status":"ok"', 1, true) then
		result.status = "ok"
		-- 登录成功：自动启用并重启服务，守护进程会复用刚建立的会话继续提速
		local uci2 = require "luci.model.uci".cursor()
		uci2:set("xlnetacc", "general", "enabled", "1")
		uci2:commit("xlnetacc")
		uci2:unload("xlnetacc")
		luci.sys.call("/etc/init.d/xlnetacc restart >/dev/null 2>&1")
	elseif out:find('"status":"captcha"', 1, true) then
		result.status = "captcha"
	else
		local code = out:match('"code":"([^"]*)"')
		result.message = code and ("错误代码 " .. code) or "登录失败"
	end

	return reply()
end

-- 主动注销：停止守护进程，通知迅雷注销并撤销运营商提速
function action_logout()
	local util = require "luci.util"
	luci.sys.call("/etc/init.d/xlnetacc stop >/dev/null 2>&1")
	util.exec("/usr/bin/xlnetacc.sh --logout 2>/dev/null")
	local uci = require "luci.model.uci".cursor()
	uci:set("xlnetacc", "general", "enabled", "0")
	uci:commit("xlnetacc")
	uci:unload("xlnetacc")
	luci.http.prepare_content("application/json")
	luci.http.write_json({ status = "ok" })
end

function action_log()
	local uci = require "luci.model.uci".cursor()
	local util = require "luci.util"
	local log_data = { }

	log_data.syslog = util.trim(util.exec("logread | grep xlnetacc"))
	if uci:get("xlnetacc", "general", "logging") ~= "0" then
		log_data.client = nixio.fs.readfile("/var/log/xlnetacc.log") or ""
	end
	uci:unload("xlnetacc")

	luci.http.prepare_content("application/json")
	luci.http.write_json(log_data)
end
