extends RefCounted
class_name SaveService

## File-system boundary for GameState persistence.
##
## This service does not know anything about gameplay fields or save schema.
## GameState owns serialization and validation; SaveService only makes the
## resulting ConfigFile durable and provides a recoverable read path.
##
## Encryption: saves are written with a 32-byte AES key and read back with the
## same key. This is obfuscation against casual save editing, not a security
## boundary: the key ships inside the client, so a determined modder can still
## extract it. It exists so a text editor, `adb pull`, or a save-editor does not
## get a readable `diamonds = 999999`, and so a hand edit cannot silently corrupt
## progression. Saves written before encryption remain readable exactly once and
## are rewritten in the encrypted format by GameState.load_game().

const TEMP_SUFFIX: String = ".tmp"
const BACKUP_SUFFIX: String = ".bak"
const CORRUPT_SUFFIX: String = ".corrupt.cfg"

## Godot's encrypted-file container magic ("GDEC", little-endian). Detection is
## header-based, so a plaintext legacy save is never fed to the decryptor (which
## would emit an engine error before falling back).
const ENCRYPTED_MAGIC: String = "GDEC"
## Godot rejects any other key size; the container is always AES-256.
const KEY_BYTES: int = 32
## Build-level key, generated once. It is deliberately not derived from device
## state: a save stays portable across installs, and the .bak recovery path can
## always decrypt the file it copied. Treat as obfuscation, not secrecy.
const SAVE_KEY_HEX: String = "a5f68d2e8e0bcb52b58be2db44653be4ce8f277c9f1df25822cc6be31aaa415e"

var _key_cache := PackedByteArray()

## True when `path` is already an encrypted container. A missing or short file
## is not encrypted, so callers can branch to the legacy plaintext reader.
func is_encrypted(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var magic := file.get_buffer(ENCRYPTED_MAGIC.length()).get_string_from_ascii()
	file.close()
	return magic == ENCRYPTED_MAGIC

func backup_path(path: String) -> String:
	return path + BACKUP_SUFFIX

func corrupt_path(path: String) -> String:
	return path + CORRUPT_SUFFIX

func has_recoverable_save(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(backup_path(path))

func write_config(config: ConfigFile, path: String) -> bool:
	if config == null or path.strip_edges().is_empty():
		return false

	var temp := path + TEMP_SUFFIX
	_remove_file(temp)
	var save_error := config.save_encrypted(temp, _key())
	if save_error != OK:
		_remove_file(temp)
		return false

	# A successful save is not enough protection against a partial write or
	# malformed serialization. Decrypt and re-parse the temporary file before it
	# can replace the last known-good save.
	var verification := ConfigFile.new()
	if verification.load_encrypted(temp, _key()) != OK:
		_remove_file(temp)
		return false

	if FileAccess.file_exists(path):
		var backup_error := DirAccess.copy_absolute(
			_globalize(path), _globalize(backup_path(path)))
		if backup_error != OK:
			_remove_file(temp)
			return false

	# Rename within the same directory so the final path is never exposed to a
	# half-written ConfigFile. The existing primary remains recoverable as .bak.
	var rename_error := DirAccess.rename_absolute(
		_globalize(temp), _globalize(path))
	if rename_error != OK:
		_remove_file(temp)
		return false

	var final_verification := ConfigFile.new()
	return final_verification.load_encrypted(path, _key()) == OK

func load_config(path: String, corrupt_override: String = "",
		required_keys: Array[String] = [],
		required_sections: Array[String] = []) -> Dictionary:
	var primary := ConfigFile.new()
	if _load_and_validate(primary, path, required_keys, required_sections):
		return {"config": primary, "source": path, "recovered": false,
			"legacy_plaintext": not is_encrypted(path)}

	# Preserve the unreadable primary once for support/forensics. Do not overwrite
	# the first copy during repeated launch attempts.
	var corrupt := corrupt_override if not corrupt_override.is_empty() else corrupt_path(path)
	if FileAccess.file_exists(path) and not FileAccess.file_exists(corrupt):
		DirAccess.copy_absolute(_globalize(path), _globalize(corrupt))

	var backup := backup_path(path)
	var backup_config := ConfigFile.new()
	if FileAccess.file_exists(backup) \
			and _load_and_validate(backup_config, backup, required_keys, required_sections):
		return {"config": backup_config, "source": backup, "recovered": true,
			"legacy_plaintext": not is_encrypted(backup)}

	return {"config": null, "source": "", "recovered": false,
		"legacy_plaintext": false}

func delete_files(path: String, corrupt_override: String = "") -> void:
	_remove_file(path)
	_remove_file(path + TEMP_SUFFIX)
	_remove_file(backup_path(path))
	_remove_file(corrupt_override if not corrupt_override.is_empty() else corrupt_path(path))

func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(_globalize(path))

func _load_and_validate(config: ConfigFile, path: String,
		required_keys: Array[String], required_sections: Array[String]) -> bool:
	var load_error := config.load_encrypted(path, _key()) if is_encrypted(path) \
		else config.load(path)
	if load_error != OK:
		return false
	for required_section in required_sections:
		if not config.has_section(required_section):
			return false
	for required_key in required_keys:
		var separator := required_key.find(".")
		if separator <= 0:
			continue
		var section := required_key.substr(0, separator)
		var key := required_key.substr(separator + 1)
		if not config.has_section_key(section, key):
			return false
	return true

func _key() -> PackedByteArray:
	if _key_cache.size() != KEY_BYTES:
		_key_cache = SAVE_KEY_HEX.hex_decode()
	return _key_cache

func _globalize(path: String) -> String:
	return ProjectSettings.globalize_path(path)
