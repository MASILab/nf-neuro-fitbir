FROM ubuntu:24.04

USER root

RUN apt-get update --quiet && \
    export DEBIAN_FRONTEND=noninteractive && \
    apt-get install --quiet --yes \
        apt-transport-https \
        apt-utils \
        sudo \
        git \
        less \
        wget \
        curl \
        tree \
        graphviz \
        vim \
        software-properties-common && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Apptainer (Singularity)
RUN add-apt-repository -y ppa:apptainer/ppa && \
    apt-get update --quiet && \
    apt install -y apptainer && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set up directories
RUN mkdir -p /workspaces/.nextflow

# Install Seqera Platform "Tower Agent"
RUN curl -fSL https://github.com/seqeralabs/tower-agent/releases/latest/download/tw-agent-linux-x86_64 > tw-agent && \
    chmod +x tw-agent && \
    mv tw-agent /usr/local/bin/tw-agent

# Uncomment if we need to pin the Nextflow version
ENV NXF_EDGE=0
ENV NXF_VER=24.10.4
ENV NXF_HOME=/workspaces/.nextflow

ENV NFNEURO_RAW_REPOSITORY="https://raw.githubusercontent.com/scilus/nf-neuro/main"
ENV NFCORE_MODULES_GIT_REMOTE=https://github.com/scilus/nf-neuro.git
ENV NFCORE_MODULES_BRANCH=main
ENV NFCORE_SUBWORKFLOWS_GIT_REMOTE=https://github.com/scilus/nf-neuro.git
ENV NFCORE_SUBWORKFLOWS_BRANCH=main

# Install conda
ENV PATH="/root/miniforge3/bin:${PATH}"
RUN arch=$(uname -m) && \
    if [ "$arch" = "x86_64" ]; then \
    MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/download/25.3.0-3/Miniforge3-25.3.0-3-Linux-x86_64.sh"; \
    elif [ "$arch" = "aarch64" ]; then \
    MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/download/25.3.0-3/Miniforge3-25.3.0-3-Linux-aarch64.sh"; \
    else \
    echo "Unsupported architecture: $arch"; \
    exit 1; \
    fi && \
    wget $MINIFORGE_URL -O miniforge.sh && \
    mkdir -p /root/.conda && \
    bash miniforge.sh -b -p /root/miniforge3 && \
    rm -f miniforge.sh

# Install nextflow, nf-core, Mamba, and pytest-workflow
RUN conda config --add channels bioconda && \
    conda config --add channels conda-forge && \
    conda config --set channel_priority strict && \
    conda update --quiet --yes --all && \
    conda install --quiet --yes --name base \
        mamba \
        nextflow=$NXF_VER \
        nf-core=2.14.1 \
        nf-test=0.9.2 \
        black \
        prettier \
        pre-commit \
        linkify-it-py \
        pytest-workflow && \
    conda clean --all --force-pkgs-dirs --yes

# Cleanup
RUN printf 'unset JAVA_TOOL_OPTIONS\n' >> $HOME/.bashrc

# Update Nextflow
RUN nextflow self-update && nextflow -version

RUN unset JAVA_TOOL_OPTIONS
ENV PS1='\[\e[3;36m\]${PWD/*//} ->\[\e[0m\] '

# Get history
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    && echo "$SNIPPET" >> "/root/.bashrc"

# Add tos disclaimer to bashrc as trap so it runs at the end of the sourcing process
ADD .devcontainer/gpu/bash_profile.sh /root/.bash_profile
