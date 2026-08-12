#!/bin/bash
#
# Kilosort Pipeline Configuration
# Source this file or edit values directly
#

# Cluster Configuration
export CLUSTER_HOST="front.migale.inrae.fr"
export CLUSTER_USER="ecordina"
export CLUSTER_BASE_DIR="/home/ecordina/work/kilosort_pipeline"

# Email Configuration
export EMAIL="emmanuel.cordina@inrae.fr"

# Local Directories
export LOCAL_DATA_DIR="/mnt/c/Users/Emman/Desktop/work/These/Data/Aurelie/MEA"
export LOCAL_RESULTS_DIR="/mnt/c/Users/Emman/Desktop/work/These/Data/Aurelie/MEA/results"

# Processing Configuration
export MAX_CONCURRENT_UPLOADS=3    # Max files on cluster simultaneously
export POLL_INTERVAL=100           # Status check interval (seconds)
export CPU_CORES=8                 # Number of CPU cores per job

# Grid Engine Configuration
export QUEUE_NAME="long.q,infinit.q,highmem.q,bigmem.q,maiage.q"         # Queue to submit to
export THREAD_PE="thread"          # Parallel environment name

# Advanced Settings
export UPLOAD_TIMEOUT=7200         # Upload timeout (2 hours)
export DOWNLOAD_TIMEOUT=3600       # Download timeout (1 hour)
export MAX_RETRY_ATTEMPTS=5        # Max attempts to download results
export CLEANUP_AFTER_DOWNLOAD=true # Delete cluster files after download

# Kilosort Settings (applied in run_kilosort.py)
export KS_TH_UNIVERSAL=2          # Universal detection threshold
export KS_TH_LEARNED=2          # Learned threshold
export KS_NT=61                   # Samples per waveform
export KS_SAVE_PREPROCESSED=true  # Save preprocessed data

# Logging
export LOG_LEVEL="INFO"           # DEBUG, INFO, WARNING, ERROR
export KEEP_LOGS_DAYS=30          # Days to keep log files
