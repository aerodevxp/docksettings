#!/bin/bash

## Changelog
## 15-01-2024 v0.1 Initial release
## 19-01-2024 v0.2 Display help; replace positional parameters with options; allow prefix shortcut to steamapps location
## 20-01-2024 v0.3 Added support for games which are syncing config data to Steam Cloud
## 21-01-2024 v0.4 Added support for prefix STEAMAPPS for automatic detection of config file location; added support for restoring original config file
## 28-01-2024 v0.5 Added support for retrieving inputs from local database and autodownload db from github
## 17-06-2026 v0.6 Rewritten for ROG Ally X + eGPU on CachyOS; GPU detection instead of resolution; udev integration; multi-config; patch mode; power profiles; Wayland support; lock files; portable paths


## Define basic variables

ROOTDIR="${XDG_DOCUMENTS_DIR:-$HOME/Documents}"
DATE=$(date '+%d-%m-%Y %H:%M:%S')
CLOUDSLEEP=10
DB=$ROOTDIR/docksettings_db*.csv
DBURL=https://raw.githubusercontent.com/msterbi/docksettings/main/docksettings_db.csv
LOCKDIR="/tmp/docksettings"


## GPU detection function

detect_gpu() {
    ## Method 1: Check for eGPU via lspci
    ## Replace "YOUR_EGPU_MODEL" with a unique identifier string from your eGPU
    ## Run: lspci | grep VGA  to find what to put here
    if lspci | grep -i "VGA" | grep -qi "YOUR_EGPU_MODEL"; then
        echo "egpu"
        return 0
    fi

    ## Method 2: Check Vulkan renderer
    if command -v vulkaninfo &>/dev/null; then
        RENDERER=$(vulkaninfo --summary 2>/dev/null | grep "deviceName" | head -1)
        if echo "$RENDERER" | grep -qi "YOUR_EGPU_MODEL"; then
            echo "egpu"
            return 0
        fi
    fi

    ## Method 3: Check if specific PCI device is present
    ## Find your eGPU's PCI ID with: lspci -nn | grep VGA
    ## Then uncomment and update the line below:
    # if lspci | grep -qi "YOUR_PCI_ID_HERE"; then
    #     echo "egpu"
    #     return 0
    # fi

    ## Default to iGPU if no eGPU detected
    echo "igpu"
}


## Resolution detection function (Wayland-compatible)

detect_resolution() {
    if command -v xrandr &>/dev/null && [ -n "$DISPLAY" ]; then
        xrandr --current 2>/dev/null | grep " connected primary" | awk '{print $3}' | cut -d'+' -f1
    elif command -v wlr-randr &>/dev/null; then
        wlr-randr 2>/dev/null | grep "current" | head -1 | awk '{print $2}'
    elif command -v kscreen-doctor &>/dev/null; then
        kscreen-doctor --outputs 2>/dev/null | grep "Geometry" | head -1 | grep -oP '\d+x\d+'
    else
        echo "unknown"
    fi
}


## Power profile switching function

switch_power_profile() {
    local gpu_state="$1"

    if command -v powerprofilectl &>/dev/null; then
        if [ "$gpu_state" = "egpu" ]; then
            powerprofilectl set performance 2>/dev/null
        else
            powerprofilectl set balanced 2>/dev/null
        fi
    elif [ -f /sys/firmware/acpi/platform_profile ]; then
        if [ "$gpu_state" = "egpu" ]; then
            echo "performance" > /sys/firmware/acpi/platform_profile 2>/dev/null
        else
            echo "balanced" > /sys/firmware/acpi/platform_profile 2>/dev/null
        fi
    elif command -v asusctl &>/dev/null; then
        if [ "$gpu_state" = "egpu" ]; then
            asusctl profile --profile Performance 2>/dev/null
        else
            asusctl profile --profile Quiet 2>/dev/null
        fi
    fi
}


## Gamescope/Mangohud config switching function

