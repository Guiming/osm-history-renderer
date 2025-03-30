#!/bin/bash

# Directory containing .osh.pbf files
INPUT_DIR="/mnt/externalWD/Ubuntu/osm_data"
# OSM History Importer command
IMPORTER="./osm-history-importer"
# Database connection string
DSN="host=130.253.215.41 dbname='osm_history_planet' port=5432 user=postgres password='admin'"
# Table prefix
PREFIX="hist_planet_"

# Check if directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Directory $INPUT_DIR does not exist."
    exit 1
fi

# Find and sort files by size (largest first)
FILES=$(find "$INPUT_DIR" -maxdepth 1 -type f -name "*.osh.pbf" -printf "%s %p\n" | sort -nr | awk '{print $2}')

# Check if there are any matching files
if [ -z "$FILES" ]; then
    echo "No .osh.pbf files found in $INPUT_DIR"
    exit 1
fi

# Process files in sorted order
for file in $FILES; do
    echo "Processing file: $file"

    # Execute the importer command
    $IMPORTER --nodestore sparse --dsn "$DSN" -P "$PREFIX" "$file"

    # Check exit status of the command
    if [ $? -ne 0 ]; then
        echo "Error processing $file"
        exit 1
    fi
    echo "Done processing file: $file"
done

echo "All files processed successfully."

