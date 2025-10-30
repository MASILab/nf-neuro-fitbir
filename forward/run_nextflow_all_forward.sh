#!/bin/bash
set -e

# skip_list=("site-0e87e7" "site-2ef163" "site-2f8703" "site-52ca0d" "site-534660" "site-6af6b3" "site-d90880" "site-e4d3cf")
# Done: until site-57869d
skip_list=("site-6af6b3")
skip_until="site-534660"

nextflow_dir="/fs5/p_masi/fitbir/nextflow"
skip_flag=1
for bids_dir in $(ls -d $nextflow_dir/site-*); do
    if [[ $(basename $bids_dir) == $skip_until ]]; then
        skip_flag=0
    fi
    if [[ $skip_flag == 1 ]]; then 
        echo "Skipping $bids_dir..."
        continue
    fi
    if [[ " ${skip_list[@]} " =~ " $(basename $bids_dir) " ]]; then
        echo "Skipping $bids_dir..."
        continue
    fi
    #devcontainer exec --workspace-folder . --config .devcontainer/gpu/devcontainer.json nextflow run main.nf --input $bids_dir -profile docker -resume
    echo "Running on $bids_dir..."
    nextflow run ../main.nf --input $bids_dir -profile docker -resume
done
