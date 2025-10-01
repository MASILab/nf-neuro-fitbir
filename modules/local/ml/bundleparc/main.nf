process ML_BUNDLEPARC {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.0_gpu"

    input:
    tuple val(meta), path(fodf)

    output:
    tuple val(meta), path("*_bundleparc/*.nii.gz")  , emit: bundles
    path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    def out_prefix = task.ext.out_prefix ? "--out_prefix " + task.ext.out_prefix : ""
    def half_precision = task.ext.half_precision ? "--half_precision" : ""
    def bundles = task.ext.bundles ? "--bundles " + task.ext.bundles : ""
    def checkpoint = task.ext.checkpoint ? "--checkpoint " + task.ext.checkpoint : ""
    def nb_pts = task.ext.nb_pts ? "--nb_pts " + task.ext.nb_pts : ""
    def mm = task.ext.mm ? "--mm " + task.ext.mm : ""
    def continuous = task.ext.continuous ? "--continuous" : ""
    def min_blob_size = task.ext.min_blob_size ? "--min_blob_size " + task.ext.min_blob_size : ""
    def keep_biggest_blob = task.ext.keep_biggest_blob ? "--keep_biggest_blob" : ""
    def f = task.ext.f ? "-f" : ""
    
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    scil_fodf_bundleparc $fodf \
        --out_folder ${prefix}_bundleparc \
        $out_prefix \
        $half_precision $bundles \
        $checkpoint $nb_pts $mm $continuous \
        $min_blob_size $keep_biggest_blob $f $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ml: \$(samtools --version |& sed '1!d ; s/samtools //')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    scil_fodf_bundleparc -h

    touch ${prefix}_bundleparc
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list --disable-pip-version-check --no-python-version-warning | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
