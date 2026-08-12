# Kilosort Cluster Pipeline

Automated pipeline for processing .brw files with Kilosort on a remote cluster.

## Features

- Automated upload of .brw files to cluster
- Parallel processing with configurable CPU cores
- Email notifications at each step
- Automatic download of results
- Cleanup of cluster files to manage storage
- Batch processing with concurrency control

## Prerequisites

### Local Machine
- SSH access to front.migale.inrae.fr
- rsync installed
- mail command (optional, for local notifications)
- SSH key authentication configured (recommended)

### Cluster (front.migale.inrae.fr)
- Grid Engine (qsub/qstat) configured
- Mamba/Conda with kilosort environment
- Python packages: kilosort, spikeinterface, numpy
- mail command configured for email notifications

## Setup

### 1. Configure SSH Key Authentication (Recommended)

```bash
# Generate SSH key if you don't have one
ssh-keygen -t rsa -b 4096

# Copy to cluster
ssh-copy-id your_username@front.migale.inrae.fr

# Test connection
ssh your_username@front.migale.inrae.fr
```

### 2. Set Environment Variables

```bash
export CLUSTER_USER="your_username"  # Your cluster username
# If not set, will use current username
```

### 3. Prepare Directory Structure

```bash
# Local directories
mkdir -p local_data      # Put your .brw files here
mkdir -p local_results   # Results will be downloaded here

# Copy .brw files to local_data/
cp /path/to/your/*.brw local_data/
```

### 4. Make Scripts Executable

```bash
chmod +x kilosort_pipeline.sh
chmod +x kilosort_cluster.sh
chmod +x run_kilosort.py
```

## Usage

### Basic Usage

```bash
# Process all .brw files in local_data/
./kilosort_pipeline.sh
```

The pipeline will:
1. Upload .brw files to cluster (max 3 concurrent)
2. Submit Kilosort jobs
3. Monitor job progress
4. Download results to local_results/
5. Clean up cluster files
6. Send email notifications

### Configuration

Edit `kilosort_pipeline.sh` to customize:

```bash
EMAIL="emmanuel.cordina@inrae.fr"          # Your email
MAX_CONCURRENT_UPLOADS=3                     # Max files on cluster at once
POLL_INTERVAL=300                            # Check status every 5 minutes
```

Edit `kilosort_cluster.sh` to customize:

```bash
#$ -pe thread 8      # Number of CPU cores (8 recommended)
#$ -q long.q         # Queue name
#$ -M your@email.fr  # Email for notifications
```

### Manual Testing

To test a single file manually on the cluster:

```bash
# SSH to cluster
ssh your_username@front.migale.inrae.fr

# Submit test job
cd ~/kilosort_pipeline
qsub -v INPUT_FILE="$PWD/data/input/yourfile.brw" \
     -pe thread 8 -q long.q \
     scripts/kilosort_cluster.sh

# Check job status
qstat

# Check logs
tail -f logs/kilosort_*.log
```

## File Structure

### Local Machine
```
.
├── kilosort_pipeline.sh      # Main orchestration script
├── kilosort_cluster.sh        # Cluster job script
├── run_kilosort.py            # Python processing script
├── local_data/                # Input .brw files
│   ├── file1.brw
│   └── file2.brw
└── local_results/             # Downloaded results
    ├── file1_results/
    │   ├── spike_times.npy
    │   ├── spike_clusters.npy
    │   └── ...
    └── file2_results/
```

### Cluster
```
~/kilosort_pipeline/
├── scripts/
│   ├── kilosort_cluster.sh
│   └── run_kilosort.py
├── data/
│   ├── input/           # Uploaded .brw files
│   └── output/          # Temporary processing
├── logs/                # Job logs
└── results/             # Final results (before download)
    ├── file1_results/
    └── file2_results/
```

## Output Files

Each processed file generates a results directory containing:
- `spike_times.npy` - Spike times
- `spike_clusters.npy` - Cluster assignments
- `amplitudes.npy` - Spike amplitudes
- `templates.npy` - Spike templates
- `channel_positions.npy` - Probe geometry
- `similar_templates.npy` - Template similarity matrix
- `data.bin` - Preprocessed data (if save_preprocessed_copy=True)
- `probe.prb` - Probe configuration
- `COMPLETED` - Completion timestamp

## Email Notifications

You will receive emails for:
- Pipeline start (local)
- Job submission (cluster)
- Job start (cluster)
- Job completion/failure (cluster)
- Pipeline completion (local)

## Troubleshooting

### "qsub: command not found"
- qsub must run on cluster, not locally
- Ensure SSH commands are properly formatted
- Check the submit_job() function

### "Permission denied" when connecting
- Configure SSH key authentication
- Check ~/.ssh/config for connection settings

### Jobs not starting
- Check queue availability: `ssh cluster qstat -f`
- Verify cluster resource limits
- Check logs in ~/kilosort_pipeline/logs/

### Results not downloading
- Ensure COMPLETED flag is created
- Check cluster disk space
- Verify result directory permissions

### Email not working
- Install mail command: `sudo apt-get install mailutils`
- Configure postfix/sendmail
- Check spam folder

### Python errors
- Ensure kilosort environment is activated
- Check Python package versions
- Review logs for specific errors

## Performance Tips

1. **Adjust CPU cores**: More cores = faster processing
   - Edit `#$ -pe thread 8` in kilosort_cluster.sh
   - Match with `--n-jobs` in run_kilosort.py

2. **Optimize concurrency**: 
   - Increase MAX_CONCURRENT_UPLOADS if cluster has space
   - Decrease if hitting storage limits

3. **Queue selection**:
   - Use `long.q` for long-running jobs
   - Check available queues: `qconf -sql`

4. **Monitor resources**:
   - `ssh cluster qstat -j <job_id>` - Job details
   - `ssh cluster qstat -f` - Queue status

## Advanced Usage

### Process specific files only

```bash
# Edit kilosort_pipeline.sh, modify the find command:
brw_files=($(find "$LOCAL_DATA_DIR" -name "J7_*.brw" -type f))
```

### Change Kilosort parameters

Edit `run_kilosort.py`, modify the settings dictionary:

```python
settings = {
    'fs': fs,
    'n_chan_bin': c,
    'Th_universal': 9,    # Detection threshold
    'Th_learned': 8,      # Learning threshold
    'nt': 61,             # Waveform samples
}
```

### Custom output location

```bash
# In kilosort_cluster.sh
OUTPUT_DIR="custom/path/${BASENAME}"
```

## Support

For issues:
1. Check logs in `logs/` directory
2. Review cluster logs: `~/kilosort_pipeline/logs/`
3. Test SSH connection and commands manually
4. Verify Kilosort environment on cluster

## License

Internal use for INRAE research.
