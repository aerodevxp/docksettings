#!/bin/bash
## One-time migration: old shader locations -> centralized $DOCK_DIR/shaders/
## This is not a script you should have to use is using a version written after August 2026

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOTDIR="$SCRIPT_DIR"
DOCK_DIR="$ROOTDIR/docksettings"

SHADER_DIR="$DOCK_DIR/shaders"
MESA_IGPU_SHADER="$SHADER_DIR/mesa_igpu"
MESA_EGPU_SHADER="$SHADER_DIR/mesa_egpu"
DXVK_IGPU_SHADER="$SHADER_DIR/dxvk_igpu"
DXVK_EGPU_SHADER="$SHADER_DIR/dxvk_egpu"

# Old locations
OLD_MESA_IGPU="$HOME/.cache/mesa_shader_cache_igpu"
OLD_MESA_EGPU="$HOME/.cache/mesa_shader_cache_egpu"
OLD_MESA_LIVE="$HOME/.cache/mesa_shader_cache"

STEAM_COMPAT_ROOTS=(
    "$HOME/.steam/steam/steamapps/compatdata"
    "/run/media/system/GAMES/steamapps/compatdata"
)

echo "=== Shader Cache Migration ==="
echo "Target: $SHADER_DIR"
echo ""

mkdir -p "$MESA_IGPU_SHADER" "$MESA_EGPU_SHADER" "$DXVK_IGPU_SHADER" "$DXVK_EGPU_SHADER"

# --- Mesa ---
migrate_mesa() {
    local old_dir="$1"
    local target="$2"
    local label="$3"

    if [ -d "$old_dir" ]; then
        local file_count=$(find "$old_dir" -type f 2>/dev/null | wc -l)
        echo "[Mesa $label] Found $file_count files in $old_dir"
        echo "  -> Migrating to $target"

        cp -rp "$old_dir"/* "$target/" 2>/dev/null
        echo "  -> Done. Old directory left in place for safety:"
        echo "     $old_dir"
        echo "     Delete manually after confirming the migration worked."
    else
        echo "[Mesa $label] Not found: $old_dir (skipping)"
    fi
    echo ""
}

migrate_mesa "$OLD_MESA_IGPU" "$MESA_IGPU_SHADER" "iGPU"
migrate_mesa "$OLD_MESA_EGPU" "$MESA_EGPU_SHADER" "eGPU"

# Also check the live mesa cache (could be a real dir or symlink)
if [ -d "$OLD_MESA_LIVE" ] && [ ! -L "$OLD_MESA_LIVE" ]; then
    echo "[Mesa LIVE] Real directory detected at $OLD_MESA_LIVE"
    echo "  This contains shaders from whatever GPU you're currently on."
    echo "  Which GPU is currently active? (igpu/egpu):"
    read -r current_gpu
    echo ""

    case "$current_gpu" in
        igpu)
            migrate_mesa "$OLD_MESA_LIVE" "$MESA_IGPU_SHADER" "LIVE->iGPU"
            ;;
        egpu)
            migrate_mesa "$OLD_MESA_LIVE" "$MESA_EGPU_SHADER" "LIVE->eGPU"
            ;;
        *)
            echo "  Invalid input, skipping live cache migration."
            echo "  You'll need to handle this manually."
            ;;
    esac
elif [ -L "$OLD_MESA_LIVE" ]; then
    echo "[Mesa LIVE] Already a symlink -> $(readlink "$OLD_MESA_LIVE")"
    echo "  Nothing to migrate, swap_shaders() will repoint it."
else
    echo "[Mesa LIVE] Not found: $OLD_MESA_LIVE"
fi
echo ""

# --- DXVK ---
echo "=== DXVK State Cache Migration ==="
echo ""

for root in "${STEAM_COMPAT_ROOTS[@]}"; do
    [ -d "$root" ] || continue

    for prefix in "$root"/*/; do
        [ -d "$prefix" ] || continue

        local appid=$(basename "$prefix")
        local old_igpu="${prefix}dxvk-state-cache-igpu"
        local old_egpu="${prefix}dxvk-state-cache-egpu"
        local old_live="${prefix}dxvk-state-cache"
        local migrated_something=0

        # Old iGPU file
        if [ -f "$old_igpu" ]; then
            echo "  [$appid] Found old iGPU cache"
            cp -p "$old_igpu" "$DXVK_IGPU_SHADER/$appid" 2>/dev/null && \
                echo "    -> Migrated to $DXVK_IGPU_SHADER/$appid" || \
                echo "    -> FAILED"
            migrated_something=1
        fi

        # Old eGPU file
        if [ -f "$old_egpu" ]; then
            echo "  [$appid] Found old eGPU cache"
            cp -p "$old_egpu" "$DXVK_EGPU_SHADER/$appid" 2>/dev/null && \
                echo "    -> Migrated to $DXVK_EGPU_SHADER/$appid" || \
                echo "    -> FAILED"
            migrated_something=1
        fi

        # Live file (if real, not symlink)
        if [ -f "$old_live" ] && [ ! -L "$old_live" ]; then
            echo "  [$appid] Found live DXVK cache (real file)"
            echo "    Which GPU is currently active for this game? (igpu/egpu/skip):"
            read -r current_gpu

            case "$current_gpu" in
                igpu)
                    cp -p "$old_live" "$DXVK_IGPU_SHADER/$appid" 2>/dev/null && \
                        echo "    -> Migrated to iGPU store" || \
                        echo "    -> FAILED"
                    migrated_something=1
                    ;;
                egpu)
                    cp -p "$old_live" "$DXVK_EGPU_SHADER/$appid" 2>/dev/null && \
                        echo "    -> Migrated to eGPU store" || \
                        echo "    -> FAILED"
                    migrated_something=1
                    ;;
                skip)
                    echo "    -> Skipped"
                    ;;
                *)
                    echo "    -> Invalid input, skipped"
                    ;;
            esac
        elif [ -L "$old_live" ]; then
            echo "  [$appid] Live cache already symlinked, skipping"
        fi

        [ "$migrated_something" = "1" ] && echo ""
    done
done

echo ""
echo "=== Migration Complete ==="
echo ""
echo "Old files/directories have been LEFT IN PLACE for safety."
echo "After confirming docksettings.sh works correctly, remove them manually:"
echo "  rm -rf $OLD_MESA_IGPU"
echo "  rm -rf $OLD_MESA_EGPU"
echo "  rm -f  ~/.steam/steam/steamapps/compatdata/*/dxvk-state-cache-igpu"
echo "  rm -f  ~/.steam/steam/steamapps/compatdata/*/dxvk-state-cache-egpu"
echo ""
echo "The live symlinks (mesa_shader_cache, dxvk-state-cache) will be"
echo "repointed automatically on your first swap with the updated script."
