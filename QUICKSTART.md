# Quick Start Guide - Kilosort Cluster Pipeline

## 🚀 Quick Start (3 Steps)

### 1. Setup SSH Access
```bash
# Configure SSH key for passwordless login
ssh-copy-id your_username@front.migale.inrae.fr

# Test connection
ssh your_username@front.migale.inrae.fr
```

### 2. Prepare Your Data
```bash
# Create local directories
mkdir -p local_data local_results

# Copy your .brw files
cp /path/to/your/data/*.brw local_data/
```

### 3. Run the Pipeline
```bash
# Test setup first (recommended)
./test_setup.sh

# Process all files
./kilosort_pipeline.sh
```

That's it! The pipeline will:
- ✓ Upload files to cluster
- ✓ Process with Kilosort (8 CPU cores)
- ✓ Send email notifications
- ✓ Download results
- ✓ Clean up cluster files

---

## 📁 Files Created

### Main Scripts
- **kilosort_pipeline.sh** - Main orchestrator (run this locally)
- **kilosort_cluster.sh** - Cluster job script (runs on cluster)
- **run_kilosort.py** - Python processing script (runs on cluster)

### Configuration & Testing
- **config.sh** - Configuration file (edit settings here)
- **test_setup.sh** - Verify setup before running
- **test_single_file.sh** - Test with one file for debugging

### Documentation
- **README.md** - Complete documentation
- **QUICKSTART.md** - This file

---

## ⚙️ Customization

### Change Email Address
Edit `config.sh`:
```bash
export EMAIL="your.email@inrae.fr"
```

### Change CPU Cores
Edit `config.sh`:
```bash
export CPU_CORES=16  # Use 16 cores instead of 8
```

### Change Concurrent Uploads
Edit `config.sh`:
```bash
export MAX_CONCURRENT_UPLOADS=5  # Process 5 files at once
```

---

## 🧪 Testing Workflow

### 1. Verify Setup
```bash
./test_setup.sh
```
This checks:
- SSH connection
- Grid Engine (qsub/qstat)
- Mamba/conda environment
- Directory permissions
- File upload capability

### 2. Test Single File
```bash
./test_single_file.sh local_data/yourfile.brw
```
This will:
- Upload one file
- Submit job
- Monitor progress
- Download results to `test_results/`
- Show job log

### 3. Run Full Pipeline
```bash
./kilosort_pipeline.sh
```
Processes all .brw files in `local_data/`

---

## 📧 Email Notifications

You'll receive emails for:

**From Cluster:**
- Job start
- Job completion
- Job failure

**From Local:**
- Pipeline start (all files)
- Pipeline completion summary

---

## 📊 Monitoring

### Check Job Status
```bash
ssh your_username@front.migale.inrae.fr qstat
```

### View Job Log (while running)
```bash
ssh your_username@front.migale.inrae.fr tail -f ~/kilosort_pipeline/logs/*.log
```

### Check Results
```bash
ls -lh local_results/
```

---

## 🐛 Troubleshooting

### "Permission denied"
```bash
# Setup SSH key
ssh-copy-id your_username@front.migale.inrae.fr
```

### "qsub: command not found"
This should not happen anymore - qsub runs on cluster via SSH.
If it does, check the SSH connection:
```bash
ssh your_username@front.migale.inrae.fr which qsub
```

### Email not working
```bash
# Install mail locally (optional)
sudo apt-get install mailutils

# Email is also sent from cluster (requires cluster mail setup)
```

### Job stuck/failed
```bash
# Check specific job
ssh your_username@front.migale.inrae.fr qstat -j <JOB_ID>

# View error log
ssh your_username@front.migale.inrae.fr cat ~/kilosort_pipeline/logs/*.log
```

### No results downloaded
- Check cluster: `ssh your_username@front.migale.inrae.fr ls ~/kilosort_pipeline/results/`
- Verify COMPLETED flag exists
- Review job log for Python errors

---

## 📋 Example Session

```bash
# 1. Setup (first time only)
ssh-copy-id ecordina@front.migale.inrae.fr
mkdir -p local_data local_results

# 2. Copy data
cp /data/experiments/*.brw local_data/

# 3. Test setup
./test_setup.sh
# ✓ All tests passed

# 4. Test one file
./test_single_file.sh local_data/J7_D29.04.26_PCCTg338_175kP3_Baseline_00.brw
# ✓ Test completed, results in test_results/

# 5. Process all files
./kilosort_pipeline.sh
# Pipeline running... you'll get email updates

# 6. Check results
ls -lh local_results/
```

---

## 🎯 What Happens During Processing

1. **Local Machine:**
   - Finds all .brw files in `local_data/`
   - Uploads to cluster (max 3 at a time)
   - Submits Grid Engine job for each

2. **Cluster:**
   - Job starts with 8 CPU cores
   - Activates kilosort environment
   - Converts .brw → binary format
   - Runs Kilosort spike sorting
   - Saves results
   - Creates COMPLETED flag
   - Sends email

3. **Local Machine:**
   - Monitors job status
   - Downloads results when complete
   - Cleans up cluster files
   - Sends completion email

---

## 📦 Output Structure

```
local_results/
├── J7_D29.04.26_PCCTg338_175kP3_Baseline_00_results/
│   ├── COMPLETED                    # Timestamp
│   ├── spike_times.npy              # Spike times
│   ├── spike_clusters.npy           # Cluster IDs
│   ├── amplitudes.npy               # Amplitudes
│   ├── templates.npy                # Spike templates
│   ├── channel_positions.npy        # Probe geometry
│   ├── similar_templates.npy        # Template similarity
│   ├── data.bin                     # Preprocessed data
│   └── probe.prb                    # Probe config
└── [other files]_results/
```

---

## ⚡ Performance Tips

**Faster Processing:**
- Increase CPU cores: Edit `CPU_CORES=16` in config.sh
- Use shorter queue if available: Edit `QUEUE_NAME` in config.sh

**More Concurrent:**
- Increase `MAX_CONCURRENT_UPLOADS` if cluster has space
- Decrease if hitting storage limits

**Monitor Resources:**
```bash
ssh cluster qstat -f   # Queue status
ssh cluster qstat -j <JOB_ID>  # Job details
```

---

## 🆘 Getting Help

1. Run setup test: `./test_setup.sh`
2. Try single file: `./test_single_file.sh local_data/file.brw`
3. Check logs: `ssh cluster cat ~/kilosort_pipeline/logs/*.log`
4. Review README.md for detailed troubleshooting

---

## ✅ Checklist

- [ ] SSH key configured
- [ ] .brw files in local_data/
- [ ] Ran test_setup.sh successfully
- [ ] Tested one file with test_single_file.sh
- [ ] Reviewed config.sh settings
- [ ] Email address correct
- [ ] Ready to run kilosort_pipeline.sh

**Happy processing! 🧠⚡**
