extends Node

signal initialized(success: bool, message: String)

const APP_ID := 480

var is_initialized := false


func _ready() -> void:
	OS.set_environment("SteamAppId", str(APP_ID))
	OS.set_environment("SteamGameId", str(APP_ID))
	var initialize_response: Dictionary = Steam.steamInitEx(APP_ID, true)
	print("Steam initialization: %s" % initialize_response)
	is_initialized = initialize_response.get("status", 1) == Steam.STEAM_API_INIT_RESULT_OK
	if not is_initialized:
		var message: String = str(initialize_response.get("verbal", "Unknown Steam initialization error"))
		push_warning("Steam failed to initialize: %s" % message)
		initialized.emit(false, message)
		return
	initialized.emit(true, "Steam initialized")


func _process(_delta: float) -> void:
	if is_initialized:
		Steam.run_callbacks()
