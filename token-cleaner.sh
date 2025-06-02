#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RENAME_CSV="$SCRIPT_DIR/rename-scheme.csv"
COLOR_CSV="$SCRIPT_DIR/tag-scheme.csv"
TARGET_DIR="$SCRIPT_DIR/design-tokens"

# Function to look up new name from CSV
get_new_name() {
  local original_name="$1"
  grep -F "$original_name" "$RENAME_CSV" | head -n1 | awk -F',' '{gsub(/\r/, "", $2); gsub(/^ +| +$/, "", $2); print $2}'
}

# Function to look up tag color from CSV
get_tag_color() {
  local file_name="$1"
  grep -F "$file_name" "$COLOR_CSV" | head -n1 | awk -F',' '{gsub(/\r/, "", $2); gsub(/^ +| +$/, "", $2); print $2}'
}

# Assign macOS color tag using AppleScript and label index
assign_tag() {
  local filepath="$1"
  local tagname="$2"
  local label_index=0

  case "$(echo "$tagname" | tr '[:upper:]' '[:lower:]' | xargs)" in
    orange) label_index=1 ;;
    red)    label_index=2 ;;
    yellow) label_index=3 ;;
    blue)   label_index=4 ;;
    purple) label_index=5 ;;
    green)  label_index=6 ;;
    gray)   label_index=7 ;;
    *)      label_index=0 ;;  # fallback to no color
  esac

  /usr/bin/osascript <<EOF
set filePath to POSIX file "$(echo "$filepath" | sed 's/"/\\"/g')" as alias
tell application "Finder"
  try
    set label index of filePath to $label_index
  end try
end tell
EOF
}

#remove unwanted files
cleanup() {
  for file in "$TARGET_DIR"/❌*; do
    [ -e "$file" ] || continue
    echo "🗑️ Moving to Trash: $(basename "$file")"
    /usr/bin/osascript <<EOF
tell application "Finder"
  move (POSIX file "$file" as alias) to trash
end tell
EOF
  done
}

# Clean up JSON keys
sanitize_json_keys() {
  local MAPPING_CSV="$SCRIPT_DIR/value-mapping.csv"

  for json_file in "$TARGET_DIR"/typography.json "$TARGET_DIR"/effects.json; do
    [ -f "$json_file" ] || continue

    node <<EOF
const fs = require("fs");
const path = require("path");
const csvPath = "${MAPPING_CSV}";
const filePath = "${json_file}";

// Load CSV mappings
const csvData = fs.readFileSync(csvPath, "utf8").split(/\r?\n/).filter(Boolean);
const mappings = {};
for (let i = 1; i < csvData.length; i++) {
  const [key, from, to] = csvData[i].split(',');
  if (!mappings[key]) mappings[key] = {};
  mappings[key][from] = to;
}

// Clean a key name: remove leading dot, trim, strip " (xyz)"
function cleanKeyName(key) {
  return key
    .replace(/^\./, '')                // remove leading dot
    .replace(/ \([^)]*\)/g, '')        // remove " (stuff)"
    .trim();
}

// Recursively clean and transform keys + values
function process(obj) {
  const result = {};
  for (const key in obj) {
    const cleanKey = cleanKeyName(key);
    const value = obj[key];

    if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
      result[cleanKey] = process(value);
    } else {
      if (mappings[cleanKey] && mappings[cleanKey][value]) {
        result[cleanKey] = mappings[cleanKey][value];
      } else {
        result[cleanKey] = value;
      }
    }
  }
  return result;
}

const data = JSON.parse(fs.readFileSync(filePath, "utf8"));
const cleaned = process(data);
fs.writeFileSync(filePath, JSON.stringify(cleaned, null, 2));
console.log("✅ Sanitized:", path.basename(filePath));
EOF
  done
}


# Process each file in design-tokens
for file_path in "$TARGET_DIR"/*; do
  [ -f "$file_path" ] || continue
  file_name="$(basename "$file_path")"
  dir_name="$(dirname "$file_path")"

  # Rename if applicable
  new_name="$(get_new_name "$file_name")"
  if [ -n "$new_name" ]; then
    mv "$file_path" "$dir_name/$new_name"
    echo "✅ Successfully Renamed: $file_name ➜ $new_name"
    file_path="$dir_name/$new_name"
    file_name="$new_name"
  fi

  # Tag based on color CSV
  tag_color="$(get_tag_color "$file_name")"
  if [ -n "$tag_color" ]; then
    assign_tag "$file_path" "$tag_color"
    echo "✅ Successfully Tagged: $file_name [Tag: $tag_color]"
  fi
done

cleanup
sanitize_json_keys