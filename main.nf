#!/usr/bin/env nextflow

include { IO_BIDS } from './subworkflows/nf-neuro/io_bids/main'
include { PREPROC_T1 } from './subworkflows/nf-neuro/preproc_t1/main'

include { IMAGE_RESAMPLE } from './modules/nf-neuro/image/resample/main'
include { UTILS_EXTRACTB0 } from './modules/nf-neuro/utils/extractb0/main'
include { BETCROP_SYNTHBET } from './modules/nf-neuro/betcrop/synthbet/main'
include { RECONST_FREEWATER } from './modules/nf-neuro/reconst/freewater/main'
include { RECONST_DTIMETRICS } from './modules/nf-neuro/reconst/dtimetrics/main'
include { RECONST_FODF } from './modules/nf-neuro/reconst/fodf/main'
include { SEGMENTATION_SYNTHSEG } from './modules/nf-neuro/segmentation/synthseg/main'
include { REGISTRATION_ANTS } from './modules/nf-neuro/registration/ants/main'
include { 
    REGISTRATION_ANTSAPPLYTRANSFORMS as REGISTRATION_ANTSAPPLYTRANSFORMS_mask; 
    REGISTRATION_ANTSAPPLYTRANSFORMS as REGISTRATION_ANTSAPPLYTRANSFORMS_wm;
    REGISTRATION_ANTSAPPLYTRANSFORMS as REGISTRATION_ANTSAPPLYTRANSFORMS_seg
} from './modules/nf-neuro/registration/antsapplytransforms/main'
include { RECONST_FRF } from './modules/nf-neuro/reconst/frf/main'
include { STATS_METRICSINROI } from './modules/nf-neuro/stats/metricsinroi/main'

include { ML_BUNDLEPARC } from './modules/local/ml/bundleparc/main'
include { STATS_VOLUME } from './modules/local/stats/volume/main'

