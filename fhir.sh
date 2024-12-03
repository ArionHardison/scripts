#!/bin/bash

# Configuration
THREADS=10
CHECKPOINT_FILE="checkpoint.txt"
LOG_FILE="url_check.log"
TEMP_DIR="temp_results"

# Create temp directory if it doesn't exist
mkdir -p "$TEMP_DIR"

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
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

    # Check if URL returns 404 or contains error text
    response=$(curl -s "$url")
    if [[ $? -eq 22 ]] || [[ $response =~ "404 File Not Found" ]] || [[ $response =~ "The file you were looking for was not found" ]]; then
        # Replace -example with -examples in URL
        new_url="${url/example.json/examples.json}"
        echo "${url}:${new_url}" >> "$CHECKPOINT_FILE"
        echo "$new_url" >> "$temp_file"
        log_message "Thread $thread_id modified: $url -> $new_url"
    else
        echo "${url}:unchanged" >> "$CHECKPOINT_FILE"
        echo "$url" >> "$temp_file"
        log_message "Thread $thread_id unchanged: $url"
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
echo "Starting URL check process at $(date)" > "$LOG_FILE"

# Create checkpoint file if it doesn't exist
touch "$CHECKPOINT_FILE"

# Process URLs
log_message "Starting URL processing with $THREADS threads"
process_urls

# Combine results
log_message "Combining results"
cat "$TEMP_DIR"/result_*.txt > "new_urls.txt"

# Replace original file
log_message "Updating original file"
mv "new_urls.txt" "urls.txt"

# Cleanup
log_message "Cleaning up temporary files"
rm -rf "$TEMP_DIR"

log_message "Process completed"

# Print summary
total_processed=$(($(wc -l < "$CHECKPOINT_FILE")))
total_modified=$(grep -c ":http" "$CHECKPOINT_FILE")
log_message "Summary: Processed $total_processed URLs, Modified $total_modified URLs"
