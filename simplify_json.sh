#!/bin/bash

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    echo "Install it using: brew install jq"
    exit 1
fi

# Check if at least one file is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <json_file1> [json_file2 ...]"
    exit 1
fi

# Process each JSON file
for file in "$@"; do
    # Check if file exists
    if [ ! -f "$file" ]; then
        echo "Error: File '$file' not found."
        continue
    fi
    
    echo "Processing $file..."
    
    # Create a temporary file
    temp_file=$(mktemp)
    
    # Transform the JSON
    # This approach recursively processes all levels of the JSON structure
    jq '
    # Define a recursive function to process objects
    def simplify_object:
      # For each key-value pair in the object
      to_entries | map(
        # Keep the key the same
        .key as $key |
        # Process the value based on its structure
        if .value | type == "object" and has("$value") then
          # If value is an object with "$value", replace it with just the "$value"
          {key: $key, value: .value["$value"]}
        elif .value | type == "object" then
          # If value is an object without "$value", recursively process it
          {key: $key, value: (.value | simplify_object)}
        elif .value | type == "array" then
          # If value is an array, recursively process each item
          {key: $key, value: (.value | map(if type == "object" then simplify_object else . end))}
        else
          # Otherwise keep the key-value pair as is
          {key: $key, value: .value}
        end
      ) | from_entries;

    # Apply the function to the entire JSON
    if type == "object" then simplify_object
    elif type == "array" then map(if type == "object" then simplify_object else . end)
    else .
    end
    ' "$file" > "$temp_file"
    
    # Check if jq command succeeded
    if [ $? -ne 0 ]; then
        echo "Error: Failed to process '$file'."
        rm "$temp_file"
        continue
    fi
    
    # Replace the original file with the processed one
    mv "$temp_file" "$file"
    
    echo "Successfully simplified $file"
done

echo "All files processed."