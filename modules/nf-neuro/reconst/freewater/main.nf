
process RECONST_FREEWATER {
    tag "$meta.id"
    label 'process_very_high_memory'

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

    def my_script = '''
        #! /usr/bin/env python3
    # -*- coding: utf-8 -*-
    """
    Compute Free Water maps [1] using the AMICO framework [2].
    This script supports both single and multi-shell data.

    ----------------------------------------------------------
    References:
    [1] Pasternak 0, Sochen N, Gur Y, Intrator N, Assaf Y.
        Free water elimination and mapping from diffusion mri.
        Magn Reson Med. 62 (3) (2009) 717-730.
    [2] Daducci A, et al. Accelerated microstructure imaging
        via convex optimization (AMICO) from diffusion MRI data.
        Neuroimage 105 (2015) 32-44.
    ----------------------------------------------------------

    """

    import argparse
    from contextlib import redirect_stdout
    import io
    import logging
    import os
    import sys
    import tempfile

    import amico
    from dipy.io.gradients import read_bvals_bvecs
    import numpy as np

    from scilpy.io.gradients import fsl2mrtrix
    from scilpy.io.utils import (add_overwrite_arg,
                                add_processes_arg,
                                add_verbose_arg,
                                assert_inputs_exist,
                                assert_output_dirs_exist_and_empty,
                                redirect_stdout_c)
    from scilpy.gradients.bvec_bval_tools import identify_shells
    from scilpy.version import version_string


    def _build_arg_parser():
        p = argparse.ArgumentParser(description=__doc__,
                                    formatter_class=argparse.RawTextHelpFormatter,
                                    epilog=version_string)

        p.add_argument('in_dwi',
                    help='DWI file.')
        p.add_argument('in_bval',
                    help='b-values filename, in FSL format (.bval).')
        p.add_argument('in_bvec',
                    help='b-vectors filename, in FSL format (.bvec).')

        p.add_argument('--mask',
                    help='Brain mask filename.')
        p.add_argument('--out_dir', default="results",
                    help='Output directory for the Free Water results. '
                            '[%(default)s]')
        p.add_argument('--b_thr', type=int, default=40,
                    help='Limit value to consider that a b-value is on an '
                            'existing shell. Above this limit, the b-value is '
                            'placed on a new shell. This includes b0s values.')

        g1 = p.add_argument_group(title='Model options')
        g1.add_argument('--para_diff', type=float, default=1.5e-3,
                        help='Axial diffusivity (AD) in the CC. [%(default)s]')
        g1.add_argument('--iso_diff', type=float, default=3e-3,
                        help='Mean diffusivity (MD) in ventricles. [%(default)s]')
        g1.add_argument('--perp_diff_min', type=float, default=0.1e-3,
                        help='Radial diffusivity (RD) minimum. [%(default)s]')
        g1.add_argument('--perp_diff_max', type=float, default=0.7e-3,
                        help='Radial diffusivity (RD) maximum. [%(default)s]')
        g1.add_argument('--lambda1', type=float, default=0.0,
                        help='First regularization parameter. [%(default)s]')
        g1.add_argument('--lambda2', type=float, default=0.25,
                        help='Second regularization parameter. [%(default)s]')

        g2 = p.add_argument_group(title='Kernels options')
        kern = g2.add_mutually_exclusive_group()
        kern.add_argument('--save_kernels', metavar='DIRECTORY',
                        help='Output directory for the COMMIT kernels.')
        kern.add_argument('--load_kernels', metavar='DIRECTORY',
                        help='Input directory where the COMMIT kernels are '
                            'located.')
        g2.add_argument('--compute_only', action='store_true',
                        help='Compute kernels only, --save_kernels must be used.')

        p.add_argument('--mouse', action='store_true',
                    help='If set, use mouse fitting profile.')

        add_processes_arg(p)
        add_verbose_arg(p)
        add_overwrite_arg(p)

        return p


    def main():
        parser = _build_arg_parser()
        args = parser.parse_args()
        # COMMIT has some c-level stdout and non-logging print that cannot
        # be easily stopped. Manual redirection of all printed output
        if args.verbose == "WARNING":
            f = io.StringIO()
            redirected_stdout = redirect_stdout(f)
            redirect_stdout_c()
        else:
            logging.getLogger().setLevel(logging.getLevelName(args.verbose))
            redirected_stdout = redirect_stdout(sys.stdout)

        # Verifications
        if args.compute_only and not args.save_kernels:
            parser.error('--compute_only must be used with --save_kernels.')

        assert_inputs_exist(parser, [args.in_dwi, args.in_bval, args.in_bvec],
                            args.mask)

        assert_output_dirs_exist_and_empty(parser, args, args.out_dir,
                                        optional=args.save_kernels)

        # Generate a scheme file from the bvals and bvecs files
        tmp_dir = tempfile.TemporaryDirectory()
        tmp_scheme_filename = os.path.join(tmp_dir.name, 'gradients.b')
        tmp_bval_filename = os.path.join(tmp_dir.name, 'bval')
        bvals, _ = read_bvals_bvecs(args.in_bval, args.in_bvec)
        shells_centroids, indices_shells = identify_shells(bvals, args.b_thr,
                                                        round_centroids=True)
        np.savetxt(tmp_bval_filename, shells_centroids[indices_shells],
                newline=' ', fmt='%i')
        fsl2mrtrix(tmp_bval_filename, args.in_bvec, tmp_scheme_filename)
        logging.info(
            'Computing FreeWater with AMICO on {} shells at found at {}.'.format(
                len(shells_centroids), shells_centroids))

        with redirected_stdout:
            amico.core.setup()
            # Load the data
            ae = amico.Evaluation('.', '.')
            # Load the data
            ae.load_data(args.in_dwi,
                        scheme_filename=tmp_scheme_filename,
                        mask_filename=args.mask,
                        replace_bad_voxels=0)

            # Compute the response functions
            ae.set_model("FreeWater")
            model_type = 'Human'
            if args.mouse:
                model_type = 'Mouse'

            ae.model.set(args.para_diff,
                        np.linspace(args.perp_diff_min, args.perp_diff_max, 10),
                        [args.iso_diff],
                        model_type)

            ae.set_solver(lambda1=args.lambda1, lambda2=args.lambda2)

            # The kernels are, by default, set to be in the current directory
            # Depending on the choice, manually change the saving location
            if args.save_kernels:
                kernels_dir = os.path.join(args.save_kernels)
                regenerate_kernels = True
            elif args.load_kernels:
                kernels_dir = os.path.join(args.load_kernels)
                regenerate_kernels = False
            else:
                kernels_dir = os.path.join(tmp_dir.name, 'kernels', ae.model.id)
                regenerate_kernels = True

            ae.set_config('ATOMS_path', kernels_dir)
            ae.set_config('OUTPUT_path', args.out_dir)
            ae.set_config('nthreads', args.nbr_processes)
            ae.generate_kernels(regenerate=regenerate_kernels)
            if args.compute_only:
                return

            ae.load_kernels()

            # Set number of processes
            ae.set_config('doNormalizeSignal', True)
            ae.set_config('doKeepb0Intact', False)
            ae.set_config('doComputeNRMSE', True)
            ae.set_config('doSaveCorrectedDWI', True)

            # Model fit
            ae.fit()
            # Save the results
            ae.save_results()

        tmp_dir.cleanup()


    if __name__ == "__main__":
        main()
    '''


    """
    cat > run_freewater.py << 'EOF'
    ${my_script}
    EOF

    python run_freewater.py $dwi $bval $bvec $para_diff $perp_diff_min \
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
