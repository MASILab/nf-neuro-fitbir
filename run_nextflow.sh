nextflow_dir="/fs5/p_masi/fitbir/example_datasets/example_nextflow"
for bids_dir in $nextflow_dir/site-*; do
    devcontainer exec --workspace-folder . --config .devcontainer/gpu/devcontainer.json nextflow run main.nf --input $bids_dir -profile docker -resume
done
