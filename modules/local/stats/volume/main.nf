process STATS_VOLUME {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilus:2.1.0"

    input:
    tuple val(meta), path(rois)

    output:
    tuple val(meta), path("*_volumes.json")       , emit: mqc
    path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_volumes" : "volumes"
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    for f in $rois; do 
        name=\$(basename "\$f" .nii.gz)
        vol=\$(fslstats "\$f" -V | awk '{print \$2/1000}')
        echo "{\\"\$name\\": \$vol}"
    done | jq -s 'add' > ${prefix}__${suffix}.json


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fsl: \$(flirt -version 2>&1 | sed -E 's/.*version ([0-9.]+).*/\\1/')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_stats" : "stats"
    """
    set +e
    function handle_code () {
    local code=\$?
    ignore=( 1 )
    [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }
    trap 'handle_code' ERR

    fslstats -h
    touch ${prefix}__${suffix}.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fsl: \$(flirt -version 2>&1 | sed -E 's/.*version ([0-9.]+).*/\\1/')
    END_VERSIONS
    """
}
