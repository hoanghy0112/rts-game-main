#!/usr/bin/env bash
set -uo pipefail

GODOT_BIN="${GODOT_BIN:-/home/hy/Downloads/Godot_v4.6.3-stable_linux.x86_64}"
SCENE_PATH="${SCENE_PATH:-res://maps/midlands/midlands.tscn}"
MODE="${MODE:-load}"
SAVE_COUNT="${SAVE_COUNT:-1}"
HOLD_FRAMES="${HOLD_FRAMES:-${HOLD_SECONDS:-600}}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
CYCLES="${CYCLES:-1}"
DIAG_ROOT="${DIAG_ROOT:-${TMPDIR:-/tmp}/rts-midlands-editor-diag}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_PROJECT="$REPO_ROOT/src"
WORK_ROOT="$DIAG_ROOT/$RUN_ID"
LOG_DIR="$WORK_ROOT/logs"

if [ ! -x "$GODOT_BIN" ]; then
	echo "Godot binary is not executable: $GODOT_BIN" >&2
	echo "Set GODOT_BIN=/path/to/Godot_v4.x before running this script." >&2
	exit 2
fi

if [ ! -f "$SOURCE_PROJECT/project.godot" ]; then
	echo "Cannot find project.godot under $SOURCE_PROJECT" >&2
	exit 2
fi

mkdir -p "$LOG_DIR"

if [ "$#" -gt 0 ]; then
	PROFILES=("$@")
else
	PROFILES=(
		"terrain_only"
		"terrain_no_forest_village"
		"terrain_forest_village"
		"full"
	)
fi

plugin_line_for_profile() {
	case "$1" in
		terrain_only)
			echo 'enabled=PackedStringArray("res://addons/terrain_3d/plugin.cfg")'
			;;
		terrain_no_forest_village)
			echo 'enabled=PackedStringArray("res://addons/terrain_3d/plugin.cfg", "res://addons/waterways/plugin.cfg")'
			;;
		terrain_forest_village)
			echo 'enabled=PackedStringArray("res://addons/terrain_3d/plugin.cfg", "res://addons/village_brush/plugin.cfg", "res://addons/forest_brush/plugin.cfg")'
			;;
		full)
			echo ""
			;;
		*)
			echo "Unknown profile: $1" >&2
			echo "Known profiles: terrain_only terrain_no_forest_village terrain_forest_village full" >&2
			return 1
			;;
	esac
}

prepare_project_copy() {
	local profile="$1"
	local cycle="$2"
	local project_copy="$WORK_ROOT/$profile/cycle-$cycle/project"

	rm -rf "$project_copy"
	mkdir -p "$project_copy"

	if command -v rsync >/dev/null 2>&1; then
		rsync -a --delete \
			--exclude '.godot' \
			--exclude '.import' \
			--exclude '.mono' \
			"$SOURCE_PROJECT"/ "$project_copy"/
	else
		cp -a "$SOURCE_PROJECT"/. "$project_copy"/
		rm -rf "$project_copy/.godot" "$project_copy/.import" "$project_copy/.mono"
	fi

	local plugin_line
	plugin_line="$(plugin_line_for_profile "$profile")" || return 1
	if [ -n "$plugin_line" ]; then
		sed -i "s#^enabled=PackedStringArray.*#$plugin_line#" "$project_copy/project.godot"
	fi
	if [ "$MODE" = "save" ]; then
		sed -i '/^enabled=PackedStringArray/s#)$#, "res://addons/midlands_save_probe/plugin.cfg")#' "$project_copy/project.godot"
	fi

	echo "$project_copy"
}

run_editor_load() {
	local profile="$1"
	local cycle="$2"
	local project_copy="$3"
	local log_file="$LOG_DIR/${profile}_cycle-${cycle}.log"
	local summary_file="$LOG_DIR/${profile}_cycle-${cycle}.summary"
	local editor_home="$WORK_ROOT/editor-home"
	local editor_config="$WORK_ROOT/editor-config"
	local editor_cache="$WORK_ROOT/editor-cache"
	local editor_data="$WORK_ROOT/editor-data"
	local status

	mkdir -p "$editor_home" "$editor_config" "$editor_cache" "$editor_data"

	echo "[$profile cycle $cycle] Project copy: $project_copy"
	echo "[$profile cycle $cycle] Log: $log_file"

	local godot_args=(
		"$GODOT_BIN"
		--path "$project_copy"
		--headless
		--verbose
	)
	if [ "$MODE" = "save" ]; then
		godot_args+=(
			--editor
			--scene "$SCENE_PATH"
			--quit-after "$HOLD_FRAMES"
			-- "--scene-path=$SCENE_PATH"
			"--save-count=$SAVE_COUNT"
		)
	else
		godot_args+=(
			--editor
			--scene "$SCENE_PATH"
			--quit-after "$HOLD_FRAMES"
		)
	fi

	if command -v timeout >/dev/null 2>&1; then
		HOME="$editor_home" \
		XDG_CONFIG_HOME="$editor_config" \
		XDG_CACHE_HOME="$editor_cache" \
		XDG_DATA_HOME="$editor_data" \
			timeout --kill-after=10s "${TIMEOUT_SECONDS}s" \
			"${godot_args[@]}" \
			>"$log_file" 2>&1
		status=$?
	else
		HOME="$editor_home" \
		XDG_CONFIG_HOME="$editor_config" \
		XDG_CACHE_HOME="$editor_cache" \
		XDG_DATA_HOME="$editor_data" \
			"${godot_args[@]}" \
			>"$log_file" 2>&1
		status=$?
	fi

	{
		echo "profile=$profile"
		echo "cycle=$cycle"
		echo "status=$status"
		echo "project_copy=$project_copy"
		echo "log_file=$log_file"
		if [ "$status" -eq 124 ]; then
			echo "result=timeout"
		elif [ "$status" -eq 0 ]; then
			echo "result=ok"
		else
			echo "result=failed"
		fi
	} >"$summary_file"

	return "$status"
}

overall_status=0
echo "Diagnostics root: $WORK_ROOT"
echo "Scene: $SCENE_PATH"
echo "Mode: $MODE"
if [ "$MODE" = "save" ]; then
	echo "Saves per editor instance: $SAVE_COUNT"
fi
echo "Cycles per profile: $CYCLES"
echo "Hold frames per editor load: $HOLD_FRAMES"

for profile in "${PROFILES[@]}"; do
	cycle=1
	while [ "$cycle" -le "$CYCLES" ]; do
		project_copy="$(prepare_project_copy "$profile" "$cycle")" || exit 2
		if ! run_editor_load "$profile" "$cycle" "$project_copy"; then
			overall_status=1
		fi
		cycle=$((cycle + 1))
	done
done

echo "Diagnostics complete. Logs: $LOG_DIR"
exit "$overall_status"
