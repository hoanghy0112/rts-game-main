@tool
extends Node
class_name GameTimeSystem

signal time_changed(snapshot: Dictionary)
signal day_changed(snapshot: Dictionary, days_elapsed: int)

const MINUTES_PER_HOUR := 60
const HOURS_PER_DAY := 24
const MINUTES_PER_DAY := MINUTES_PER_HOUR * HOURS_PER_DAY
@export var auto_advance := true
@export_range(0.0, 1440.0, 0.1, "or_greater") var game_minutes_per_real_second := 12.0

@export_range(1, 9999, 1, "or_greater") var year := 1:
	set(value):
		year = maxi(value, 1)
		_emit_time_changed_if_ready()

@export_range(1, 12, 1) var calendar_month := 1:
	set(value):
		calendar_month = clampi(value, 1, months_per_year)
		day_of_month = clampi(day_of_month, 1, days_per_month)
		_emit_time_changed_if_ready()

@export_range(1, 31, 1) var day_of_month := 1:
	set(value):
		day_of_month = clampi(value, 1, days_per_month)
		_emit_time_changed_if_ready()

@export_range(0, 23, 1) var hour := 6:
	set(value):
		hour = clampi(value, 0, HOURS_PER_DAY - 1)
		_emit_time_changed_if_ready()

@export_range(0, 59, 1) var minute := 0:
	set(value):
		minute = clampi(value, 0, MINUTES_PER_HOUR - 1)
		_emit_time_changed_if_ready()

@export_range(1, 31, 1, "or_greater") var days_per_month := 30:
	set(value):
		days_per_month = maxi(value, 1)
		day_of_month = clampi(day_of_month, 1, days_per_month)
		_emit_time_changed_if_ready()

@export_range(1, 12, 1, "or_greater") var months_per_year := 12:
	set(value):
		months_per_year = maxi(value, 1)
		calendar_month = clampi(calendar_month, 1, months_per_year)
		_emit_time_changed_if_ready()

@export var month_names := PackedStringArray([
	"Month 01",
	"Month 02",
	"Month 03",
	"Month 04",
	"Month 05",
	"Month 06",
	"Month 07",
	"Month 08",
	"Month 09",
	"Month 10",
	"Month 11",
	"Month 12",
])

var _ready_to_emit := false
var _suppress_emit := false
var _minute_fraction := 0.0


func _ready() -> void:
	_ready_to_emit = true
	_emit_time_changed_if_ready()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not auto_advance or game_minutes_per_real_second <= 0.0:
		return

	advance_minutes(delta * game_minutes_per_real_second)


func set_date(new_year: int, new_month: int, new_day: int) -> void:
	_suppress_emit = true
	year = new_year
	calendar_month = new_month
	day_of_month = new_day
	_suppress_emit = false
	_emit_time_changed_if_ready()


func set_time(new_hour: int, new_minute: int) -> void:
	_suppress_emit = true
	hour = new_hour
	minute = new_minute
	_suppress_emit = false
	_emit_time_changed_if_ready()


func advance_days(days: int) -> void:
	var day_count := maxi(days, 0)
	if day_count <= 0:
		return

	_suppress_emit = true
	_set_absolute_day_index(_get_absolute_day_index() + day_count)
	_suppress_emit = false
	_emit_time_changed_if_ready()
	day_changed.emit(get_current_snapshot(), day_count)


func advance_minutes(minutes_to_add: float) -> void:
	var safe_minutes := maxf(minutes_to_add, 0.0)
	if safe_minutes <= 0.0:
		return

	var whole_minutes := floori(_minute_fraction + safe_minutes)
	_minute_fraction = fmod(_minute_fraction + safe_minutes, 1.0)
	if whole_minutes <= 0:
		return

	var total_minutes := _get_time_of_day_minutes() + whole_minutes
	var elapsed_days := total_minutes / MINUTES_PER_DAY
	var remaining_minutes := total_minutes % MINUTES_PER_DAY

	_suppress_emit = true
	if elapsed_days > 0:
		_set_absolute_day_index(_get_absolute_day_index() + elapsed_days)
	hour = remaining_minutes / MINUTES_PER_HOUR
	minute = remaining_minutes % MINUTES_PER_HOUR
	_suppress_emit = false

	_emit_time_changed_if_ready()
	if elapsed_days > 0:
		day_changed.emit(get_current_snapshot(), elapsed_days)


func get_current_snapshot() -> Dictionary:
	var month_name := _get_month_name(calendar_month)
	var date_label := _format_date(year, calendar_month, day_of_month, month_name)
	var time_label := _format_time(hour, minute)
	return {
		"year": year,
		"calendar_month": calendar_month,
		"month": calendar_month,
		"month_name": month_name,
		"day_of_month": day_of_month,
		"day_of_year": _get_day_of_year(),
		"absolute_day": _get_absolute_day_index(),
		"hour": hour,
		"minute": minute,
		"time_of_day_minutes": _get_time_of_day_minutes(),
		"days_per_month": days_per_month,
		"months_per_year": months_per_year,
		"date_label": date_label,
		"time_label": time_label,
		"date_time_label": "%s  %s" % [date_label, time_label],
	}


func _set_absolute_day_index(absolute_day_index: int) -> void:
	var days_per_year := maxi(days_per_month * months_per_year, 1)
	var safe_day := maxi(absolute_day_index, 0)
	var year_index := safe_day / days_per_year
	var day_in_year := safe_day % days_per_year
	year = year_index + 1
	calendar_month = day_in_year / days_per_month + 1
	day_of_month = day_in_year % days_per_month + 1


func _get_absolute_day_index() -> int:
	var days_per_year := maxi(days_per_month * months_per_year, 1)
	return (year - 1) * days_per_year + (calendar_month - 1) * days_per_month + (day_of_month - 1)


func _get_day_of_year() -> int:
	return (calendar_month - 1) * days_per_month + day_of_month


func _get_time_of_day_minutes() -> int:
	return hour * MINUTES_PER_HOUR + minute


func _get_month_name(month: int) -> String:
	var index := month - 1
	if index >= 0 and index < month_names.size():
		return month_names[index]
	return "Month %02d" % [month]


func _format_date(date_year: int, month: int, day: int, month_name: String) -> String:
	return "Year %d, %s, Day %02d" % [date_year, month_name, day]


func _format_time(time_hour: int, time_minute: int) -> String:
	return "%02d:%02d" % [time_hour, time_minute]


func _emit_time_changed_if_ready() -> void:
	if _suppress_emit or not _ready_to_emit:
		return
	time_changed.emit(get_current_snapshot())
