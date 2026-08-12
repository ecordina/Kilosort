#!/bin/bash
#
# Test script to verify cluster setup and connectivity
#

# Load configuration
source ./config.sh 2>/dev/null || true

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "Kilosort Cluster Setup Test"
echo "========================================"
echo ""

# Test 1: SSH Connection
echo -n "Testing SSH connection to cluster... "
if ssh -o ConnectTimeout=10 -o BatchMode=yes "${CLUSTER_USER}@${CLUSTER_HOST}" "echo 'OK'" 2>/dev/null | grep -q "OK"; then
    echo -e "${GREEN}✓ PASSED${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "  - Cannot connect to ${CLUSTER_HOST}"
    echo "  - Try: ssh-copy-id ${CLUSTER_USER}@${CLUSTER_HOST}"
    exit 1
fi

# Test 2: Grid Engine commands
echo -n "Testing Grid Engine (qsub/qstat)... "
if ssh "${CLUSTER_USER}@${CLUSTER_HOST}" "source /etc/profile && which qsub > /dev/null 2>&1 && which qstat > /dev/null 2>&1"; then
    echo -e "${GREEN}✓ PASSED${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "  - qsub or qstat not found on cluster"
    echo "  - Check Grid Engine installation"
    exit 1
fi

# Test 3: Mamba/Conda
echo -n "Testing mamba/conda... "
if ssh "${CLUSTER_USER}@${CLUSTER_HOST}" "source /etc/profile && which mamba > /dev/null 2>&1 || which conda > /dev/null 2>&1"; then
    echo -e "${GREEN}✓ PASSED${NC}"
else
    echo -e "${YELLOW}⚠ WARNING${NC}"
    echo "  - mamba/conda not found"
    echo "  - You may need to load environment modules"
fi

# Test 4: Kilosort environment
echo -n "Testing kilosort environment... "
if ssh "${CLUSTER_USER}@${CLUSTER_HOST}" "source /etc/profile && eval \"\$(mamba shell hook --shell bash)\" 2>/dev/null && mamba env list | grep -q kilosort"; then
    echo -e "${GREEN}✓ PASSED${NC}"
else
    echo -e "${YELLOW}⚠ WARNING${NC}"
    echo "  - kilosort environment not found"
    echo "  - You may need to create it first"
fi

# Test 5: Directory creation
echo -n "Testing directory creation... "
if ssh "${CLUSTER_USER}@${CLUSTER_HOST}" "source /etc/profile && mkdir -p ${CLUSTER_BASE_DIR}/test && rmdir ${CLUSTER_BASE_DIR}/test"; then
    echo -e "${GREEN}✓ PASSED${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "  - Cannot create directories on cluster"
    echo "  - Check permissions"
    exit 1
fi

# Test 6: rsync
echo -n "Testing rsync... "
if which rsync > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASSED${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "  - rsync not found locally"
    echo "  - Install with: sudo apt-get install rsync"
    exit 1
fi

# Test 7: Local directories
echo -n "Testing local directories... "
if [ -d "$LOCAL_DATA_DIR" ] || mkdir -p "$LOCAL_DATA_DIR"; then
    if [ -d "$LOCAL_RESULTS_DIR" ] || mkdir -p "$LOCAL_RESULTS_DIR"; then
        echo -e "${GREEN}✓ PASSED${NC}"
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "  - Cannot create local results directory"
        exit 1
    fi
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "  - Cannot create local data directory"
    exit 1
fi

# Test 8: .brw files
echo -n "Checking for .brw files... "
brw_count=$(find "$LOCAL_DATA_DIR" -name "*.brw" -type f 2>/dev/null | wc -l)
if [ "$brw_count" -gt 0 ]; then
    echo -e "${GREEN}✓ Found $brw_count files${NC}"
else
    echo -e "${YELLOW}⚠ No .brw files found${NC}"
    echo "  - Add .brw files to $LOCAL_DATA_DIR"
fi

# Test 9: Mail command (optional)
echo -n "Testing email (optional)... "
if which mail > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Available${NC}"
else
    echo -e "${YELLOW}⚠ Not installed${NC}"
    echo "  - Email notifications will be skipped"
    echo "  - Install with: sudo apt-get install mailutils"
fi

# Test 10: Upload test
echo -n "Testing file upload... "
# Create small test file
test_file=$(mktemp)
echo "test" > "$test_file"
if rsync -q "$test_file" "${CLUSTER_USER}@${CLUSTER_HOST}:${CLUSTER_BASE_DIR}/test_upload.txt" 2>/dev/null; then
    # Cleanup
    ssh "${CLUSTER_USER}@${CLUSTER_HOST}" "source /etc/profile && rm -f ${CLUSTER_BASE_DIR}/test_upload.txt" 2>/dev/null
    rm -f "$test_file"
    echo -e "${GREEN}✓ PASSED${NC}"
else
    rm -f "$test_file"
    echo -e "${RED}✗ FAILED${NC}"
    echo "  - Cannot upload files to cluster"
    exit 1
fi

# Summary
echo ""
echo "========================================"
echo -e "${GREEN}Setup verification completed!${NC}"
echo "========================================"
echo ""
echo "Configuration:"
echo "  Cluster: ${CLUSTER_USER}@${CLUSTER_HOST}"
echo "  Base dir: ${CLUSTER_BASE_DIR}"
echo "  Email: ${EMAIL}"
echo "  CPU cores: ${CPU_CORES}"
echo "  Max concurrent: ${MAX_CONCURRENT_UPLOADS}"
echo "  .brw files: $brw_count"
echo ""

if [ "$brw_count" -gt 0 ]; then
    echo -e "${GREEN}Ready to run: ./kilosort_pipeline.sh${NC}"
else
    echo -e "${YELLOW}Add .brw files to $LOCAL_DATA_DIR first${NC}"
fi
