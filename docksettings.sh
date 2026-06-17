#!/bin/bash

## Changelog
## 17-06-2026 v1.20 Global Automation (Back to Working Basics)
## - FIXED: Reverted to the -o syntax that was manually confirmed to work
## - FIXED: Exclusion logic is now applied to the final list of files, which is robust and reliable
## - FIXED: No more complex find expressions that break on your system

## ==============================================================================
## BASIC VARIABLES
## ==============================================================================
ROOTDIR="/home/deck/Documents"
DOCK_DIR="$ROOTDIR/docksettings"
MAP_FILE="$DOCK_DIR/master_map.txt"
STATE_FILE="$DOCK_DIR/global_state"
DATE=$(date '+%d-%m-%Y %H:%M:%S')
DB="$ROOTDIR/docksettings_db.csv"
LOCKDIR="/tmp/docksettings"
TEMPFILE="/tmp/docksettings_steam_find.tmp"

## Profile Directories
IGPU_PROFILES="$DOCK_DIR/profiles/igpu"
EGPU_PROFILES="$DOCK_DIR/profiles/egpu"
BACKUP_DIR="$DOCK_DIR/backups"

## ==============================================================================
## THE ENGINE: DISCOVERY & MAPPING
## ==============================================================================

crawl_and_register() {
    > "$DOCK_DIR/global.log"
    echo "$DATE INFO: Starting Scan with Post-Filter Exclusions..." >> "$DOCK_DIR/global.log"

    # Define the 4 target zone patterns
    local zone_patterns=(
        "$HOME/.steam/steam/steamapps/compatdata/*/pfx/drive_c/users/steamuser/"
        #"/run/media/$USER/*/steamapps/common/"
        #"/mnt/*/steamapps/common/"
        #"$HOME/.steam/steam/steamapps/common/"
    )

    local found_files=()
    local scanned_count=0

    # 1. Crawl the System Zones (FILTERED)
    echo "$DATE INFO: Scanning Steam zones (Filtered)..." >> "$DOCK_DIR/global.log"

    # Clear temp file
    > "$TEMPFILE"

    for zone_pattern in "${zone_patterns[@]}"; do
        echo "$DATE DEBUG: Expanding pattern: $zone_pattern" >> "$DOCK_DIR/global.log"

        # Expand the glob pattern
        local expanded_paths=()
        while IFS= read -r -d '' path; do
            expanded_paths+=("$path")
        done < <(find "$(dirname "$zone_pattern")" -path "$zone_pattern" -type d 2>/dev/null || echo "$zone_pattern")

        # If no expansion happened, try direct glob
        if [ ${#expanded_paths[@]} -eq 0 ] || [ "${expanded_paths[0]}" = "$zone_pattern" ]; then
            expanded_paths=()
            local old_opts=$(set +o)
            set +f  # Enable globbing
            for expanded_path in $zone_pattern; do
                if [ -d "$expanded_path" ]; then
                    expanded_paths+=("$expanded_path")
                fi
            done
            eval "$old_opts"  # Restore original options
        fi

        echo "$DATE DEBUG: Pattern yielded ${#expanded_paths[@]} paths" >> "$DOCK_DIR/global.log"

        for expanded_path in "${expanded_paths[@]}"; do
            if [ -d "$expanded_path" ]; then
                echo "$DATE DEBUG: Filtered Scanning: $expanded_path" >> "$DOCK_DIR/global.log"

                # USE THE WORKING SYNTAX: The one the user manually confirmed
                find -L "$expanded_path" -type f -name "*.ini" -o -name "*.cfg" -o -name "*.json" -o -name "*.xml" 2>/dev/null >> "$TEMPFILE"
            fi
        done
    done

    # Read temp file into array and FILTER
    if [ -f "$TEMPFILE" ]; then
        while IFS= read -r file; do
            if [ -n "$file" ]; then
                local lower_file=$(echo "$file" | tr '[:upper:]' '[:lower:]')
                # FILTER: Exclude if path contains 'steamlinuxruntime' or 'proton'
                if [[ "$lower_file" != *"steamlinuxruntime"* ]] && [[ "$lower_file" != *"proton"* ]]; then
                    found_files+=("$file")
                    scanned_count=$((scanned_count + 1))
                    if [ $((scanned_count % 50)) -eq 0 ]; then
                        echo "$DATE DEBUG: Read file: $file" >> "$DOCK_DIR/global.log"
                    fi
                else
                    echo "$DATE INFO: Excluding file: $file" >> "$DOCK_DIR/global.log"
                fi
            fi
        done < "$TEMPFILE"
        rm -f "$TEMPFILE"
    fi

    echo "$DATE INFO: Steam Filtered Find complete. Total files found: $scanned_count" >> "$DOCK_DIR/global.log"

    # 2. Crawl the CSV (UNFILTERED)
    echo "$DATE INFO: Scanning CSV entries (Unfiltered)..." >> "$DOCK_DIR/global.log"
    local csv_files=0
    if [ -f "$DB" ]; then
        echo "$DATE DEBUG: CSV file exists, processing..." >> "$DOCK_DIR/global.log"
        while IFS= read -r entry || [[ -n "$entry" ]]; do
            entry=$(echo "$entry" | xargs)
            [ -z "$entry" ] && continue

            echo "$DATE DEBUG: Processing CSV entry: $entry" >> "$DOCK_DIR/global.log"

            if [ -d "$entry" ]; then
                echo "$DATE DEBUG: Entry is directory, scanning recursively (no extension filter)..." >> "$DOCK_DIR/global.log"
                local dir_count=0

                # UNFILTERED: Find ALL files
                while IFS= read -r file; do
                    if [ -n "$file" ]; then
                        found_files+=("$file")
                        csv_files=$((csv_files + 1))
                        dir_count=$((dir_count + 1))
                        echo "$DATE DEBUG: Found [CSV]: $file" >> "$DOCK_DIR/global.log"
                    fi
                done < <(find -L "$entry" -type f 2>/dev/null)

                echo "$DATE DEBUG: Directory $entry contributed $dir_count files" >> "$DOCK_DIR/global.log"
            elif [ -f "$entry" ]; then
                found_files+=("$entry")
                csv_files=$((csv_files + 1))
                echo "$DATE DEBUG: Found CSV file: $entry" >> "$DOCK_DIR/global.log"
            else
                echo "$DATE WARN: CSV entry not found: $entry" >> "$DOCK_DIR/global.log"
            fi
        done < "$DB"
        echo "$DATE INFO: CSV Unfiltered Find complete. Files from CSV: $csv_files" >> "$DOCK_DIR/global.log"
    else
        echo "$DATE WARN: CSV file not found: $DB" >> "$DOCK_DIR/global.log"
    fi

    echo "$DATE INFO: Total files to process: ${#found_files[@]}" >> "$DOCK_DIR/global.log"

    # 3. Register found files in the Master Map
    mkdir -p "$IGPU_PROFILES" "$EGPU_PROFILES" "$BACKUP_DIR"
    touch "$MAP_FILE"

    local registered_count=0
    for file_path in "${found_files[@]}"; do
        if ! grep -qF "$file_path" "$MAP_FILE"; then
            local id="ID_$(($(wc -l < "$MAP_FILE") + 1))"
            echo "$id | $file_path" >> "$MAP_FILE"

            local filename=$(basename "$file_path")
            cp -p "$file_path" "$BACKUP_DIR/${id}_${filename}" 2>/dev/null
            cp -p "$file_path" "$IGPU_PROFILES/$id" 2>/dev/null
            cp -p "$file_path" "$EGPU_PROFILES/$id" 2>/dev/null

            echo "$DATE REGISTERED: $file_path as $id" >> "$DOCK_DIR/global.log"
            registered_count=$((registered_count + 1))
        fi
    done

    echo "$DATE INFO: Registration complete. New files registered: $registered_count" >> "$DOCK_DIR/global.log"
    echo "$DATE INFO: Total entries in map: $(wc -l < "$MAP_FILE" 2>/dev/null || echo 0)" >> "$DOCK_DIR/global.log"
}

perform_swap() {
    local target_state="$1"
    local current_state=$(cat "$STATE_FILE" 2>/dev/null || echo "unknown")

    local save_to_dir=""
    local load_from_dir=""

    # Determine the direction of the swap
    if [ "$target_state" = "egpu" ]; then
        load_from_dir="$EGPU_PROFILES"
        if [ "$current_state" = "igpu" ]; then
            save_to_dir="$IGPU_PROFILES"
        fi
    else # target_state is "igpu"
        load_from_dir="$IGPU_PROFILES"
        if [ "$current_state" = "egpu" ]; then
            save_to_dir="$EGPU_PROFILES"
        fi
    fi

    echo "$DATE SWAP: Current: $current_state -> Target: $target_state" >> "$DOCK_DIR/global.log"

    # Iterate through all registered files
    while IFS=" | " read -r id file_path; do
        id=$(echo "$id" | xargs)
        file_path=$(echo "$file_path" | xargs)

        # 1. BACKUP
        if [ -n "$save_to_dir" ] && [ -f "$file_path" ]; then
            if [ "$DRYRUN" = "1" ]; then
                echo "$DATE DRY RUN: Backing up $file_path" >> "$DOCK_DIR/global.log"
            else
                cp -p "$file_path" "$save_to_dir/$id"
            fi
        fi

        # 2. APPLY
        if [ -f "$load_from_dir/$id" ]; then
            if [ "$DRYRUN" = "1" ]; then
                echo "$DATE DRY RUN: Applying $load_from_dir/$id" >> "$DOCK_DIR/global.log"
            else
                cp -p "$load_from_dir/$id" "$file_path"
            fi
        fi
    done < "$MAP_FILE"

    # 3. Update state
    (
        echo "$target_state" > "$STATE_FILE"
        echo "$DATE STATE SAVED: Now in $target_state mode" >> "$DOCK_DIR/global.log"
    )
}

## ==============================================================================
## HELP & OPTIONS
## ==============================================================================

help() {
    echo "ROG Ally X Absolute GPU Automation (Back to Working Basics)"
    echo "-----------------------------------------------------------"
    echo "Usage: $0 [options]"
    echo "-u          Global Update: Sync map and swap all"
    echo "-g [state]  REQUIRED: Target GPU state (igpu/egpu)"
    echo "-d          Dry run: Log changes without writing to files"
}

while getopts "hug:d" option; do
    case $option in
        h) help; exit;;
        u) UDEV_MODE=1;;
        g) GPU_OVERRIDE=$OPTARG;;
        d) DRYRUN=1;;
        \?) echo "$DATE Invalid options" >> "$ROOTDIR/docksettings_error"; exit;;
    esac
done

## ==============================================================================
## MAIN EXECUTION
## ==============================================================================

mkdir -p "$LOCKDIR"
LOCKFILE="$LOCKDIR/global.lock"
if [ -f "$LOCKFILE" ]; then
    PID=$(cat "$LOCKFILE")
    if kill -0 "$PID" 2>/dev/null; then exit 1; else rm -f "$LOCKFILE"; fi
fi
echo $$ > "$LOCKFILE"
trap "rm -f '$LOCKFILE'" EXIT

# 1. ALWAYS Crawl and Register
crawl_and_register

# 2. Handle Swap
if [ "$UDEV_MODE" = "1" ] && [ -n "$GPU_OVERRIDE" ]; then
    perform_swap "$GPU_OVERRIDE"
elif [ "$UDEV_MODE" = "1" ] && [ -z "$GPU_OVERRIDE" ]; then
    echo "$DATE ERROR: -g flag required" >> "$DOCK_DIR/global.log"
    exit 1
fi

if [ -z "$UDEV_MODE" ]; then help; fi
exit 0
