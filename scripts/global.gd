extends Node

var map_size: int = 75
var map_seed: int = 0
var starting_cash: int = 3000
var save_slot: String = "city"   # "town" | "city" | "metropolis"
var pending_load: bool = false   # true when startup dialog chose Load
var current_day: int = 0
var current_week: int = 0
var day_progress: float = 0.0       # 0.0 (dawn) → 1.0 (end of day), updated every frame
var day_cycle_enabled: bool = true  # toggle with F3; persisted in save


func save_path() -> String:
	return "user://" + save_slot + ".res"


# ── Web / localStorage save system ───────────────────────────────────────────
# On web builds, Godot's user:// filesystem is not persistent across page
# reloads.  These helpers serialise DataMap to JSON → base64 → localStorage.

func web_has_save(slot: String) -> bool:
	var result = JavaScriptBridge.eval('localStorage.getItem("citybuilder_' + slot + '") !== null', true)
	return result == true


func web_save(map: DataMap) -> void:
	var structs := []
	for s: DataStructure in map.structures:
		structs.append({
			"px": s.position.x, "py": s.position.y,
			"orientation": s.orientation,
			"structure": s.structure,
			"layer": s.layer,
			"placed_week": s.placed_week,
			"job_slots": s.job_slots,
			"patience": s.patience,
		})
	var data := {
		"cash": map.cash, "map_size": map.map_size,
		"map_seed": map.map_seed, "current_day": map.current_day,
		"tax_rate": map.tax_rate, "payday_count": map.payday_count,
		"day_cycle_enabled": map.day_cycle_enabled,
		"structures": structs,
	}
	var b64 := Marshalls.utf8_to_base64(JSON.stringify(data))
	JavaScriptBridge.eval('localStorage.setItem("citybuilder_' + save_slot + '", "' + b64 + '")')


func web_load() -> DataMap:
	var b64 = JavaScriptBridge.eval('localStorage.getItem("citybuilder_' + save_slot + '")', true)
	if b64 == null:
		return null
	var parsed = JSON.parse_string(Marshalls.base64_to_utf8(str(b64)))
	if parsed == null:
		return null
	var map := DataMap.new()
	map.cash        = int(parsed["cash"])
	map.map_size    = int(parsed["map_size"])
	map.map_seed    = int(parsed["map_seed"])
	map.current_day   = int(parsed["current_day"])
	map.tax_rate      = float(parsed.get("tax_rate", 0.08))
	map.payday_count      = int(parsed.get("payday_count", 0))
	map.day_cycle_enabled = bool(parsed.get("day_cycle_enabled", true))
	for sd in parsed["structures"]:
		var ds := DataStructure.new()
		ds.position    = Vector2i(int(sd["px"]), int(sd["py"]))
		ds.orientation = int(sd["orientation"])
		ds.structure   = int(sd["structure"])
		ds.layer       = int(sd["layer"])
		ds.placed_week = int(sd["placed_week"])
		ds.job_slots   = int(sd.get("job_slots", 0))
		ds.patience    = int(sd.get("patience", 10))
		map.structures.append(ds)
	return map
