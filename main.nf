#!/usr/bin/env nextflow

include { IO_BIDS } from './subworkflows/nf-neuro/io_bids/main'
include { IMAGE_RESAMPLE } from './modules/nf-neuro/image/resample/main'

workflow {
    main:
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
        
    input = file(params.input)
    
    // ** Create channels for IO_BIDS subworkflow ** //
    bids_folder_ch = Channel.of(input)
    fs_folder_ch = Channel.empty()
    bidsignore_ch = Channel.empty()
    
    // ** Call IO_BIDS subworkflow ** //
    IO_BIDS(bids_folder_ch, fs_folder_ch, bidsignore_ch)
    dwi_bval_bvec = IO_BIDS.output.ch_dwi_bval_bvec
        .multiMap { meta, dwi, bval, bvec ->
            dwi:            [meta, file(dwi)]
            bvs_files:      [meta, file(bval), file(bvec)]
            dwi_bval_bvec:  [meta, file(dwi), file(bval), file(bvec)]
        }

    dwi_bval_bvec.dwi.view()

    // // ** Resample to 1x1x1 ** //
    // resample_input_ch = IO_BIDS.output.ch_dwi_bval_bvec.map { meta, dwi, _bval, _bvec ->
    //     tuple(meta, [dwi, []])   // wrap properly, dwi stays a Path
    // }
    // IMAGE_RESAMPLE(resample_input_ch)
}