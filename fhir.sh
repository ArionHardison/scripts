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

# Function to check if content is 404
is_404() {
    local content="$1"
    [[ "$content" =~ "HL7 - 404 File Not Found" ]]
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

    # Get the content
    response=$(curl -s "$url")
    
    # Check if it's a 404 page
    if is_404 "$response"; then
        log_message "Thread $thread_id found 404: $url"
        echo "${url}:404" >> "$CHECKPOINT_FILE"
        return
    fi

    # Create a temporary file for the response
    temp_response_file="$TEMP_DIR/response_${thread_id}.html"
    echo "$response" > "$temp_response_file"

    # Extract JSON content using a more reliable method
    json_content=$(awk '/<pre class="json"/{p=1;next} /<\/pre>/{p=0} p' "$temp_response_file" | sed 's/&lt;/</g' | sed 's/&gt;/>/g')

    if [[ -n "$json_content" ]]; then
        # Create filename from URL
        filename=$(sanitize_filename "$url")
        
        # Save JSON content to file
        echo "$json_content" > "$JSON_DIR/$filename"
        
        # Verify the file was created and has content
        if [[ -s "$JSON_DIR/$filename" ]]; then
            log_message "Thread $thread_id saved JSON to: $filename ($(wc -l < "$JSON_DIR/$filename") lines)"
            echo "${url}:saved" >> "$CHECKPOINT_FILE"
        else
            log_message "Thread $thread_id failed: Empty file created for $url"
            echo "${url}:failed" >> "$CHECKPOINT_FILE"
        fi
    else
        log_message "Thread $thread_id failed to extract JSON from: $url"
        # Debug: Save the response for inspection
        cp "$temp_response_file" "$TEMP_DIR/failed_${thread_id}_$(basename "$url").html"
        echo "${url}:failed" >> "$CHECKPOINT_FILE"
    fi

    # Cleanup temporary response file
    rm -f "$temp_response_file"

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

# Function to clean up URLs file
cleanup_urls() {
    log_message "Cleaning up URLs file - removing 404s"
    local temp_file="cleaned_urls.txt"
    while IFS=: read -r url status; do
        if [[ "$status" != "404" ]]; then
            echo "$url" >> "$temp_file"
        fi
    done < "$CHECKPOINT_FILE"
    mv "$temp_file" "urls.txt"
    log_message "URLs cleanup completed"
}

# Main execution

# Initialize log file
echo "Starting JSON extraction process at $(date)" > "$LOG_FILE"

# Create checkpoint file if it doesn't exist
touch "$CHECKPOINT_FILE"

# Process URLs
log_message "Starting URL processing with $THREADS threads"
process_urls

# Clean up URLs file
cleanup_urls

# Cleanup
log_message "Cleaning up temporary files"
rm -rf "$TEMP_DIR"

log_message "Process completed"

# Print summary
total_processed=$(($(wc -l < "$CHECKPOINT_FILE")))
total_saved=$(grep -c ":saved" "$CHECKPOINT_FILE")
total_failed=$(grep -c ":failed" "$CHECKPOINT_FILE")
total_404=$(grep -c ":404" "$CHECKPOINT_FILE")
log_message "Summary: Processed $total_processed URLs, Saved $total_saved JSONs, Failed $total_failed, 404s $total_404"
