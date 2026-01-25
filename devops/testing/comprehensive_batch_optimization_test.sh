#!/bin/bash

# Comprehensive Batch Size Optimization Test
# This script runs multiple iterations with different batch sizes to find optimal performance

set -e

# Test configurations
BATCH_SIZES=(1000 3000 5000 8000)
RESULTS_FILE="/Users/jhf/ssb/statbus/tmp/batch_optimization_results.csv"

# Initialize results file
echo "batch_size,dataset,analysis_rows_per_sec,processing_rows_per_sec,performance_ratio,total_updates,updates_per_row" > "$RESULTS_FILE"

# Function to run import and measure performance
run_import_test() {
    local batch_size=$1
    echo "=== Testing batch size: $batch_size ==="
    
    # Step 1: Setup import data and definitions  
    echo "Setting up import for Norway dataset..."
    USER_EMAIL=jorgen@veridit.no ./samples/norway/brreg/brreg-import-selection.sh
    
    # Step 2: Modify batch sizes for this test
    echo "Updating processing batch size to $batch_size..."
    echo "UPDATE import_definition SET processing_batch_size = $batch_size WHERE slug LIKE 'brreg_%';" | ./devops/manage-statbus.sh psql
    
    # Step 3: Reset database activity counters
    echo "SELECT pg_stat_reset();" | ./devops/manage-statbus.sh psql > /dev/null
    
    # Step 4: Run import jobs and wait for completion
    echo "Starting import jobs..."
    start_time=$(date +%s)
    
    # Monitor job completion
    while true; do
        job_count=$(echo "SELECT COUNT(*) FROM import_job WHERE state NOT IN ('finished', 'failed');" | ./devops/manage-statbus.sh psql -t | tr -d ' ')
        if [ "$job_count" = "0" ]; then
            break
        fi
        echo "Jobs still running... ($job_count remaining)"
        sleep 10
    done
    
    end_time=$(date +%s)
    total_time=$((end_time - start_time))
    echo "Import completed in $total_time seconds"
    
    # Step 5: Collect performance metrics
    echo "Collecting performance metrics..."
    
    # Get job performance data
    job_metrics=$(echo "SELECT 
        ROUND(AVG(analysis_rows_per_sec)::numeric, 2) as avg_analysis_rows_per_sec,
        ROUND(AVG(import_rows_per_sec)::numeric, 2) as avg_processing_rows_per_sec,
        ROUND((AVG(import_rows_per_sec) / AVG(analysis_rows_per_sec))::numeric, 3) as performance_ratio
    FROM import_job 
    WHERE slug LIKE '%_2026_selection';" | ./devops/manage-statbus.sh psql -t | tr -s ' ')
    
    # Get database activity data for the most active table
    update_metrics=$(echo "SELECT 
        n_tup_upd as total_updates,
        ROUND((n_tup_upd::numeric / GREATEST(n_live_tup, 1))::numeric, 2) as updates_per_row
    FROM pg_stat_user_tables 
    WHERE schemaname = 'public' AND relname LIKE '%underenhet%data%'
    ORDER BY n_tup_upd DESC LIMIT 1;" | ./devops/manage-statbus.sh psql -t | tr -s ' ')
    
    # Parse metrics
    analysis_speed=$(echo $job_metrics | cut -d'|' -f1 | tr -d ' ')
    processing_speed=$(echo $job_metrics | cut -d'|' -f2 | tr -d ' ') 
    ratio=$(echo $job_metrics | cut -d'|' -f3 | tr -d ' ')
    total_updates=$(echo $update_metrics | cut -d'|' -f1 | tr -d ' ')
    updates_per_row=$(echo $update_metrics | cut -d'|' -f2 | tr -d ' ')
    
    # Record results
    echo "$batch_size,underenhet,$analysis_speed,$processing_speed,$ratio,$total_updates,$updates_per_row" >> "$RESULTS_FILE"
    
    echo "Results: Analysis=$analysis_speed rows/sec, Processing=$processing_speed rows/sec, Ratio=$ratio, Updates/row=$updates_per_row"
    
    # Step 6: Clean up for next test
    echo "Cleaning up for next test..."
    ./devops/manage-statbus.sh recreate-database > /dev/null 2>&1
    sleep 5
}

# Main test loop
echo "Starting comprehensive batch size optimization test..."
echo "Testing batch sizes: ${BATCH_SIZES[*]}"

for batch_size in "${BATCH_SIZES[@]}"; do
    run_import_test $batch_size
done

# Display final results
echo ""
echo "=== FINAL RESULTS ==="
column -t -s ',' "$RESULTS_FILE"

echo ""
echo "Best performing batch size:"
tail -n +2 "$RESULTS_FILE" | sort -t',' -k5 -nr | head -n1 | while IFS=',' read batch_size dataset analysis processing ratio updates updates_per_row; do
    echo "Batch Size: $batch_size"
    echo "Performance Ratio: $ratio"
    echo "Processing Speed: $processing rows/sec"
    echo "Updates per Row: $updates_per_row"
done