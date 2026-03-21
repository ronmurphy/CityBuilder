extends Node

var map_size: int = 75
var map_seed: int = 0
var starting_cash: int = 3000
var save_slot: String = "city"   # "town" | "city" | "metropolis"
var pending_load: bool = false   # true when startup dialog chose Load
var current_day: int = 0
var current_week: int = 0


func save_path() -> String:
	return "user://" + save_slot + ".res"
