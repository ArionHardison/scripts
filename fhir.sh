#!/bin/bash

# Configuration
THREADS=10
CHECKPOINT_FILE="checkpoint.txt"
LOG_FILE="url_check.log"
TEMP_DIR="temp_results"
JSON_DIR="json_files"

# Create directories if they don't exist
mkdir -p "$TEMP_DIR"
mkdir -p "$JSON_DIR"

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to sanitize filename
sanitize_filename() {
    local url="$1"
    # Extract the resource name from URL and add .json extension
    echo "$url" | sed 's|.*/\([^/]*\)\.json\.html|\1.json|'
}

# Function to process a single URL
process_url() {
    local url="$1"
    local thread_id="$2"
    local temp_file="$TEMP_DIR/result_${thread_id}.txt"

    # Skip if URL has already been processed (check checkpoint)
    if grep -q "^${url}:" "$CHECKPOINT_FILE" 2>/dev/null; then
        return
    fi

    # Log start of processing
    log_message "Thread $thread_id processing: $url"

    # Get the content and extract JSON
    response=$(curl -s "$url")
    if [[ $response =~ \<pre[^>]*class=\"json\"[^>]*\>(.*)\</pre\> ]]; then
        json_content="${BASH_REMATCH[1]}"
        
        # Create filename from URL
        filename=$(sanitize_filename "$url")
        
        # Save JSON content to file
        echo "$json_content" > "$JSON_DIR/$filename"
        
        log_message "Thread $thread_id saved JSON to: $filename"
        echo "${url}:saved" >> "$CHECKPOINT_FILE"
    else
        log_message "Thread $thread_id failed to extract JSON from: $url"
        echo "${url}:failed" >> "$CHECKPOINT_FILE"
    fi

    # Update progress
    processed=$(($(wc -l < "$CHECKPOINT_FILE")))
    total=$(($(wc -l < "urls.txt")))
    log_message "Progress: $processed/$total URLs processed"
}

# Function to process URLs in parallel
process_urls() {
    local thread_count=0
    local thread_id=0

    while IFS= read -r url; do
        # Skip if URL has already been processed
        if grep -q "^${url}:" "$CHECKPOINT_FILE" 2>/dev/null; then
            continue
        fi

        # Wait if we've reached max threads
        if [ $thread_count -ge $THREADS ]; then
            wait
            thread_count=0
        fi

        # Process URL in background
        process_url "$url" "$thread_id" &
        
        thread_count=$((thread_count + 1))
        thread_id=$((thread_id + 1))
    done < "urls.txt"

    # Wait for remaining threads to finish
    wait
}

# Main execution

# Initialize log file
echo "Starting JSON extraction process at $(date)" > "$LOG_FILE"

# Create checkpoint file if it doesn't exist
touch "$CHECKPOINT_FILE"

# Process URLs
log_message "Starting URL processing with $THREADS threads"
process_urls

# Cleanup
log_message "Cleaning up temporary files"
rm -rf "$TEMP_DIR"

log_message "Process completed"

# Print summary
total_processed=$(($(wc -l < "$CHECKPOINT_FILE")))
total_saved=$(grep -c ":saved" "$CHECKPOINT_FILE")
total_failed=$(grep -c ":failed" "$CHECKPOINT_FILE")
log_message "Summary: Processed $total_processed URLs, Saved $total_saved JSONs, Failed $total_failed"
