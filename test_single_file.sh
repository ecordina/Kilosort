#!/bin/bash
#
# Test script for processing a single .brw file
# Usage: ./test_single_file.sh <path_to_brw_file>
#

# Load configuration
source ./config.sh 2>/dev/null || true

CLUSTER_HOST="${CLUSTER_HOST:-front.migale.inrae.fr}"
CLUSTER_USER="${CLUSTER_USER:-$USER}"
EMAIL="${EMAIL:-emmanuel.cordina@inrae.fr}"
CLUSTER_BASE_DIR="${CLUSTER_BASE_DIR:-/home/ecordina/work/kilosort_pipeline}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ $# -eq 0 ]; then
    echo "Usage: $0 <path_to_brw_file>"
    echo "Example: $0 ./local_data/myfile.brw"
    exit 1
fi

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}Error: File not found: $INPUT_FILE${NC}"
    exit 1
fi

FILENAME=$(basename "$INPUT_FILE")
BASENAME="${FILENAME%.brw}"

echo "========================================"
echo "Single File Test"
echo "========================================"
echo "File: $FILENAME"
echo "Cluster: ${CLUSTER_USER}@${CLUSTER_HOST}"
echo "========================================"
echo ""

# Step 1: Setup
echo -e "${YELLOW}[1/6]${NC} Setting up cluster environment..."
ssh "${CLUSTER_USER}@${CLUSTER_HOST}" "mkdir -p ${CLUSTER_BASE_DIR}/{data/input,data/output,logs,results,scripts}"
echo -e "${GREEN}✓ Done${NC}"
echo ""

# Step 2: Copy scripts
echo -e "${YELLOW}[2/6]${NC} Copying processing scripts..."
scp -q kilosort_cluster.sh "${CLUSTER_USER}@${CLUSTER_HOST}:${CLUSTER_BASE_DIR}/scripts/"
scp -q run_kilosort.py "${CLUSTER_USER}@${CLUSTER_HOST}:${CLUSTER_BASE_DIR}/scripts/"
echo -e "${GREEN}✓ Done${NC}"
echo ""

# Step 3: Upload file
echo -e "${YELLOW}[3/6]${NC} Uploading $FILENAME..."
rsync -avz --progress "$INPUT_FILE" "${CLUSTER_USER}@${CLUSTER_HOST}:${CLUSTER_BASE_DIR}/data/input/"
echo -e "${GREEN}✓ Done${NC}"
echo ""

# Step 4: Submit job
echo -e "${YELLOW}[4/6]${NC} Submitting job..."
JOB_OUTPUT=$(ssh "${CLUSTER_USER}@${CLUSTER_HOST}" \
    "source /etc/profile && \
    cd ${CLUSTER_BASE_DIR} && \
    qsub -v INPUT_FILE='${CLUSTER_BASE_DIR}/data/input/${FILENAME}' \
         -N 'kilosort_test_${BASENAME}' \
         -pe thread 8 \
         -q highmem.q \
         -M ${EMAIL} \
         -m bes \
         -j y \
         -o logs/kilosort_test_${BASENAME}.log \
         scripts/kilosort_cluster.sh")

echo "qsub output: $JOB_OUTPUT"

JOB_ID=$(echo "$JOB_OUTPUT" | grep "Your job" | sed -E 's/Your job ([0-9]+).*/\1/')
if [ -n "$JOB_ID" ]; then
    echo -e "${GREEN}✓ Job submitted: $JOB_ID${NC}"
else
    echo -e "${RED}✗ Failed to submit job${NC}"
    exit 1
fi
echo ""

# Step 5: Monitor
echo -e "${YELLOW}[5/6]${NC} Monitoring job (Ctrl+C to stop monitoring, job will continue)..."
echo "Job ID: $JOB_ID"
echo "Log file: logs/kilosort_test_${BASENAME}.$JOB_ID.log"
echo ""

while true; do
    # Check if job is still running
    if ssh "${CLUSTER_USER}@${CLUSTER_HOST}" "source /etc/profile && qstat -j $JOB_ID 2>&1" | grep -q "job_number"; then
        echo -n "."
        sleep 30
    else
        echo ""
        echo -e "${GREEN}✓ Job completed${NC}"
        break
    fi
done
echo ""

# Wait for results
sleep 10

# Step 6: Download results
echo -e "${YELLOW}[6/6]${NC} Downloading results..."
RESULT_DIR="${BASENAME}_results"

if ssh "${CLUSTER_USER}@${CLUSTER_HOST}" "[ -f ${CLUSTER_BASE_DIR}/results/${RESULT_DIR}/COMPLETED ]"; then
    mkdir -p "./test_results/${RESULT_DIR}"
    rsync -avz --progress "${CLUSTER_USER}@${CLUSTER_HOST}:${CLUSTER_BASE_DIR}/results/${RESULT_DIR}/" "./test_results/${RESULT_DIR}/"
    echo -e "${GREEN}✓ Results downloaded to: ./test_results/${RESULT_DIR}${NC}"
else
    echo -e "${RED}✗ Results not found or job failed${NC}"
    echo "Check log file:"
    echo "  ssh ${CLUSTER_USER}@${CLUSTER_HOST} 'cat ${CLUSTER_BASE_DIR}/logs/kilosort_test_${BASENAME}.$JOB_ID.log'"
    exit 1
fi
echo ""

# View log
echo "========================================"
echo "Job Log (last 50 lines):"
echo "========================================"
ssh "${CLUSTER_USER}@${CLUSTER_HOST}" "tail -50 ${CLUSTER_BASE_DIR}/logs/kilosort_test_${BASENAME}.$JOB_ID.log"
echo ""

echo "========================================"
echo -e "${GREEN}Test completed successfully!${NC}"
echo "========================================"
echo "Results: ./test_results/${RESULT_DIR}"
echo ""
echo "To cleanup cluster:"
echo "  ssh ${CLUSTER_USER}@${CLUSTER_HOST} 'rm -rf ${CLUSTER_BASE_DIR}/data/input/${FILENAME} ${CLUSTER_BASE_DIR}/results/${RESULT_DIR}'"
