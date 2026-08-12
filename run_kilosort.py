#!/usr/bin/env python
"""
Kilosort processing script with multi-threading support
"""
import os
import sys
import argparse
from pathlib import Path
import numpy as np
from kilosort import run_kilosort, io
from spikeinterface.extractors.neoextractors import BiocamRecordingExtractor
import logging

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def process_brw_file(input_file, output_dir='./data/output', n_jobs=None):
    """
    Process a single .brw file with Kilosort
    
    Parameters:
    -----------
    input_file : str
        Path to input .brw file
    output_dir : str
        Directory for output files
    n_jobs : int or None
        Number of parallel jobs (defaults to number of available cores)
    """
    logger.info(f"Starting processing of {input_file}")
    
    # Set number of jobs
    if n_jobs is None:
        n_jobs = int(os.environ.get('NSLOTS', os.cpu_count()))
    logger.info(f"Using {n_jobs} parallel jobs")
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Load recording
    logger.info("Loading BiocamRecordingExtractor...")
    recording = BiocamRecordingExtractor(input_file)
    
    # Convert to binary format
    logger.info("Converting to binary format...")
    dtype = np.int16
    filename, N, c, s, fs, probe_path = io.spikeinterface_to_binary(
        recording,
        output_dir,
        data_name='data.bin',
        dtype=dtype,
        chunksize=30_000,
        export_probe=True,
        probe_name='probe.prb',
    )
    
    logger.info(f"Binary file created: {filename}")
    logger.info(f"Sampling rate: {fs} Hz")
    logger.info(f"Number of channels: {c}")
    
    # Configure Kilosort settings
    settings = {
        'fs': fs,
        'n_chan_bin': c,
        'nblocks': 1,  # Adjust based on your data size
        'Th_universal': 6.5,  # Universal threshold for spike detection
        'Th_learned': 6.5,    # Learned threshold
        'nt': 61,           # Number of samples per waveform
    }
    
    # Load probe configuration
    assert probe_path is not None, 'No probe information exported by SpikeInterface'
    probe = io.load_probe(probe_path)
    logger.info(f"Probe loaded: {probe['n_chan']} channels")
    
    # Run Kilosort
    logger.info("Running Kilosort spike sorting...")
    ops, st, clu, tF, Wall, similar_templates, is_ref, \
    est_contam_rate, kept_spikes = run_kilosort(
        settings=settings,
        probe=probe,
        filename=filename,
        data_dir=output_dir,
        results_dir=output_dir,
        invert_sign=False,
        save_preprocessed_copy=True,
    )
    
    logger.info(f"Spike sorting completed!")
    logger.info(f"Total spikes detected: {len(st)}")
    logger.info(f"Number of units: {len(np.unique(clu))}")
    logger.info(f"Results saved to: {output_dir}")
    
    return ops, st, clu

def main():
    parser = argparse.ArgumentParser(
        description='Run Kilosort on BioCam .brw files'
    )
    parser.add_argument(
        'input_file',
        help='Path to input .brw file'
    )
    parser.add_argument(
        '--output-dir',
        default='./data/output',
        help='Output directory (default: ./data/output)'
    )
    parser.add_argument(
        '--n-jobs',
        type=int,
        default=None,
        help='Number of parallel jobs (default: use all available cores)'
    )
    
    args = parser.parse_args()
    
    # Check input file exists
    if not os.path.exists(args.input_file):
        logger.error(f"Input file not found: {args.input_file}")
        sys.exit(1)
    
    try:
        # Process the file
        process_brw_file(
            args.input_file,
            args.output_dir,
            args.n_jobs
        )
        logger.info("Processing completed successfully!")
        
    except Exception as e:
        logger.error(f"Error during processing: {str(e)}", exc_info=True)
        sys.exit(1)

if __name__ == '__main__':
    main()
