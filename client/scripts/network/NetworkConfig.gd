class_name NetworkConfig
extends RefCounted

# Native/editor fallback. The Web build automatically uses its page's host.
const LOCAL_SERVER_URL := "ws://127.0.0.1:8080/ws"

static func server_url() -> String:
	if not OS.has_feature("web"):
		return LOCAL_SERVER_URL

	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	if window == null:
		return LOCAL_SERVER_URL
	var location: JavaScriptObject = window.location
	var scheme := "wss" if str(location.protocol) == "https:" else "ws"
	return "%s://%s/ws" % [scheme, str(location.host)]

