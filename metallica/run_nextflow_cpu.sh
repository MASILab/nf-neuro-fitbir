#!/bin/bash
set -e

nextflow_dir="/fs5/p_masi/fitbir/nextflow"
for bids_dir in $nextflow_dir/site-{17,20,30,35}; do
    echo $bids_dir
    #devcontainer exec --workspace-folder . --config .devcontainer/gpu/devcontainer.json nextflow run main.nf --input $bids_dir -profile docker -resume
    NXF_APPTAINER_CACHEDIR="/home-local/saundam1/singularity" nextflow run /workspaces/nf-neuro-fitbir/main.nf --input $bids_dir -profile apptainer -resume
done
