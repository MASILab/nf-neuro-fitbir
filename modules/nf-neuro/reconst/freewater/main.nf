
process RECONST_FREEWATER {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.0_cpu"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(mask), path(kernels)

    output:
        tuple val(meta), path("*__dwi_fw_corrected.nii.gz")  , emit: dwi_fw_corrected, optional: true
        tuple val(meta), path("*__dir.nii.gz")               , emit: dir, optional: true
        tuple val(meta), path("*__FiberVolume.nii.gz")       , emit: fibervolume, optional: true
        tuple val(meta), path("*__FW.nii.gz")                , emit: fw, optional: true
        tuple val(meta), path("*__NRMSE.nii.gz")             , emit: nrmse, optional: true
        path("kernels")                                      , emit: kernels, optional: true
        path "versions.yml"                                  , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def para_diff = task.ext.para_diff ? "--para_diff " + task.ext.para_diff : ""
    def perp_diff_min = task.ext.perp_diff_min ? "--perp_diff_min " + task.ext.perp_diff_min : ""
    def perp_diff_max = task.ext.perp_diff_max ? "--perp_diff_max " + task.ext.perp_diff_max : ""
    def iso_diff = task.ext.iso_diff ? "--iso_diff " + task.ext.iso_diff : ""
    def lambda1 = task.ext.lambda1 ? "--lambda1 " + task.ext.lambda1 : ""
    def lambda2 = task.ext.lambda2 ? "--lambda2 " + task.ext.lambda2 : ""
    def nb_threads = task.ext.nb_threads ? "--processes " + task.ext.nb_threads : ""
    def b_thr = task.ext.b_thr ? "--b_thr " + task.ext.b_thr : ""
    def set_kernels = kernels ? "--load_kernels $kernels" : "--save_kernels kernels/"
    def set_mask = mask ? "--mask $mask" : ""
    def compute_only = task.ext.compute_only && !kernels ? "--compute_only" : ""

    """
    scil_freewater_maps $dwi $bval $bvec $para_diff $perp_diff_min \
        $perp_diff_max $iso_diff $lambda1 $lambda2 $nb_threads $b_thr \
        $set_mask $set_kernels $compute_only

    if [ -z "${compute_only}" ]; then
        mv results/DWI_corrected.nii.gz ${prefix}__dwi_fw_corrected.nii.gz
        mv results/fit_dir.nii.gz ${prefix}__dir.nii.gz
        mv results/fit_FiberVolume.nii.gz ${prefix}__FiberVolume.nii.gz
        mv results/fit_FW.nii.gz ${prefix}__FW.nii.gz
        mv results/fit_NRMSE.nii.gz ${prefix}__NRMSE.nii.gz

        rm -rf results
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_freewater_maps -h
    mkdir kernels
    touch "${prefix}__dwi_fw_corrected.nii.gz"
    touch "${prefix}__FIT_dir.nii.gz"
    touch "${prefix}__FIT_FiberVolume.nii.gz"
    touch "${prefix}__FIT_FW.nii.gz"
    touch "${prefix}__FIT_nrmse.nii.gz"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