workflow {
    
    if ( !params.input ) {
        log.info "You must provide an input directory containing all images using:"
        log.info ""
        log.info "    --input=/path/to/[input]   Input BIDS directory containing your subjects"
        log.info "                        |"
        log.info "                        ├-- sub-*"
        log.info "                        |    └-- ses-*"
        log.info "                        |         └-- anat"
        log.info "                        |             ├-- *T1w.nii.gz"
        log.info "                        |             └-- *T1w.json"
        log.info "                        |         └-- *dwi"
        log.info "                        |             ├-- *dwi.nii.gz"
        log.info "                        |             ├-- *dwi.bval"
        log.info "                        |             └-- *dwi.bvec"
        log.info "                        └-- sub-*"
        log.info "                             ..."
        log.info ""
        error "Please resubmit your command with the previous file structure."
    }    
        
    // Create channels for IO_BIDS subworkflow
    bids_folder_ch = Channel.of(params.input)
    fs_folder_ch = Channel.empty()
    bidsignore_ch = Channel.empty()
    
    // Call IO_BIDS subworkflow
    IO_BIDS(bids_folder_ch, fs_folder_ch, bidsignore_ch)
    bids_dwi = IO_BIDS.out.ch_dwi_bval_bvec
        .multiMap { meta, dwi, bval, bvec -> 
            def new_meta = meta.clone()
            new_meta.id = "${meta.id}${meta.session ?: ''}"
            dwi: [ new_meta, dwi ]
            dwi_bval_bvec: [ new_meta, dwi, bval, bvec ]
            bval_bvec: [ new_meta, bval, bvec ]
        }
    bids_t1w = IO_BIDS.out.ch_t1
        .map { meta, t1w -> 
            def new_meta = meta.clone()
            new_meta.id = "${meta.id}${meta.session ?: ''}"
            t1w: [ new_meta, t1w ]
        }

    // ** T1w PROCESSING ** //
    PREPROC_T1(
        bids_t1w,
        Channel.empty(),
        Channel.empty(),
        Channel.empty(),
        Channel.empty(),
        Channel.empty(),
        Channel.empty(),
        Channel.empty(),
    )
    t1_preproc = PREPROC_T1.out.t1_final
    t1_mask = PREPROC_T1.out.mask_final
    t1_resample = PREPROC_T1.out.image_resample

    // Check we can access the file right away
    def fs_license_path = file(params.freesurfer_license)
    if( !fs_license_path.exists() ) {
        error "ERROR: Cannot access Freesurfer license file at ${fs_license_path}. Check path and permissions."
    } else if ( !fs_license_path.canRead() ) {
        error "ERROR: Cannot read Freesurfer license file at ${fs_license_path}. Check permissions."
    }

    // Now create a channel
    fs_license_ch = Channel.fromPath(params.freesurfer_license)

    // Combine T1w input with FS license
    synthseg_input = t1_resample
        .combine(fs_license_ch)
        .map { meta, t1, license -> tuple(meta, t1, [], license) }

    SEGMENTATION_SYNTHSEG(synthseg_input)

    // ** DWI PREPROCESSING ** //
    // Resample to 1x1x1
    resample_input = bids_dwi.dwi
        .map { it + [[]] }
    IMAGE_RESAMPLE(resample_input)

    resampled_dwi_bval_bvec = IMAGE_RESAMPLE.out.image
        .join(bids_dwi.bval_bvec)

    // Extract b0 images
    UTILS_EXTRACTB0(resampled_dwi_bval_bvec)
    b0_image = UTILS_EXTRACTB0.out.b0

    // Create b0 mask
    betcrop_input = b0_image
        .map { it + [[]] }
    BETCROP_SYNTHBET(betcrop_input)
    b0_mask = BETCROP_SYNTHBET.out.brain_mask

    // Register T1w --> dwi
    t1_to_dwi_input = b0_image
        .join(t1_preproc)
        .map { it + [[]] }
    REGISTRATION_ANTS(t1_to_dwi_input)
    t1_to_dwi_affine = REGISTRATION_ANTS.out.affine
    t1_to_dwi_warp = REGISTRATION_ANTS.out.warp

    // Apply transform to mask and synthseg
    antsapplytransforms_input_mask = SEGMENTATION_SYNTHSEG.out.brain_mask
        .join(b0_image)
        .map { it + [[]] }
        .join(t1_to_dwi_affine)
    REGISTRATION_ANTSAPPLYTRANSFORMS_mask(antsapplytransforms_input_mask)
    t1_to_dwi_mask = REGISTRATION_ANTSAPPLYTRANSFORMS_mask.out.warped_image

    antsapplytransforms_input_wm = SEGMENTATION_SYNTHSEG.out.wm_mask
        .join(b0_image)
        .map { it + [[]] }
        .join(t1_to_dwi_affine)
    REGISTRATION_ANTSAPPLYTRANSFORMS_wm(antsapplytransforms_input_wm)
    wm_mask = REGISTRATION_ANTSAPPLYTRANSFORMS_wm.out.warped_image

    antsapplytransforms_input_seg = SEGMENTATION_SYNTHSEG.out.seg
        .join(b0_image)
        .map { it + [[]] }
        .join(t1_to_dwi_affine)
    REGISTRATION_ANTSAPPLYTRANSFORMS_seg(antsapplytransforms_input_seg)
    seg = REGISTRATION_ANTSAPPLYTRANSFORMS_seg.out.warped_image

    // Run FW correction
    fw_input = resampled_dwi_bval_bvec
        .join(b0_mask)
        .map { it + [[]] }
    RECONST_FREEWATER(fw_input)

    // Get FW-corrected DTI metrics
    dtimetrics_input = RECONST_FREEWATER.out.dwi_fw_corrected
        .join(bids_dwi.bval_bvec)
        .join(b0_mask)
    RECONST_DTIMETRICS(dtimetrics_input)
    fa = RECONST_DTIMETRICS.out.fa
    md = RECONST_DTIMETRICS.out.md

    // // Calculate FRF
    // frf_input = RECONST_FREEWATER.out.dwi_fw_corrected
    //     .join(bids_dwi.bval_bvec)
    //     .join(b0_mask)
    //     .join(wm_mask)
    //     .map { it + [[], []] }
    // RECONST_FRF(frf_input)
    // ss_frf = RECONST_FRF.out.frf

    // // Reconstruct FODs
    // fodf_input = RECONST_FREEWATER.out.dwi_fw_corrected
    //     .join(bids_dwi.bval_bvec)
    //     .join(b0_mask)
    //     .join(fa)
    //     .join(md)
    //     .join(ss_frf)
    //     .map { it + [[], []] }
    // RECONST_FODF(fodf_input)

    // // Perform BundleParc
    // ml_bundleparc_input = RECONST_FODF.out.fodf
    // ML_BUNDLEPARC(ml_bundleparc_input)

    // // Now get mean/std of FA and MD in the BundleParc ROIs
    // bundles = ML_BUNDLEPARC.out.bundles
    // metrics_input = fa.join(md)
    //     .map { meta, fa_file, md_file -> tuple(meta, [fa_file, md_file]) }
    //     .join(bundles)
    //     .map { it + [[]] }

    // STATS_METRICSINROI(metrics_input)

    // // Calculate volume of each BundleParc ROI
    // STATS_VOLUME(bundles)

    // Calculate FA in synthseg mask
    metrics_input = fa.join(md)
        .map { meta, fa_file, md_file -> tuple(meta, [fa_file, md_file]) }
        .join(t1_to_dwi_mask)
        .map { it + [[]] }
    STATS_METRICSINROI(metrics_input)
}