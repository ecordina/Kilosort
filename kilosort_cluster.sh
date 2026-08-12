#!/bin/bash
#$ -cwd
#$ -N kilosort
#$ -pe thread 8
#$ -q long.q,infinit.q,highmem.q,bigmem.q,maiage.q
#$ -M emmanuel.cordina@inrae.fr
#$ -m bes
#$ -j y
#$ -o logs/$JOB_NAME.$JOB_ID.log

# Email notification function
send_email() {
    local subject="$1"
    local message="$2"
    echo "$message" | mail -s "$subject" emmanuel.cordina@inrae.fr 2>/dev/null || true
}

# Trap errors and send notification
trap 'send_email "Kilosort Job Failed - $JOB_NAME.$JOB_ID" "Job failed at $(date). Check log file: logs/$JOB_NAME.$JOB_ID.log"' ERR

# Start notification
send_email "Kilosort Job Started - $JOB_NAME.$JOB_ID" "Job started at $(date) on $(hostname) with $NSLOTS cores. Processing: $INPUT_FILE"

# Verify INPUT_FILE is set
if [ -z "$INPUT_FILE" ]; then
    echo "ERROR: INPUT_FILE not set"
    send_email "Kilosort Job Failed - $JOB_NAME.$JOB_ID" "INPUT_FILE variable not set"
    exit 1
fi

# Verify input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: Input file not found: $INPUT_FILE"
    send_email "Kilosort Job Failed - $JOB_NAME.$JOB_ID" "Input file not found: $INPUT_FILE"
    exit 1
fi

# Extract basename for output directory
BASENAME=$(basename "${INPUT_FILE}" .brw)
OUTPUT_DIR="data/output/${BASENAME}"
RESULT_DIR="results/${BASENAME}_results"

# Create necessary directories
mkdir -p logs
mkdir -p "$OUTPUT_DIR"
mkdir -p "$RESULT_DIR"

# Set number of threads for various libraries
export OMP_NUM_THREADS=$NSLOTS
export MKL_NUM_THREADS=$NSLOTS
export NUMBA_NUM_THREADS=$NSLOTS
export OPENBLAS_NUM_THREADS=$NSLOTS

# Activate environment
eval "$(mamba shell hook --shell bash)"
mamba activate kilosort

# Run Kilosort
echo "Starting Kilosort processing at $(date)"
echo "Input file: $INPUT_FILE"
echo "Output directory: $OUTPUT_DIR"
echo "Using $NSLOTS cores"

cd ~/work/kilosort_pipeline
python scripts/run_kilosort.py "$INPUT_FILE" --output-dir "$OUTPUT_DIR" --n-jobs $NSLOTS

# Check if processing was successful
if [ $? -eq 0 ]; then
    echo "Packaging results at $(date)"
    
    # Move results to final location
    mv "$OUTPUT_DIR"/* "$RESULT_DIR/" 2>/dev/null || true
    
    # Create completion flag
    touch "$RESULT_DIR/COMPLETED"
    echo "$(date)" > "$RESULT_DIR/COMPLETED"
    
    send_email "Kilosort Job Completed - $JOB_NAME.$JOB_ID" "Job completed successfully at $(date). Results in: $RESULT_DIR. File: $(basename $INPUT_FILE)"
    echo "Processing completed successfully"
else
    send_email "Kilosort Job Failed - $JOB_NAME.$JOB_ID" "Python script failed for $INPUT_FILE. Check logs."
    exit 1
fi
