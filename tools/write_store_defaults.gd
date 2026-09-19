extends SceneTree

## Writes the shipped store defaults resource that an exported Android build
## reads (`res://store_defaults.tres`, gitignored). Values come from the same
## environment variables the editor path uses, so there is one vocabulary:
##
##   EMBERVALE_REVENUECAT_PUBLIC_KEY=test_XXXXXXXX \
##   godot --headless --path . --script tools/write_store_defaults.gd
##
## Optional: EMBERVALE_REVENUECAT_PROJECT_ID, EMBERVALE_STORE_FUNNEL_URL,
## EMBERVALE_STORE_BACKEND_URL. A secret (`sk_...`) is refused, and `--clear`
## removes the file for a build that must not carry test keys.
##
## The public SDK key is SEALED by default (`--no-seal` writes it plain):
## obfuscation only, so a literal copy-paste of the resource does not hand out a
## working key. The passphrase ships in the client, so this is not secrecy.
## `--from-resource user://old.tres` recovers values from a previous defaults
## resource (used when rotating a key out of an existing build) instead of the
## environment.
##
## The file is a RESOURCE on purpose: the exporter only packs resources, so a
## plain `.cfg` would silently not exist inside the APK.

const SECURITY := preload("res://scripts/systems/store_security.gd")
const DEFAULTS := preload("res://scripts/systems/store_defaults.gd")

const PATH := "res://store_defaults.tres"

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--clear"):
		_clear()
		return
	var seal_key := not args.has("--no-seal")
	var source := _source_from_args(args)
	var key := OS.get_environment("EMBERVALE_REVENUECAT_PUBLIC_KEY").strip_edges()
	var project_id := OS.get_environment("EMBERVALE_REVENUECAT_PROJECT_ID").strip_edges()
	var funnel_url := OS.get_environment("EMBERVALE_STORE_FUNNEL_URL").strip_edges()
	var backend_url := OS.get_environment("EMBERVALE_STORE_BACKEND_URL").strip_edges()
	if source != null:
		# A previous defaults resource is the fallback for any field the
		# environment does not override (used when recovering a shipped key).
		if key.is_empty():
			key = source.resolved_native_api_key()
		if project_id.is_empty():
			project_id = source.project_id.strip_edges()
		if funnel_url.is_empty():
			funnel_url = source.funnel_url.strip_edges()
		if backend_url.is_empty():
			backend_url = source.backend_url.strip_edges()

	_check_inputs(key, project_id, funnel_url, backend_url)
	if not _failures.is_empty():
		_report()
		return

	var defaults := DEFAULTS.new()
	if not key.is_empty() and seal_key:
		defaults.native_api_key_sealed = SECURITY.seal(key)
		if defaults.native_api_key_sealed.is_empty():
			_failures.append("Could not seal the public SDK key.")
			_report()
			return
	else:
		defaults.native_api_key = key
	defaults.project_id = project_id
	defaults.funnel_url = funnel_url
	defaults.backend_url = backend_url
	var error := ResourceSaver.save(defaults, PATH)
	if error != OK:
		_failures.append("Could not write %s (error %d)." % [PATH, error])
		_report()
		return
	print("WROTE %s" % PATH)
	var key_state := "absent"
	if not key.is_empty():
		key_state = "sealed" if seal_key else "plaintext"
	print("  native_api_key : %s" % key_state)
	print("  project_id     : %s" % ("set" if not project_id.is_empty() else "absent"))
	print("  funnel_url     : %s" % ("set" if not funnel_url.is_empty() else "absent"))
	print("  backend_url    : %s" % ("set" if not backend_url.is_empty() else "absent"))
	print("  identity       : device-minted (never shipped)")
	print("STORE DEFAULTS WRITTEN")
	quit(0)

## `--from-resource user://recovered.tres` reads values from an existing
## StoreDefaults resource; the environment still wins per field.
func _source_from_args(args: PackedStringArray) -> StoreDefaults:
	var index := args.find("--from-resource")
	if index < 0 or index + 1 >= args.size():
		return null
	var path := args[index + 1].strip_edges()
	if not ResourceLoader.exists(path):
		_failures.append("--from-resource path does not exist: %s" % path)
		return null
	var loaded := ResourceLoader.load(path)
	if loaded is not StoreDefaults:
		_failures.append("--from-resource is not a StoreDefaults resource: %s" % path)
		return null
	return loaded as StoreDefaults

func _clear() -> void:
	if FileAccess.file_exists(PATH) and DirAccess.remove_absolute(PATH) != OK:
		_failures.append("Could not remove %s." % PATH)
		_report()
		return
	print("STORE DEFAULTS CLEARED (%s is absent)" % PATH)
	quit(0)

func _check_inputs(key: String, project_id: String, funnel_url: String,
		backend_url: String) -> void:
	if key.is_empty() and funnel_url.is_empty():
		_failures.append("Nothing to ship: set EMBERVALE_REVENUECAT_PUBLIC_KEY "
			+ "(SDK path) and/or EMBERVALE_STORE_FUNNEL_URL (web path).")
	if not key.is_empty():
		var key_problem := SECURITY.validate_public_sdk_key(key)
		if not key_problem.is_empty():
			_failures.append("EMBERVALE_REVENUECAT_PUBLIC_KEY is refused (%s); "
				% key_problem + "a secret key must never ship.")
	if not project_id.is_empty():
		var project_problem := SECURITY.validate_project_id(project_id)
		if not project_problem.is_empty():
			_failures.append("EMBERVALE_REVENUECAT_PROJECT_ID is refused (%s)." % project_problem)
	if not funnel_url.is_empty():
		var funnel_problem := SECURITY.validate_url(funnel_url,
			SECURITY.ALLOWED_FUNNEL_HOSTS)
		if not funnel_problem.is_empty():
			_failures.append("EMBERVALE_STORE_FUNNEL_URL is refused (%s)." % funnel_problem)
	if not backend_url.is_empty():
		var backend_problem := SECURITY.validate_backend_url(backend_url)
		if not backend_problem.is_empty():
			_failures.append("EMBERVALE_STORE_BACKEND_URL is refused (%s)." % backend_problem)

func _report() -> void:
	for failure in _failures:
		print("FAIL: %s" % failure)
	print("STORE DEFAULTS NOT WRITTEN (%d)" % _failures.size())
	quit(1)
