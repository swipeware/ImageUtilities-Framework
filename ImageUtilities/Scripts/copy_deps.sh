#!/bin/bash

# Ensure the script is run in the current directory
TARGET_DIR=$(pwd)

echo "Scanning for dylib dependencies and copying them to: $TARGET_DIR"

# Find all dylib files in the directory
find "$TARGET_DIR" -type f -name "*.dylib" | while read -r dylib; do
    echo "Processing: $dylib"

    # List all linked dependencies
    otool -L "$dylib" | awk '{print $1}' | grep -E '^/' | while read -r dep; do
        # Ignore system frameworks
        if [[ "$dep" == /System/* || "$dep" == /usr/lib/* ]]; then
            echo "Skipping system library: $dep"
            continue
        fi

        # Extract filename from full path
        dep_filename=$(basename "$dep")

        # Check if the dependency already exists in the target directory
        if [[ -f "$TARGET_DIR/$dep_filename" ]]; then
            echo "Already exists: $dep_filename"
        else
            echo "Copying: $dep -> $TARGET_DIR/$dep_filename"
            cp "$dep" "$TARGET_DIR/$dep_filename"
            chmod 755 "$TARGET_DIR/$dep_filename"
        fi
    done
done

echo "Done"
