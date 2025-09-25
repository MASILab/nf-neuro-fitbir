#!/usr/bin/env nextflow

include { IO_BIDS } from './subworkflows/nf-neuro/io_bids/main'
include { IMAGE_RESAMPLE } from './modules/nf-neuro/image/resample/main'
include { UTILS_EXTRACTB0 } from './modules/nf-neuro/utils/extractb0/main'
include { BETCROP_SYNTHBET } from './modules/nf-neuro/betcrop/synthbet/main'
include { RECONST_FREEWATER } from './modules/nf-neuro/reconst/freewater/main'

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
        
    // ** Create channels for IO_BIDS subworkflow ** //
    // Pass the path directly without file() to avoid staging
    bids_folder_ch = Channel.of(params.input)
    fs_folder_ch = Channel.empty()
    bidsignore_ch = Channel.empty()
    
    // ** Call IO_BIDS subworkflow ** //
    IO_BIDS(bids_folder_ch, fs_folder_ch, bidsignore_ch)
    bids_output = IO_BIDS.out.ch_dwi_bval_bvec
        .multiMap { meta, dwi, bval, bvec -> 
            def new_meta = meta.clone()
            new_meta.id = "${meta.id}${meta.session ?: ''}"
            dwi: [ new_meta, dwi ]
            dwi_bval_bvec: [ new_meta, dwi, bval, bvec ]
            bval_bvec: [ new_meta, bval, bvec ]
        }
    
    // ** Resample to 1x1x1 ** //
    resample_input = bids_output.dwi
        .map { it + [[]] }
    IMAGE_RESAMPLE(resample_input)

    resampled_dwi_bval_bvec = IMAGE_RESAMPLE.out.image
        .join(bids_output.bval_bvec)

    // ** Extract b0 images ** //
    UTILS_EXTRACTB0(resampled_dwi_bval_bvec)
    b0_image = UTILS_EXTRACTB0.out.b0
    synthstrip_input = b0_image
        .map { it + [[]] }

    // ** Run synthstrip ** //
    BETCROP_SYNTHBET(synthstrip_input)

    // ** Run FW correction ** //
    fw_input = resampled_dwi_bval_bvec
        .join(BETCROP_SYNTHBET.out.brain_mask)
        .map { meta_dwi_bval_bvec, brain_mask -> 
            def (meta, dwi, bval, bvec) = meta_dwi_bval_bvec
            [ meta, dwi, bval, bvec, brain_mask, [] ]
        }
    RECONST_FREEWATER(fw_input)
}