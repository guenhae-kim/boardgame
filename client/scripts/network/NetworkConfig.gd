class_name NetworkConfig
extends RefCounted

# Editor/native clients use the deployed authority by default so F5 works
# without running Node separately. Local integration tests can override this
# with BOARDGAME_SERVER_URL=ws://127.0.0.1:8080/ws.
const PUBLIC_SERVER_URL := "wss://godot-boardgame-prototype.onrender.com/ws"

static func server_url() -> String:
	if not OS.has_feature("web"):
		var override_url := OS.get_environment("BOARDGAME_SERVER_URL").strip_edges()
		return override_url if not override_url.is_empty() else PUBLIC_SERVER_URL

	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	if window == null:
		return PUBLIC_SERVER_URL
	var location: JavaScriptObject = window.location
	var scheme := "wss" if str(location.protocol) == "https:" else "ws"
	return "%s://%s/ws" % [scheme, str(location.host)]