switch_gaming_overlays() {
    local gpu_state="$1"
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

    ## Gamescope
    if [ -d "$config_home/gamescope" ]; then
        if [ "$gpu_state" = "egpu" ] && [ -f "$config_home/gamescope/dock.conf" ]; then
            ln -sf "$config_home/gamescope/dock.conf" "$config_home/gamescope/gamescope.conf"
        elif [ -f "$config_home/gamescope/deck.conf" ]; then
            ln -sf "$config_home/gamescope/deck.conf" "$config_home/gamescope/gamescope.conf"
        fi
    fi

    ## MangoHud
    if [ -d "$config_home/MangoHud" ]; then
        if [ "$gpu_state" = "egpu" ] && [ -f "$config_home/MangoHud/dock.conf" ]; then
            ln -sf "$config_home/MangoHud/dock.conf" "$config_home/MangoHud/MangoHud.conf"
        elif [ -f "$config_home/MangoHud/deck.conf" ]; then
            ln -sf "$config_home/MangoHud/deck.conf" "$config_home/MangoHud/MangoHud.conf"
        fi
    fi
}


## Display help message

help()
{
    echo "Available options for docksettings.sh:"
    echo "-h          Print this help"
    echo "-n          Name of game"
    echo "-f          Location of config file (comma-separated for multiple)"
    echo "-i          Enable input from local database file"
    echo "-c          Name of game's executable (optional; for games which are syncing config data to Steam Cloud)"
    echo "-r          Restore original backup (which have been taken during first run) of config file"
    echo "-g          Override GPU state (igpu/egpu)"
    echo "-p          Patch mode: modify specific settings instead of full file swap"
    echo "-d          Dry run: show what would be done without making changes"
    echo "-u          Udev mode: auto-detect GPU and swap all configured games"
    echo ""
    echo "Examples:"
    echo "./docksettings.sh -n \"Resident Evil 2\" -i"
    echo "./docksettings.sh -n \"Resident Evil 2\" -f \"STEAMAPPS/common/RESIDENT EVIL 2  BIOHAZARD RE2/re2_config.ini\""
    echo "./docksettings.sh -n \"Resident Evil 2\" -f \"NVME/common/RESIDENT EVIL 2  BIOHAZARD RE2/re2_config.ini\""
    echo "./docksettings.sh -n \"Resident Evil 2\" -f \"SD/common/RESIDENT EVIL 2  BIOHAZARD RE2/re2_config.ini\""
    echo "./docksettings.sh -n \"Game\" -f \"STEAMAPPS/common/Game/config1.ini,STEAMAPPS/common/Game/config2.ini\""
    echo "./docksettings.sh -n \"NieR Automata\" -f \"NVME/compatdata/524220/pfx/drive_c/users/steamuser/Documents/My Games/NieR_Automata/SystemData.dat\" -c \"NieRAutomata.exe\""
    echo "./docksettings.sh -n \"Resident Evil 2\" -g egpu"
    echo "./docksettings.sh -n \"Resident Evil 2\" -d"
    echo "./docksettings.sh -u"
}


## Get the options

while getopts "hurdpic:n:f:g:" option; do
    case $option in
        h) help; exit;;
        c) GAMEEXE=$OPTARG;;
        n) NAME=$OPTARG;;
        f) FILE=$OPTARG;;
        r) RESTORE=1;;
        i) INPUT=1;;
        g) GPU_OVERRIDE=$OPTARG;;
        p) PATCH_MODE=1;;
        d) DRYRUN=1;;
        u) UDEV_MODE=1;;
        \?) echo "$DATE Invalid options have been used." >> "$ROOTDIR/docksettings_error"; exit;;
    esac
done


## Udev mode: iterate through all configured games

