local m, s, o
local uci = luci.model.uci.cursor()

m = Map("xlnetacc", "%s - %s" %{translate("XLNetAcc"), translate("Settings")}, translate("XLNetAcc is a Thunder joint broadband operators launched a commitment to help users solve the low broadband, slow Internet access, poor Internet experience of professional-grade broadband upgrade software."))
m:append(Template("xlnetacc/status"))

-- 保存并应用后重载服务：enabled=0 时停止守护进程，enabled=1 时重启
m.on_after_commit = function(self)
	luci.sys.call("/etc/init.d/xlnetacc reload >/dev/null 2>&1")
end

s = m:section(NamedSection, "general", "general", translate("General Settings"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("Enabled"))
o.rmempty = false

o = s:option(Flag, "down_acc", translate("Enable DownLink Upgrade"))

o = s:option(Flag, "up_acc", translate("Enable UpLink Upgrade"))

o = s:option(Flag, "logging", translate("Enable Logging"))
o.default = "1"

o = s:option(Flag, "verbose", translate("Enable verbose logging"))
o:depends("logging", "1")

o = s:option(ListValue, "network", translate("Upgrade interface"))
uci:foreach("network", "interface", function(section)
	if section[".name"] ~= "loopback" then
		o:value(section[".name"])
	end
end)

o = s:option(Value, "keepalive", translate("Keepalive interval"), "5-60 " .. translate("minutes"))
for _, v in ipairs({5, 10, 20, 30, 60}) do
	o:value(v, v .. " " .. translate("minutes"))
end
o.datatype = "range(5, 60)"
o.default = 10

o = s:option(Value, "relogin", translate("Account relogin"), "1-48 " .. translate("hours"))
o:value(0, translate("Not enabled"))
for _, v in ipairs({3, 12, 18, 24, 30}) do
	o:value(v, v .. " " .. translate("hours"))
end
o.datatype = "max(48)"
o.default = 0

o = s:option(ListValue, "timeout", "请求超时")
for _, v in ipairs({5, 10, 15, 20, 30, 60, 120}) do
	o:value(v, v .. " 秒")
end
o.default = 20
o.rmempty = false

o = s:option(Value, "account", translate("XLNetAcc account"))

o = s:option(Value, "password", translate("XLNetAcc password"))
o.password = true

-- 手动登录：验证码仅在点击登录且服务器要求时显示
o = s:option(DummyValue, "_login", "账号操作")
o.rawhtml = true
o.value = function(self, section)
	local login_url = luci.dispatcher.build_url("admin", "services", "xlnetacc", "login")
	local logout_url = luci.dispatcher.build_url("admin", "services", "xlnetacc", "logout")
	local captcha_url = luci.dispatcher.build_url("admin", "services", "xlnetacc", "captcha")
	return string.format([==[
	<div id="xlnetacc_captcha_box" style="display:none;">
		<img id="xlnetacc_captcha_img" src="" alt="captcha" title="点击刷新验证码"
			style="display:block;margin:0 0 8px 0;max-width:200px;cursor:pointer;" />
		<input type="text" id="xlnetacc_captcha_code" class="cbi-input-text" maxlength="8"
			autocomplete="off" placeholder="请输入验证码" style="width:200px;" />
		<div class="cbi-value-description">看不清？点击图片刷新</div>
	</div>
	<div>
		<button type="button" class="cbi-button cbi-button-apply" id="xlnetacc_login_btn">登录</button>
		<button type="button" class="cbi-button cbi-button-reset" id="xlnetacc_logout_btn">注销</button>
		<span id="xlnetacc_login_msg" style="margin-left:10px;"></span>
	</div>
<script type="text/javascript">//<![CDATA[
(function() {
	var loginUrl = '%s';
	var captchaUrl = '%s';
	var logoutUrl = '%s';
	var btn = document.getElementById('xlnetacc_login_btn');
	var logoutBtn = document.getElementById('xlnetacc_logout_btn');
	var box = document.getElementById('xlnetacc_captcha_box');
	var img = document.getElementById('xlnetacc_captcha_img');
	var code = document.getElementById('xlnetacc_captcha_code');
	var msg = document.getElementById('xlnetacc_login_msg');

	function field(id) {
		var el = document.getElementById('widget.' + id) || document.getElementById(id);
		if (el && el.tagName === 'DIV') {
			el = el.querySelector('input');
		}
		return el ? el.value : '';
	}
	function setMsg(text, color) {
		msg.innerHTML = text || '';
		msg.style.color = color || '';
	}
	function refreshCaptcha() {
		img.src = captchaUrl + '?t=' + (new Date().getTime());
	}
	function showCaptcha() {
		box.style.display = '';
		refreshCaptcha();
		code.value = '';
		code.focus();
	}
	function hideCaptcha() {
		box.style.display = 'none';
	}
	function doLogin() {
		var account = field('cbid.xlnetacc.general.account');
		var password = field('cbid.xlnetacc.general.password');
		if (!account || !password) {
			setMsg('请先填写账号和密码', 'red');
			return;
		}
		var captcha = (box.style.display === 'none') ? '' : code.value.replace(/\s+/g, '');
		btn.disabled = true;
		setMsg('正在登录，请稍候...', '');
		var xhr = new XMLHttpRequest();
		xhr.open('POST', loginUrl, true);
		xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
		xhr.onreadystatechange = function() {
			if (xhr.readyState !== 4) return;
			btn.disabled = false;
			var r = {};
			try { r = JSON.parse(xhr.responseText); } catch (e) {}
			if (r.status === 'ok') {
				hideCaptcha();
				setMsg('登录成功，已自动启用并开始提速', 'green');
				var en = document.querySelector('input[data-widget-id="widget.cbid.xlnetacc.general.enabled"]')
					|| document.querySelector('input[name="cbid.xlnetacc.general.enabled"]');
				if (en) en.checked = true;
			} else if (r.status === 'captcha') {
				showCaptcha();
				setMsg('需要验证码，请输入图片中的字符', '#e67e00');
			} else {
				var reason = r.message ? r.message : (r.code ? ('错误代码 ' + r.code) : '登录失败');
				setMsg('登录失败：' + reason, 'red');
			}
		};
		xhr.send('account=' + encodeURIComponent(account) +
			'&password=' + encodeURIComponent(password) +
			'&captcha=' + encodeURIComponent(captcha));
	}
	function doLogout() {
		if (!confirm('确定注销并停止提速吗？')) return;
		logoutBtn.disabled = true;
		setMsg('正在注销...', '');
		var xhr = new XMLHttpRequest();
		xhr.open('POST', logoutUrl, true);
		xhr.onreadystatechange = function() {
			if (xhr.readyState !== 4) return;
			logoutBtn.disabled = false;
			var r = {};
			try { r = JSON.parse(xhr.responseText); } catch (e) {}
			if (r.status === 'ok') {
				hideCaptcha();
				setMsg('已注销，服务已停止', 'green');
				var en = document.querySelector('input[data-widget-id="widget.cbid.xlnetacc.general.enabled"]')
					|| document.querySelector('input[name="cbid.xlnetacc.general.enabled"]');
				if (en) en.checked = false;
			} else {
				setMsg('注销失败', 'red');
			}
		};
		xhr.send('');
	}
	btn.onclick = doLogin;
	logoutBtn.onclick = doLogout;
	img.onclick = refreshCaptcha;
	code.onkeydown = function(e) {
		if (e.keyCode === 13) {
			e.preventDefault();
			doLogin();
		}
	};
})();
//]]></script>
]==], login_url, captcha_url, logout_url)
end

return m
