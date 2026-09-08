extends RefCounted
class_name BackendApiClient

## Transport-neutral authenticated API adapter. UI and GameState depend on this
## contract; provider SDKs and secrets remain outside the Godot client.

var base_url: String
var access_token: String = ""

func _init(endpoint: String = "") -> void:
	base_url = endpoint.strip_edges().trim_suffix("/")

func configure_token(token: String) -> void:
	access_token = token.strip_edges()

func can_request() -> bool:
	return base_url.begins_with("https://") and not access_token.is_empty()

func authorization_headers() -> PackedStringArray:
	if access_token.is_empty():
		return PackedStringArray(["Content-Type: application/json"])
	return PackedStringArray(["Content-Type: application/json", "Authorization: Bearer %s" % access_token])
