#!/bin/bash

# Function to modify the dylib dependencies and sign the dylib
process_dylib() {
    local dylib="$1"

    echo "Processing: $dylib"

    # Get the current ID of the dylib
    local current_id
    current_id=$(otool -D "$dylib" | tail -n 1)

    # Change the ID only if it does not start with @
    if [[ "$current_id" != @* ]]; then
        local new_id="@rpath/$(basename "$dylib")"
        install_name_tool -id "$new_id" "$dylib" && echo "Changed ID of $dylib to $new_id"
    fi

    # Change library paths from /opt/local/lib to @loader_path
    otool -L "$dylib" | awk '{print $1}' | grep '^/opt/local/lib' | while IFS= read -r dep; do
        local new_dep="@loader_path/$(basename "$dep")"
        install_name_tool -change "$dep" "$new_dep" "$dylib" && echo "Updated dependency: $dep -> $new_dep"
    done

    # Change dependencies that start with @rpath or @loader_path to @loader_path
    otool -L "$dylib" | awk '{print $1}' | grep '^@rpath\|^@loader_path' | while IFS= read -r dep; do
        local new_dep="@loader_path/$(basename "$dep")"
        install_name_tool -change "$dep" "$new_dep" "$dylib" && echo "Updated dependency: $dep -> $new_dep"
    done

    # Remove all rpath entries
    otool -l "$dylib" | awk '/path/ {print $2}' | grep -v '@' | while IFS= read -r rpath; do
        install_name_tool -delete_rpath "$rpath" "$dylib" && echo "Removed rpath: $rpath"
    done

    # Sign the dylib with an ad-hoc signature
    codesign --force --sign - "$dylib" && echo "Signed $dylib with an ad-hoc signature"
}

# Find and process all dylibs safely handling filenames with spaces
find . -type f -name "*.dylib" -print0 | while IFS= read -r -d '' dylib; do
    process_dylib "$dylib"
done

echo "Finished processing all dylib files"

