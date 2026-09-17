extends RefCounted
class_name AccountSession

var account_id: String = ""
var access_token: String = ""

func is_authenticated() -> bool:
	return not account_id.is_empty() and not access_token.is_empty()

## A backend-issued token can precede a full login, so it is settable alone.
func configure_token(token: String) -> void:
	access_token = token.strip_edges()

func apply_account_response(response: Dictionary) -> bool:
	account_id = str(response.get("account_id", "")).strip_edges()
	access_token = str(response.get("access_token", "")).strip_edges()
	return is_authenticated()

func clear() -> void:
	account_id = ""
	access_token = ""