if [ "$UDEV_MODE" = "1" ]; then
    GPU_STATE=$(detect_gpu)
    echo "$DATE UDEV: Detected GPU state: $GPU_STATE" >> "$ROOTDIR/docksettings_udev_log"

    switch_power_profile "$GPU_STATE"
    echo "$DATE UDEV: Power profile switched for $GPU_STATE" >> "$ROOTDIR/docksettings_udev_log"

    switch_gaming_overlays "$GPU_STATE"
    echo "$DATE UDEV: Gaming overlays switched for $GPU_STATE" >> "$ROOTDIR/docksettings_udev_log"

    if [ -d "$ROOTDIR/docksettings" ]; then
        for game_dir in "$ROOTDIR/docksettings"/*/; do
            GAME_NAME=$(basename "$game_dir")
            if [ "$GAME_NAME" != "docksettings" ] && [ -f "$game_dir/logfile" ]; then
                echo "$DATE UDEV: Swapping config for $GAME_NAME" >> "$ROOTDIR/docksettings_udev_log"
                "$0" -n "$GAME_NAME" -i -g "$GPU_STATE"
            fi
        done
    fi

    echo "$DATE UDEV: Complete" >> "$ROOTDIR/docksettings_udev_log"
    exit 0
fi


## Check if mandatory options have been provided

if [ "$INPUT" = "" ]; then
    if [ "$NAME" = "" ] || [ "$FILE" = "" ]; then
        echo "$DATE Mandatory options have not been provided. Please provide name of game and location to config file." >> "$ROOTDIR/docksettings_error"
        echo "$DATE Example: ./docksettings.sh -n \"Resident Evil 2\" -f \"STEAMAPPS/common/RESIDENT EVIL 2  BIOHAZARD RE2/re2_config.ini\"" >> "$ROOTDIR/docksettings_error"
        exit 1
    fi
elif [ "$INPUT" = "1" ]; then
    if [ "$NAME" = "" ]; then
        echo "$DATE Mandatory options have not been provided. Please provide name of game." >> "$ROOTDIR/docksettings_error"
        echo "$DATE Example: ./docksettings.sh -n \"Resident Evil 2\" -i" >> "$ROOTDIR/docksettings_error"
        exit 1
    fi
fi


## Validate GPU override if provided

if [ -n "$GPU_OVERRIDE" ]; then
    if [ "$GPU_OVERRIDE" != "igpu" ] && [ "$GPU_OVERRIDE" != "egpu" ]; then
        echo "$DATE Invalid GPU override: $GPU_OVERRIDE. Must be 'igpu' or 'egpu'." >> "$ROOTDIR/docksettings_error"
        exit 1
    fi
fi


## Download or update docksettings_db.csv if necessary

if [ "$INPUT" = "1" ]; then
    if [ ! -f "$ROOTDIR/docksettings_db.csv" ]; then
        echo "$DATE File docksettings_db.csv does not exist. Starting download." >> "$ROOTDIR/docksettings_db_log"
        curl -f $DBURL -o $ROOTDIR/docksettings_db.csv >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "$DATE File docksettings_db.csv has been downloaded." >> "$ROOTDIR/docksettings_db_log"
        else
            echo "$DATE Not able to download from $DBURL." >> "$ROOTDIR/docksettings_db_log"
        fi
    else
        DBSHA1=$(sha1sum $ROOTDIR/docksettings_db.csv | cut -d " " -f1)
        DBSHA2=$(curl -f $DBURL -s -o - | sha1sum | cut -d " " -f1)
        if [ "$DBSHA1" == "$DBSHA2" ]; then
            echo "$DATE File docksettings_db.csv is up to date. Nothing to do" >> "$ROOTDIR/docksettings_db_log"
        elif [ "$DBSHA2" == "da39a3ee5e6b4b0d3255bfef95601890afd80709" ]; then
            echo "$DATE Not able to reach $DBURL. Database update failed." >> "$ROOTDIR/docksettings_db_log"
        else
            curl -f $DBURL -o $ROOTDIR/docksettings_db.csv >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "$DATE File docksettings_db.csv has been updated." >> "$ROOTDIR/docksettings_db_log"
            else
                echo "$DATE Update of docksettings_db.csv failed." >> "$ROOTDIR/docksettings_db_log"
            fi
        fi
    fi
fi


## Get variables from local database

if [ "$INPUT" = "1" ]; then
    ENTRIES=$(grep "$NAME;" $DB 2> /dev/null | wc -l)
    DBENTRY=$(grep "$NAME;" $DB 2> /dev/null)
    if [ $? -eq 1 ]; then
        echo "$DATE Database entry for game $NAME does not exist. Exiting" >> "$ROOTDIR/docksettings_error"
        exit 1
    elif [ $ENTRIES -gt 1 ]; then
        echo "$DATE There are two or more database entries for game $NAME. Exiting" >> "$ROOTDIR/docksettings_error"
        exit 1
    else
        FILE=$(echo "$DBENTRY" | cut -d ":" -f2- | cut -d ";" -f2)
        GAMEEXE=$(echo "$DBENTRY" | cut -d ":" -f2- | cut -d ";" -f3)
    fi
fi


## Define path to game specific logfile

LOGFILE="$ROOTDIR/docksettings/$NAME/logfile"


## Create lock file to prevent concurrent execution

mkdir -p "$LOCKDIR"
LOCKFILE="$LOCKDIR/${NAME}.lock"
if [ -f "$LOCKFILE" ]; then
    PID=$(cat "$LOCKFILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "$DATE Another instance is already running for $NAME (PID: $PID). Exiting." >> "$LOGFILE"
        exit 1
    else
        rm -f "$LOCKFILE"
    fi
fi
echo $$ > "$LOCKFILE"
trap "rm -f '$LOCKFILE'" EXIT


## Function to process a single config file

process_config() {
    local FILE_PATH="$1"
    local CONFIG=$(echo "$FILE_PATH" | awk '{print $NF}' FS=/)


    ## Extract config filename from path

    echo "$DATE INFO: Processing config file: $CONFIG" >> "$LOGFILE"


    ## Check if directory structure exists and create it if not

    if [ -d "$ROOTDIR/docksettings/$NAME" ]; then
        echo "$DATE INFO: Directory structure already exists." >> "$LOGFILE"
    else
        mkdir -p "$ROOTDIR/docksettings/$NAME/deck"
        mkdir -p "$ROOTDIR/docksettings/$NAME/dock"
        echo "$DATE CHANGE: Directory structure have been created." >> "$LOGFILE"
    fi


    ## Support usage of STEAMAPPS prefix for automatic detection of config file location

    if [[ $FILE_PATH = STEAMAPPS* ]]; then
        NVME="$HOME/.steam/steam/steamapps"
        SDNAME=$(df | grep mmcblk0 | awk '{print $6}' | awk -F/ '{print $5}')
        SD="/run/media/$USER/$SDNAME/steamapps"
        if [ -f "$(echo "$FILE_PATH" | sed "s|STEAMAPPS|$NVME|")" ]; then
            FILE_PATH=$(echo "$FILE_PATH" | sed "s|STEAMAPPS|$NVME|")
            echo "$DATE INFO: Config file location have been automatically found on NVMe: $FILE_PATH." >> "$LOGFILE"
        elif [ -f "$(echo "$FILE_PATH" | sed "s|STEAMAPPS|$SD|")" ]; then
            FILE_PATH=$(echo "$FILE_PATH" | sed "s|STEAMAPPS|$SD|")
            echo "$DATE INFO: Config file location have been automatically found on SD card: $FILE_PATH." >> "$LOGFILE"
        else
            echo "$DATE ERROR: Not able to automatically detect config file location. Exiting." >> "$LOGFILE"
            echo "------------------------------------" >> "$LOGFILE"
            return 1
        fi
    fi


    ## Support usage of NVME and SD prefixes for config file location shortcuts to steamapps folder

    if [[ $FILE_PATH = NVME* ]]; then
        NVME="$HOME/.steam/steam/steamapps"
        FILE_PATH=$(echo "$FILE_PATH" | sed "s|NVME|$NVME|")
    elif [[ $FILE_PATH = SD* ]]; then
        SDNAME=$(df | grep mmcblk0 | awk '{print $6}' | awk -F/ '{print $5}')
        SD="/run/media/$USER/$SDNAME/steamapps"
        FILE_PATH=$(echo "$FILE_PATH" | sed "s|SD|$SD|")
    fi


    ## Check validity of provided config file path

    if [ -f "$FILE_PATH" ]; then
        echo "$DATE INFO: Provided config file location is valid." >> "$LOGFILE"
    else
        echo "$DATE ERROR: Provided config file location doesn't exist. Exiting." >> "$LOGFILE"
        echo "------------------------------------" >> "$LOGFILE"
        return 1
    fi


    ## Restore initial backup if requested by option -r

    if [ "$RESTORE" = "1" ]; then
        if [ ! -f "$ROOTDIR/docksettings/$NAME/backup_$CONFIG" ]; then
            echo "$DATE ERROR: Restore failed. Initial backup of config file $ROOTDIR/docksettings/$NAME/backup_$CONFIG does not exist. Exiting" >> "$LOGFILE"
            echo "------------------------------------" >> "$LOGFILE"
            return 1
        else
            if [ "$DRYRUN" = "1" ]; then
                echo "$DATE DRY RUN: Would restore $ROOTDIR/docksettings/$NAME/backup_$CONFIG to $FILE_PATH" >> "$LOGFILE"
            else
                cp -p "$ROOTDIR/docksettings/$NAME/backup_$CONFIG" "$FILE_PATH"
                echo "$DATE CHANGE: Initial backup of config file $ROOTDIR/docksettings/$NAME/backup_$CONFIG have been restored to $FILE_PATH. Exiting." >> "$LOGFILE"
            fi
            echo "------------------------------------" >> "$LOGFILE"
            return 0
        fi
    fi


    ## Create initial backup and two profiles of configfile

    if [ -f "$ROOTDIR/docksettings/$NAME/backup_$CONFIG" ]; then
        echo "$DATE INFO: Initial backup and profiles already exist." >> "$LOGFILE"
    else
        if [ "$DRYRUN" = "1" ]; then
            echo "$DATE DRY RUN: Would create backup and profiles for $CONFIG" >> "$LOGFILE"
        else
            cp -p "$FILE_PATH" "$ROOTDIR/docksettings/$NAME/backup_$CONFIG"
            cp -p "$FILE_PATH" "$ROOTDIR/docksettings/$NAME/deck/deck_$CONFIG"
            cp -p "$FILE_PATH" "$ROOTDIR/docksettings/$NAME/dock/dock_$CONFIG"
            echo "$DATE CHANGE: Initial backup and docked/undocked profiles have been created." >> "$LOGFILE"
        fi
    fi


    ## Create last state file if it doesn't exist yet

    if [ ! -f "$ROOTDIR/docksettings/$NAME/laststate" ]; then
        echo 0 > "$ROOTDIR/docksettings/$NAME/laststate"
        echo "$DATE CHANGE: Last state file have been created with dummy value 'undocked'." >> "$LOGFILE"
    fi


    ## Determine current GPU state

    if [ -n "$GPU_OVERRIDE" ]; then
        GPU_STATE="$GPU_OVERRIDE"
        echo "$DATE INFO: GPU state overridden to: $GPU_STATE" >> "$LOGFILE"
    else
        GPU_STATE=$(detect_gpu)
        echo "$DATE INFO: Auto-detected GPU state: $GPU_STATE" >> "$LOGFILE"
    fi


    ## Map GPU state to dock/deck terminology

    if [ "$GPU_STATE" = "egpu" ]; then
        DOCK=1
        STATE_LABEL="docked (eGPU)"
    else
        DOCK=0
        STATE_LABEL="undocked (iGPU)"
    fi


    ## Read last state value

    if [ "$GAMEEXE" = "" ]; then
        LASTSTATE=$(cat "$ROOTDIR/docksettings/$NAME/laststate")

        if [ "$LASTSTATE" = "0" ]; then
            echo "$DATE INFO: Last state was 'undocked'." >> "$LOGFILE"
        elif [ "$LASTSTATE" = "1" ]; then
            echo "$DATE INFO: Last state was 'docked'." >> "$LOGFILE"
        else
            echo "$DATE ERROR: Last state was 'unknown'. Exiting." >> "$LOGFILE"
            echo "------------------------------------" >> "$LOGFILE"
            return 1
        fi
    fi


    ## Save current state to file for future run

    echo "$DOCK" > "$ROOTDIR/docksettings/$NAME/laststate"
    echo "$DATE INFO: Current state is '$STATE_LABEL'." >> "$LOGFILE"


    ## Switch power profile based on GPU state

    if [ "$DRYRUN" != "1" ]; then
        switch_power_profile "$GPU_STATE"
        echo "$DATE INFO: Power profile switched for $GPU_STATE." >> "$LOGFILE"
    else
        echo "$DATE DRY RUN: Would switch power profile for $GPU_STATE" >> "$LOGFILE"
    fi


    ## Switch gaming overlay configs

    if [ "$DRYRUN" != "1" ]; then
        switch_gaming_overlays "$GPU_STATE"
        echo "$DATE INFO: Gaming overlays switched for $GPU_STATE." >> "$LOGFILE"
    else
        echo "$DATE DRY RUN: Would switch gaming overlays for $GPU_STATE" >> "$LOGFILE"
    fi


    ## Patch mode: modify specific settings instead of full file swap

    if [ "$PATCH_MODE" = "1" ]; then
        echo "$DATE INFO: Patch mode enabled. Modifying specific settings." >> "$LOGFILE"

        if [ "$DRYRUN" = "1" ]; then
            echo "$DATE DRY RUN: Would patch $FILE_PATH for $GPU_STATE" >> "$LOGFILE"
        else
            ## Add your game-specific patches here
            ## Example for INI files:
            # if [ "$GPU_STATE" = "egpu" ]; then
            #     sed -i 's/Resolution=.*/Resolution=3840x2160/' "$FILE_PATH"
            #     sed -i 's/Quality=.*/Quality=Ultra/' "$FILE_PATH"
            # else
            #     sed -i 's/Resolution=.*/Resolution=1280x800/' "$FILE_PATH"
            #     sed -i 's/Quality=.*/Quality=Low/' "$FILE_PATH"
            # fi
            echo "$DATE INFO: Patch mode active - add your sed commands to the script." >> "$LOGFILE"
        fi

        echo "------------------------------------" >> "$LOGFILE"
        return 0
    fi


    ## Implement logic for cloud-based config files

    if [ "$GAMEEXE" != "" ]; then
        echo "$DATE INFO: Starting cloud-based config file syncing sequence." >> "$LOGFILE"
        if [ "$DOCK" = "0" ]; then
            if [ "$DRYRUN" = "1" ]; then
                echo "$DATE DRY RUN: Would copy $ROOTDIR/docksettings/$NAME/deck/deck_$CONFIG to $FILE_PATH" >> "$LOGFILE"
            else
                cp -p "$ROOTDIR/docksettings/$NAME/deck/deck_$CONFIG" "$FILE_PATH"
                echo "$DATE CHANGE: Copying cloud-based config file $ROOTDIR/docksettings/$NAME/deck/deck_$CONFIG to $FILE_PATH" >> "$LOGFILE"
            fi
        elif [ "$DOCK" = "1" ]; then
            if [ "$DRYRUN" = "1" ]; then
                echo "$DATE DRY RUN: Would copy $ROOTDIR/docksettings/$NAME/dock/dock_$CONFIG to $FILE_PATH" >> "$LOGFILE"
            else
                cp -p "$ROOTDIR/docksettings/$NAME/dock/dock_$CONFIG" "$FILE_PATH"
                echo "$DATE CHANGE: Copying cloud-based config file $ROOTDIR/docksettings/$NAME/dock/dock_$CONFIG to $FILE_PATH" >> "$LOGFILE"
            fi
        fi

        while true
        do
            ps -efa | grep "$GAMEEXE" | grep -v "$0" | grep -v grep >/dev/null 2>&1
            if [ $? -eq 1 ]; then
                SHA1=$(sha1sum "$FILE_PATH" | cut -d " " -f1)
                echo "$(date '+%d-%m-%Y %H:%M:%S') INFO: Checksum of $FILE_PATH is $SHA1" >> "$LOGFILE"
                if [ "$DOCK" = "0" ]; then
                    SHA2=$(sha1sum "$ROOTDIR/docksettings/$NAME/deck/deck_$CONFIG" | cut -d " " -f1)
                    echo "$(date '+%d-%m-%Y %H:%M:%S') INFO: Checksum of deck_$CONFIG is $SHA2" >> "$LOGFILE"
                    if [ "$SHA1" == "$SHA2" ]; then
                        echo "$(date '+%d-%m-%Y %H:%M:%S') INFO: Checksum matched. Nothing to do." >> "$LOGFILE"
                    else
                        if [ "$DRYRUN" = "1" ]; then
                            echo "$(date '+%d-%m-%Y %H:%M:%S') DRY RUN: Would sync $FILE_PATH to deck profile" >> "$LOGFILE"
                        else
                            cp -p "$FILE_PATH" "$ROOTDIR/docksettings/$NAME/deck/deck_$CONFIG"
                            echo "$(date '+%d-%m-%Y %H:%M:%S') CHANGE: Config file has been updated. Syncing." >> "$LOGFILE"
                        fi
                    fi
                elif [ "$DOCK" = "1" ]; then
                    SHA2=$(sha1sum "$ROOTDIR/docksettings/$NAME/dock/dock_$CONFIG" | cut -d " " -f1)
                    echo "$(date '+%d-%m-%Y %H:%M:%S') INFO: Checksum of dock_$CONFIG is $SHA2" >> "$LOGFILE"
                    if [ "$SHA1" == "$SHA2" ]; then
                        echo "$(date '+%d-%m-%Y %H:%M:%S') INFO: Checksum matched. Nothing to do." >> "$LOGFILE"
                    else
                        if [ "$DRYRUN" = "1" ]; then
                            echo "$(date '+%d-%m-%Y %H:%M:%S') DRY RUN: Would sync $FILE_PATH to dock profile" >> "$LOGFILE"
                        else
                            cp -p "$FILE_PATH" "$ROOTDIR/docksettings/$NAME/dock/dock_$CONFIG"
                            echo "$(date '+%d-%m-%Y %H:%M:%S') CHANGE: Config file has been updated. Syncing." >> "$LOGFILE"
                        fi
                    fi
                fi
                echo "$(date '+%d-%m-%Y %H:%M:%S') CHANGE: Process $GAMEEXE no longer running. Exiting." >> "$LOGFILE"
                echo "------------------------------------" >> "$LOGFILE"
                return 0
            else
                echo "$(date '+%d-%m-%Y %H:%M:%S') INFO: Process $GAMEEXE still running. Sleeping." >> "$LOGFILE"
                sleep $CLOUDSLEEP
            fi
        done
    fi


    ## Copy correct savefile according to current state and last state

    if [ "$DOCK" = "0" ] && [ "$LASTSTATE" = "0" ]; then
        echo "$DATE INFO: Last state was 'undocked' and current state is 'undocked'. Nothing to do." >> "$LOGFILE"
    elif [ "$DOCK" = "0" ] && [ "$LASTSTATE" = "1" ]; then
        echo "$DATE CHANGE: Last state was 'docked' and current state is 'undocked'. Copying correct save files." >> "$LOGFILE"
        if [ "$DRYRUN" = "1" ]; then
            echo "$DATE DRY RUN: Would copy $FILE_PATH to dock profile and deck profile to $FILE_PATH" >> "$LOGFILE"
        else
            cp -p "$FILE_PATH" "$ROOTDIR/docksettings/$NAME/dock/dock_$CONFIG"
            echo "$DATE CHANGE: Copying file $FILE_PATH to $ROOTDIR/docksettings/$NAME/dock/dock_$CONFIG" >> "$LOGFILE"
            cp -p "$ROOTDIR/docksettings/$NAME/deck/deck_$CONFIG" "$FILE_PATH"
            echo "$DATE CHANGE: Copying file $ROOTDIR/docksettings/$NAME/deck/deck_$CONFIG to $FILE_PATH" >> "$LOGFILE"
        fi
    elif [ "$DOCK" = "1" ] && [ "$LASTSTATE" = "0" ]; then
        echo "$DATE CHANGE: Last state was 'undocked' and current state is 'docked'. Copying correct save files." >> "$LOGFILE"
        if [ "$DRYRUN" = "1" ]; then
            echo "$DATE DRY RUN: Would copy $FILE_PATH to deck profile and dock profile to $FILE_PATH" >> "$LOGFILE"
        else
            cp -p "$FILE_PATH" "$ROOTDIR/docksettings/$NAME/deck/deck_$CONFIG"
            echo "$DATE CHANGE: Copying file $FILE_PATH to $ROOTDIR/docksettings/$NAME/deck/deck_$CONFIG" >> "$LOGFILE"
            cp -p "$ROOTDIR/docksettings/$NAME/dock/dock_$CONFIG" "$FILE_PATH"
            echo "$DATE CHANGE: Copying file $ROOTDIR/docksettings/$NAME/dock/dock_$CONFIG to $FILE_PATH" >> "$LOGFILE"
        fi
    elif [ "$DOCK" = "1" ] && [ "$LASTSTATE" = "1" ]; then
        echo "$DATE INFO: Last state was 'docked' and current state is 'docked'. Nothing to do." >> "$LOGFILE"
    fi

    echo "------------------------------------" >> "$LOGFILE"
    return 0
}


## Main execution: handle single or multiple config files

if [[ "$FILE" == *","* ]]; then
    ## Multiple config files
    IFS=',' read -ra CONFIG_PATHS <<< "$FILE"
    for FILE_PATH in "${CONFIG_PATHS[@]}"; do
        FILE_PATH=$(echo "$FILE_PATH" | xargs)  ## Trim whitespace
        process_config "$FILE_PATH"
    done
else
    ## Single config file
    process_config "$FILE"
fi


## Cleanup lock file on exit

rm -f "$LOCKFILE"
exit 0
