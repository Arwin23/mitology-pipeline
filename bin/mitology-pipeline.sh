#!/usr/bin/env bash

#
# MITOLOGY PIPELINE
#

# Authors: Joseph Tran <Joseph.Tran@versailles.inra.fr>, Delphine Charif <Delphine.Charif@versailles.inra.fr>

# This script provides a pipeline for plant organites (chloroplast and mitochondrion) assembly 
# GRANT: ANR BIOADAPT CYTOPHENO 2013

# This software is governed by the CeCILL license, Version 2.0 (the "License"), under French law and
# abiding by the rules of distribution of free software.  You can  use,
# modify and/ or redistribute the software under the terms of the CeCILL
# license, Version 2.0 (the "License"), as circulated by CEA, CNRS and INRIA at the following URL
# "http://www.cecill.info/licences/Licence_CeCILL_V2-en.txt".

# As a counterpart to the access to the source code and  rights to copy,
# modify and redistribute granted by the license, users are provided only
# with a limited warranty  and the software's author,  the holder of the
# economic rights,  and the successive licensors  have only  limited
# liability.

# In this respect, the user's attention is drawn to the risks associated
# with loading,  using,  modifying and/or developing or reproducing the
# software by the user in light of its specific status of free software,
# that may mean  that it is complicated to manipulate,  and  that  also
# therefore means  that it is reserved for developers  and  experienced
# professionals having in-depth computer knowledge. Users are therefore
# encouraged to load and test the software's suitability as regards their
# requirements in conditions enabling the security of their systems and/or
# data to be ensured and,  more generally, to use and operate it in the
# same conditions as regards security.

# The fact that you are presently reading this means that you have had
# knowledge of the CeCILL license, Version 2.0 (the "License"), and that you accept its terms.

# Date: 2014-09-25

declare -r VERSION="dev"

########################
# SECTION CONFIGURATION
#######################

### SESSION VARIABLES ###

NAMESPACE="MITOLOGY"

WORKING_DIR=$(pwd)
DATE=$(date '+%F_%Hh%Mm%Ss')
SESSION_ID=$(date '+%Y%m%d%H%M%S')
EXECUTED_COMMAND="$0 $*"
SESSION_TAG=${NAMESPACE}_${USER}_${SESSION_ID}

LOG_DIR="log"
DEBUGFILE=${SESSION_TAG}.log
ERROR_TMP="/tmp/$(basename ${0%.*})_error_${SESSION_TAG}.log"

[[ $VERSION -eq "dev" ]] && PROG_PATH=$(realpath $(dirname $0));PIPELINE_USER_CONFIG=${PROG_PATH}/../share/mitology-pipeline/etc/mitology-pipeline_user.config || PIPELINE_USER_CONFIG=/usr/local/share/mitology-pipeline/etc/mitology-pipeline_user.config

PIDS_ARR=()
WAITALL_TIMEOUT=259200
WAITALL_INTERVAL=60
WAITALL_DELAY=60

### LOGGING CONFIGURATION ###

# load log4sh (disabling properties file warning) and clear the default
# configuration
LOG4SH_CONFIGURATION='none' . /usr/local/share/log4sh/build/log4sh 2>/dev/null
[[ $? != 0 ]] && $(echo "Error loading log4sh lib" >&2; exit 1)
log4sh_resetConfiguration

# set the global logging level
# add and configure a FileAppender that outputs to STDERR
logger_addAppender stderr
appender_setType stderr FileAppender
appender_file_setFile stderr STDERR
appender_setLevel stderr FATAL
appender_setLayout stderr PatternLayout
appender_setPattern stderr '%d{HH:mm:ss,SSS} %-4rs [%F:%-5p] %t - %m'
appender_activateOptions stderr
# add and configure console appender that outputs to standard output
logger_addAppender console
appender_setType console ConsoleAppender
appender_setLevel console INFO
appender_setLayout console PatternLayout
appender_setPattern console '%d{HH:mm:ss,SSS} %-4rs [%F:%-5p] %t - %m'
appender_activateOptions console
appender_exists console && logger_debug "Console appender is enabled." || logger_warn "Console appender was not enabled. Maybe a log4sh error occured."

### LOAD LIB ###

# bash-common lib
[[ $VERSION == "dev" ]] && LIB_PATH=$(realpath $(dirname $0))/../../bash-common/share/bash-common/lib/bash-common_lib.inc || LIB_PATH=/usr/local/share/bash-common/lib/bash-common_lib.inc

logger_debug "[Library] Loading $LIB_PATH"
. $LIB_PATH
if [[ $? -ne 0 ]]; then
	logger_fatal "Error loading bash common lib: $LIB_PATH"
	exit 1
fi

### USAGE ###
Usage()
{
printf %s "\
Program: $(basename $0)
Version: $VERSION

Copyright 2014 Joseph Tran <Joseph.Tran@versailles.inra.fr> & Delphine Charif <Delphine.Charif@versailles.inra.fr>

Licensed under the CeCILL License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
http://www.cecill.info/licences/Licence_CeCILL_V2-en.txt

Usage: $(basename $0) -c|--configfile CONFIG_FILE -o|--out_dir OUTPUT_DIR [-d|--debug] [-C|--kmer_abund_cutoff INT] [--interleaving] [-e|--email_address VALID_EMAIL_ADDR]

Mandatory:
-c|--config_file CONFIG_FILE            The user configuration file listing the data samples paths and tetrad analysis parameters.
                                        You can get a copy there: $PIPELINE_USER_CONFIG.
-C|--kmer_abund_cutoff INT				The k-mer abundance cutoff below which k-mers are trimmed with khmer (filter_abund.py) corresponding to errors and contaminants. This value overrides the one given in the CONFIG_FILE. 
-o|--out_dir OUTPUT_DIR                 The output directory.

Options:
-d|--debug                              Enable debugging mode in the console.
--interleaving                          Will interleave input paired end read sequence files before build hash count table. Output: <sample_name>_interleaved.fastq in filtering directory.
-e|--email_address VALID_EMAIL_ADDR     An optional but valid email address to send pipeline job/error status notifications
-h|--help                               Displays this message.

"
}

### DEFAULTS
INTERLEAVING=false


### NOTE: This requires GNU getopt.  On Mac OS X and FreeBSD, you have to install this
# separately;
CONFIGURE_OPTS=`getopt -o hc:C:o:e:d --long help,config_file:,out_dir:,kmer_abund_cutoff:,interleaving,debug,email_address: \
    -n 'mitology-pipeline.sh' -- "$@"`

if [[ $? != 0 ]] ; then Usage >&2 ; exit 1 ; fi

# Note the quotes around `$CONFIGURE_OPTS'
eval set -- "$CONFIGURE_OPTS"

while true; do
    case "$1" in
        -h | --help ) Usage >&2; exit 1;;
        -c | --config_file ) CONFIGFILE="$2"; shift 2 ;;
        -o | --out_dir ) OUTPUT_DIR="$2"; shift 2 ;;
		-C | --kmer_abund_cutoff ) KMER_ABUND_CUTOFF="$2"; shift 2;;
		--interleaving ) INTERLEAVING=true; shift 1;;
        -d | --debug )
                    appender_setLevel console DEBUG;
                    appender_activateOptions console;
                    shift 1 ;;
        -e | --email_address ) EMAIL="$2"; shift 2 ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done

### VALIDATION ###
if [[ ! -s $CONFIGFILE ]]; then
    logger_fatal "Config file, $CONFIGFILE, does not exist or is empty. See Usage with --help option.";
    exit 1;
fi

if [[ -z $OUTPUT_DIR ]]; then
	logger_fatal "Output directory must be not null. See Usage with --help option.";
	exit 1;
fi

#################
# PIPELINE STEPS
#################

# CREATE OUTPUT DIR
# LOAD CONFIG
# OVERRIDE CONFIG
# SET GENOME PATH AND INDEXES
# CHECKING SAMPLE
# K-MER ABUNDANCE FILTERING: FILTERED READS
# ASSEMBLY: CONTIGING AND SCAFFOLDING (OPTIONAL)
# DOT PLOT AGAINST REFERENCE GENOME
# INTERNAL CONSISTENCY: MAPPING FILTERED READS AGAINST CONTIGS AND SCAFFOLDS (OPTIONAL)
# CLEANING

#===================
# OUTPUT DIRECTORY
#===================

echo "Start running $NAMESPACE pipeline (version: $VERSION)." | tee $ERROR_TMP 2>&1 | logger_info
echo "Executed command: $0 $*" | tee -a $ERROR_TMP 2>&1 | logger_info

#
# Create a directory named with OUTPUT_DIR value, to save all outputs
#
echo "Creating $OUTPUT_DIR directory ..." | tee -a $ERROR_TMP 2>&1 | logger_info
if [[ -d $OUTPUT_DIR ]]; then
    echo "OK $OUTPUT_DIR directory already exists. Will output all output files in this directory." | tee -a $ERROR_TMP 2>&1  | logger_info
else
    mkdir $OUTPUT_DIR 2>>$ERROR_TMP
    rtrn=$?
    out_dir_failed_msg="[Output directory] Failed. Output directory, $OUTPUT_DIR, was not created."
    [[ "$rtrn" -ne 0 ]] && logger_fatal "$out_dir_failed_msg"
    exit_on_error "$ERROR_TMP" "$out_dir_failed_msg" $rtrn "" $SESSION_TAG $EMAIL
    echo "$(date '+%Y-%m-%d %T') [Output directory] OK $OUTPUT_DIR directory was created successfully. Will output all output files in this directory." | tee -a $ERROR_TMP 2>&1 | logger_info
fi

# Create log directory
echo "Creating $LOG_DIR directory ..." | tee -a $ERROR_TMP 2>&1 | logger_info
if [[ -d $OUTPUT_DIR/$LOG_DIR ]]; then
    echo "OK $OUTPUT_DIR/$LOG_DIR directory already exists. Will write log files in this directory." | tee -a $ERROR_TMP 2>&1 | logger_info
else
    mkdir $OUTPUT_DIR/$LOG_DIR 2>>$ERROR_TMP
    rtrn=$?
    log_dir_failed_msg="[Log directory] Failed Log directory, $OUTPUT_DIR/$LOG_DIR, was not created."
    [[ "$rtrn" -ne 0 ]] && logger_fatal "$log_dir_failed_msg"
    exit_on_error "$ERROR_TMP" "$log_dir_failed_msg" $rtrn "" $SESSION_TAG $EMAIL
    echo "$(date '+%Y-%m-%d %T') [Log directory] OK $OUTPUT_DIR/$LOG_DIR directory was created sucessfully. Will write log files in this directory." | tee -a $ERROR_TMP 2>&1 | logger_info
fi

#==================================
# Enable the pipeline debug logger
#==================================

logger_addAppender debuggerF
appender_setType debuggerF FileAppender
appender_file_setFile debuggerF $OUTPUT_DIR/$LOG_DIR/$DEBUGFILE
appender_setLevel debuggerF DEBUG
appender_setLayout debuggerF PatternLayout
appender_setPattern debuggerF '%d{HH:mm:ss,SSS} %-4rs [%F:%-5p] %t - %m'
appender_activateOptions debuggerF
appender_exists debuggerF && cat $ERROR_TMP | logger_info
appender_exists debuggerF && logger_info "Debugging infos will be output to $OUTPUT_DIR/$LOG_DIR/$DEBUGFILE file." || logger_warn "The debugger file appender was not enabled. Maybe a log4sh error occured."

#=============
# LOAD CONFIG
#=============

# set backup config file variable
BACKUPED_CONFIG_FILE=$OUTPUT_DIR/$(basename $CONFIGFILE)

# 1. Backup session user config file in session dir if not exist
logger_info "[Check config: session user config file] Backuping session user config file into session directory ..."
cp $CONFIGFILE $OUTPUT_DIR/. 2>$ERROR_TMP
rtrn=$?
cp_user_config_failed_msg="[Check config: session user config file] Failed backuping session user config file into session directory."
[[ "$rtrn" -ne 0 ]] && logger_fatal "$cp_user_config_failed_msg"
exit_on_error "$ERROR_TMP" "$cp_user_config_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL
logger_info "[Check config: session user config file] Will use backuped session user config file: $BACKUPED_CONFIG_FILE" | tee -a $LOG_DIR/$DEBUGFILE 2>&1

# 2. Load config parameters from backuped session user config file
logger_info "[Check config: session user config file] Loading session user config parameters from $BACKUPED_CONFIG_FILE file ..."
load_user_config_failed_msg="[Check config: session user config file] Failed loading session user config parameters from $BACKUPED_CONFIG_FILE file."
for cfg in $(get_config_sections $BACKUPED_CONFIG_FILE 2>$ERROR_TMP;); do
    rtrn=$?
    [[ "$rtrn" -ne 0 ]] && logger_fatal "$load_user_config_failed_msg"
    exit_on_error "$ERROR_TMP" "$load_user_config_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL
    logger_debug "--- Config section [${cfg}] ---"
    unset $(set |awk -F= -v cfg="${cfg}" -v prefix="${NAMESPACE}" 'BEGIN {
          cfg = toupper(cfg);
          prefix = toupper(prefix);
          pattern = "\^" prefix "_" cfg "_"
       }
       $0~pattern { print $1 }' 2>$ERROR_TMP ) 2>>$ERROR_TMP
    rtrn=$?
    [[ "$rtrn" -ne 0 ]] && logger_fatal "$load_user_config_failed_msg"
    exit_on_error "$ERROR_TMP" "$load_user_config_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL
    CONFIG_PARAMS=$(format_config_params $BACKUPED_CONFIG_FILE ${cfg} ${NAMESPACE} 2>$ERROR_TMP)
    eval "${CONFIG_PARAMS}"
    rtrn=$?
    [[ "$rtrn" -ne 0 ]] && logger_fatal "$load_user_config_failed_msg"
    exit_on_error "$ERROR_TMP" "$load_user_config_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL
    for params in $(set | grep ^$(toupper ${NAMESPACE}_${cfg}_) 2>$ERROR_TMP); do
        logger_debug "$params"
    done
    rtrn=$?
    [[ "$rtrn" -ne 0 ]] && logger_fatal "$load_user_config_failed_msg"
    exit_on_error "$ERROR_TMP" "$load_user_config_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL
done
logger_info "[Check config: session user config file] OK Session user config file, $BACKUPED_CONFIG_FILE, was loaded successfully."

#=================
# OVERRIDE CONFIG
#=================

logger_info "[Override config] checking for options to override loaded config parameters ..."

### khmer filter abund cutoff
declare -r khmer_filter_abund_cutoff=$(toupper ${NAMESPACE}_khmer_filter_abund)_C
if [[ -z ${!khmer_filter_abund_cutoff} ]]; then
	logger_warn "[Override config] Config khmer filter abundance cutoff variable, ${khmer_filter_abund_cutoff}, is null. Search for option to override ..."
	if [[ -z $KMER_ABUND_CUTOFF ]]; then
		logger_fatal "[Override config] Khmer abundance cutoff option value is null. Please fill in a cutoff value in config file or on the command line, see usage with --help option."
		exit 1
	else
		eval "$(toupper ${NAMESPACE}_khmer_filter_abund)_C=${KMER_ABUND_CUTOFF}"
		logger_info "[Override config] Overrides config khmer filter abundance cutoff value, NULL, by ${!khmer_filter_abund_cutoff}"
	fi
else
	if [[ -n $KMER_ABUND_CUTOFF ]]; then
		cutoff_old=${!khmer_filter_abund_cutoff}
		eval "$(toupper ${NAMESPACE}_khmer_filter_abund)_C=${KMER_ABUND_CUTOFF}"
		logger_info "[Override config] Overrides config khmer filter abundance cutoff value, $cutoff_old, by ${!khmer_filter_abund_cutoff}"
	else
		logger_info "[Override config] Not overriding the config khmer filter abundance cutoff value, ${!khmer_filter_abund_cutoff}."
	fi
fi

#=============================================
# REFERENCE GENOME SEQUENCE AND INDEXES PATHS
#=============================================

logger_info "[Genome sequences and index paths] set path variables ..."

### set refrence genome sequence base path
declare -r genome_base_path=$(toupper ${NAMESPACE}_paths)_GENOMES_BASE_PATH

if [[ -z ${!genome_base_path} && ! -d ${!genome_base_path} ]]; then
    logger_fatal "An error occured while setting genome base path variable."
    exit 1
fi
logger_debug "[Genome base path] ${genome_base_path}=${!genome_base_path}"

### set refrence genome indexes base path
declare -r genome_index_path=$(toupper ${NAMESPACE}_paths)_INDEXES_BASE_PATH
if [[ -z ${!genome_index_path} ]]; then
    logger_fatal "An error occured while setting genome indexes path variable."
    exit 1
fi
logger_debug "[Genome index path] ${genome_index_path}=${!genome_index_path}"

#### reference
declare -r ga_ref=$(toupper ${NAMESPACE}_genome_alias )_ref
if [[ -z ${!ga_ref} ]]; then
    logger_fatal "An error occured while setting genome alias variable for reference genome."
    exit 1
fi
logger_debug "[Genome alias] ${ga_ref}=${!ga_ref}"

### SET GENOME SAMTOOLS INDEX PATH RELATIVE TO CURRENT VERSION/TOOL

declare -r genome_samtools_path=$(toupper ${NAMESPACE}_paths)_SAMTOOLS_INDEXES
if [[ -z ${!genome_samtools_path} ]]; then
    logger_fatal "An error occured while setting genome samtools indexes path variable."
    exit 1
fi
logger_debug "[Genome index path] ${genome_samtools_path}=${!genome_samtools_path}"

eval "$(toupper ${NAMESPACE}_paths)_ref_samtools_index=${!genome_index_path}/${!genome_samtools_path}/$(get_tool_version samtools)/${!ga_ref}/${!ga_ref}"
declare -r ref_samtools_index_path=$(toupper ${NAMESPACE}_paths)_ref_samtools_index
if [[ ! -s ${!ref_samtools_index_path} ]]; then
    logger_fatal "An error occured while setting genome samtools index path for reference genome."
    exit 1
fi
IDX_FILES=($(ls ${!ref_samtools_index_path}*))
if [[ ${#IDX_FILES[@]} -le 0 ]]; then
    logger_fatal "An error occured while checking genome samtools index files for the reference genome."
    exit 1
fi
logger_info "[Genome samtools index path] ${ref_samtools_index_path}=${!ref_samtools_index_path}"

### SET GENOME BWA INDEX PATH RELATIVE TO CURRENT VERSION/TOOL

#### set current tool version index for the reference genome
declare -r genome_bwa_path=$(toupper ${NAMESPACE}_paths)_BWA_INDEXES
if [[ -z ${!genome_bwa_path} ]]; then
    logger_fatal "An error occured while setting genome bwa indexes path variable."
    exit 1
fi
logger_debug "[Genome index path] ${genome_bwa_path}=${!genome_bwa_path}"

eval "$(toupper ${NAMESPACE}_paths)_ref_bwa_index=${!genome_index_path}/${!genome_bwa_path}/$(get_tool_version bwa)/${!ga_ref}/${!ga_ref}"
declare -r ref_bwa_index_path=$(toupper ${NAMESPACE}_paths)_ref_bwa_index
if [[ -z ${!ref_bwa_index_path} ]]; then
    logger_fatal "An error occured while setting genome bwa index path variable for the ref genome."
    exit 1
fi
IDX_FILES=($(ls ${!ref_bwa_index_path}*))
if [[ ${#IDX_FILES[@]} -le 0 ]]; then
    logger_fatal "An error occured while checking genome bwa index files for the ref genome."
    exit 1
fi
logger_info "[Genome index path] ${ref_bwa_index_path}=${!ref_bwa_index_path}"

# call directly
#eval echo -e \$"$(toupper ${NAMESPACE}_paths)_ref_bwa_index"
# test
#eval ls -lh \$"$(toupper ${NAMESPACE}_paths)_ref_bwa_index*"

#=================
# CHECKING SAMPLE
#=================

declare -r current_sample_alias=$(toupper ${NAMESPACE}_sample)_name_alias
declare -r current_sample_seq_dir=$(toupper ${NAMESPACE}_sample)_seqfile_parent_dir

# check if seq dir exists
if [[ ! -d ${!current_sample_seq_dir} ]]; then
	logger_fatal "[Checking sample] Sample directory, ${!current_sample_seq_dir}, does not exist. Please check the sample directory path."
	exit 1
fi
logger_info "[Checking sample] Sample directory, ${!current_sample_seq_dir}, exists."

# check if all seq files exist
declare -r current_sample_seq_R1=$(toupper ${NAMESPACE}_sample)_seqfile_R1
eval "$(toupper ${NAMESPACE}_sample)_seqfile_R1_path=${!current_sample_seq_dir}/${!current_sample_seq_R1}"
declare -r current_sample_seq_R1_path=$(toupper ${NAMESPACE}_sample)_seqfile_R1_path

declare -r current_sample_seq_R2=$(toupper ${NAMESPACE}_sample)_seqfile_R2
eval "$(toupper ${NAMESPACE}_sample)_seqfile_R2_path=${!current_sample_seq_dir}/${!current_sample_seq_R2}"
declare -r current_sample_seq_R2_path=$(toupper ${NAMESPACE}_sample)_seqfile_R2_path

if [[ ! -s "${!current_sample_seq_R1_path}" ]]; then
	logger_fatal "[Checking sample] Sample R1 seq file, ${!current_sample_seq_R1}, does not exist or is empty."
	exit 1
fi	
logger_info "[Checking sample] Sample R1 seq file, ${!current_sample_seq_R1}, exists."

if [[ ! -s "${!current_sample_seq_R2_path}" ]]; then
	logger_fatal "[Checking sample] Sample R2 seq file, ${!current_sample_seq_R2}, does not exist or is empty."
	exit 1
fi
logger_info "[Checking sample] Sample R2 seq file, ${!current_sample_seq_R2}, exists."

#===============================
# 01. K-MER ABUNDANCE FILTERING
#===============================

# STEPS
## CREATE OUTPUT DIR
## INTERLEAVE READS (OPTIONAL)
## COUNTING KMERS
## FILTER K-MER ABUNDANCE
## EXTRACT AND SPLIT PAIRED READS

#
# Create K-mer abundance filtering output directory
#
KMER_FILTER_ABUND_OUTDIR="01.K-mer_filter_abund"
logger_info "Creating $KMER_FILTER_ABUND_OUTDIR directory ..." 
if [[ -d $OUTPUT_DIR/$KMER_FILTER_ABUND_OUTDIR ]]; then
    logger_debug"OK $KMER_FILTER_ABUND_OUTDIR directory already exists. Will output all k-mer abundance filtering output files in this directory."
else
    mkdir $OUTPUT_DIR/$KMER_FILTER_ABUND_OUTDIR 2>$ERROR_TMP
    rtrn=$?
    out_dir_failed_msg="[$KMER_FILTER_ABUND_OUTDIR] Failed. K-mer abundance filtering output directory, $KMER_FILTER_ABUND_OUTDIR, was not created."
    [[ "$rtrn" -ne 0 ]] && logger_fatal "$out_dir_failed_msg"
    exit_on_error "$ERROR_TMP" "$out_dir_failed_msg" $rtrn "" $SESSION_TAG $EMAIL
    logger_debug "[$KMER_FILTER_ABUND_OUTDIR] OK $KMER_FILTER_ABUND_OUTDIR directory was created successfully. Will output all k-mer abundance filtering output files in this directory."
fi

### Enable the k-mer abundance filtering debug logger
KMER_FILTER_ABUND_DEBUGF=${KMER_FILTER_ABUND_OUTDIR}_debug.log
logger_addAppender kmerFiltAbundF
appender_setType kmerFiltAbundF FileAppender
appender_file_setFile kmerFiltAbundF $OUTPUT_DIR/$KMER_FILTER_ABUND_OUTDIR/$KMER_FILTER_ABUND_DEBUGF
appender_setLevel kmerFiltAbundF DEBUG
appender_setLayout kmerFiltAbundF PatternLayout
appender_setPattern kmerFiltAbundF '%d{HH:mm:ss,SSS} %-4rs [%F:%-5p] %t - %m'
appender_activateOptions kmerFiltAbundF
appender_exists kmerFiltAbundF && logger_info "[$KMER_FILTER_ABUND_OUTDIR] Debugging infos on k-mer abundance filtering will be output to $OUTPUT_DIR/$KMER_FILTER_ABUND_OUTDIR/$KMER_FILTER_ABUND_DEBUGF file." || logger_warn "The kmerFiltAbundF debugger file appender was not enabled. Maybe a log4sh error occured."
### error handling
KMER_FILTER_ABUND_ERROR=$OUTPUT_DIR/$KMER_FILTER_ABUND_OUTDIR/${KMER_FILTER_ABUND_OUTDIR}.err

case $INTERLEAVING in
	(true)

	#
	# Interleave reads
	#
	logger_info "[$KMER_FILTER_ABUND_OUTDIR] Interleaving reads ..."
	INTERLEAVED_ERROR=$OUTPUT_DIR/$KMER_FILTER_ABUND_OUTDIR/${!current_sample_alias}_interleaved.err

	# build cli
	declare -r khmer_interleave_reads=$(toupper ${NAMESPACE}_paths)_khmer_interleave_reads
	eval "$(toupper ${NAMESPACE}_sample)_interleaved_reads=$OUTPUT_DIR/$KMER_FILTER_ABUND_OUTDIR/${!current_sample_alias}_interleaved.fastq"
	declare -r interleaved_reads=$(toupper ${NAMESPACE}_sample)_interleaved_reads
	kmer_filt_abund_cli="${!khmer_interleave_reads} ${!current_sample_seq_R1_path} ${!current_sample_seq_R2_path} >${!interleaved_reads} 2>${INTERLEAVED_ERROR} &"

	# run cli
	logger_debug "[$KMER_FILTER_ABUND_OUTDIR] $kmer_filt_abund_cli"
	eval "$kmer_filt_abund_cli" 2>$KMER_FILTER_ABUND_ERROR
	pid=$!
	rtrn=$?
	eval_failed_msg="[$KMER_FILTER_ABUND_OUTDIR] An error occured while eval $kmer_filt_abund_cli cli." 
	exit_on_error "$KMER_FILTER_ABUND_ERROR" "$eval_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL

	# add pid to array
	PIDS_ARR=("${PIDS_ARR[@]}" "$pid")
	# wait until interleave reads process finish then proceed to next step
	# and reinit pid array
	pid_list_failed_msg="[$KMER_FILTER_ABUND_OUTDIR] Failed getting process status for process $p."
	for p in "${PIDS_ARR[@]}"; do
		logger_trace "$(ps aux | grep $USER | gawk -v pid=$p '$2 ~ pid {print $0}' 2>${KMER_FILTER_ABUND_ERROR})"
		rtrn=$?
		exit_on_error "$KMER_FILTER_ABUND_ERROR" "$pid_list_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL
	done
	logger_info "[$KMER_FILTER_ABUND_OUTDIR] Wait for all ${!khmer_interleave_reads} processes to finish before proceed to next step."
	waitalluntiltimeout "${PIDS_ARR[@]}" 2>/dev/null
	if [[ -s ${INTERLEAVED_ERROR} ]] 
		then logger_warn "[$KMER_FILTER_ABUND_OUTDIR] Some messages were thrown to standard error while executing ${!khmer_interleave_reads}. See ${INTERLEAVED_ERROR} file for more details."
	fi 
	logger_info "[$KMER_FILTER_ABUND_OUTDIR] All ${!khmer_interleave_reads} processes finished. Will proceed to next step ..."
	PIDS_ARR=()

	# set data with interleaved sequences to build hash count table
	DATA=${!interleaved_reads}
	;;
	(false)
	# set data with input paired end sequences to build hash count table
	DATA="${!current_sample_seq_R1_path} ${!current_sample_seq_R2_path}"
	;;
esac

#
# Counting k-mers
#
logger_info "[$KMER_FILTER_ABUND_OUTDIR] Counting k-mers ..."
COUNTING_ERROR=$OUTPUT_DIR/$KMER_FILTER_ABUND_OUTDIR/${!current_sample_alias}_counting.err

# build cli options
khmer_load_into_counting_opts=($(buildCommandLineOptions "khmer_load_into_counting" "$NAMESPACE" 2>$KMER_FILTER_ABUND_ERROR))
rtrn=$?
cli_opts_failed_msg="[$KMER_FILTER_ABUND_OUTDIR] An error occured while building the khmer_load_into_counting command line options for current sample ${!current_sample_alias}."
exit_on_error "$KMER_FILTER_ABUND_ERROR" "$cli_opts_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL
opts="${khmer_load_into_counting_opts[@]}"
logger_debug "[$KMER_FILTER_ABUND_OUTDIR] khmer_load_into_counting options: $opts"

# build cli
declare -r khmer_load_into_counting_k=$(toupper ${NAMESPACE}_khmer_load_into_counting)_k
declare -r khmer_load_into_counting=$(toupper ${NAMESPACE}_paths)_khmer_load_into_counting
eval "$(toupper ${NAMESPACE}_sample)_hash_count=$OUTPUT_DIR/$KMER_FILTER_ABUND_OUTDIR/${!current_sample_alias}_k${!khmer_load_into_counting_k}.hashcount"
declare -r khmer_hash_count=$(toupper ${NAMESPACE}_sample)_hash_count

khmer_load_into_counting_cli="${!khmer_load_into_counting} $opts ${!khmer_hash_count} ${DATA} 2>${COUNTING_ERROR} | logger_debug &"

# run cli
logger_debug "[$KMER_FILTER_ABUND_OUTDIR] $khmer_load_into_counting_cli"
eval "$khmer_load_into_counting_cli" 2>$KMER_FILTER_ABUND_ERROR
pid=$!
rtrn=$?
eval_failed_msg="[$KMER_FILTER_ABUND_OUTDIR] An error occured while eval $khmer_load_into_counting_cli cli."
exit_on_error "$KMER_FILTER_ABUND_ERROR" "$eval_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL

# add pid to array
PIDS_ARR=("${PIDS_ARR[@]}" "$pid")
# wait until interleave reads process finish then proceed to next step
# and reinit pid array
pid_list_failed_msg="[$KMER_FILTER_ABUND_OUTDIR] Failed getting process status for process $p."
for p in "${PIDS_ARR[@]}"; do
    logger_trace "$(ps aux | grep $USER | gawk -v pid=$p '$2 ~ pid {print $0}' 2>${KMER_FILTER_ABUND_ERROR})"
    rtrn=$?
    exit_on_error "$KMER_FILTER_ABUND_ERROR" "$pid_list_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL
done

### check for potential errors at start
# khmer version 1.1 / screed version 0.7
# load-into-counting.py throws "IOError: InvalidFASTQFileFormat: sequence and quality scores length mismatch"
# Not very informative and not related to fastq format considering this issue (https://github.com/ged-lab/khmer/issues/249)
# checked input fastq: ok, readlength == qualitylength
# awk '{if(NR%4==2) print NR"\t"$0"\t"length($0)}' test/01.K-mer_filter_abund/cvi_interleaved.fastq > cvi_readlength.txt
# awk '{if(NR%4==0) print NR"\t"$0"\t"length($0)}' test/01.K-mer_filter_abund/cvi_interleaved.fastq > cvi_qualitylength.txt
# awk 'NR==FNR{a[$3]++;next}!a[$3]' cvi_readlength.txt cvi_qualitylength.txt | wc -l # => result: 0
# Proposed fix: do not use multi-threading with T>1
# fix works but that's a pitty!

if [[ -s ${COUNTING_ERROR} ]] 
	then 
		logger_warn "[$KMER_FILTER_ABUND_OUTDIR] Some messages were thrown to standard error while executing ${!khmer_load_into_counting}. See ${COUNTING_ERROR} file for more details."
	if [[ -n $(grep "Error" $COUNTING_ERROR) ]]; then
		cat $COUNTING_ERROR | logger_warn
		logger_fatal $eval_failed_msg
		exit 1
	fi
fi
### end checking errors at start

logger_info "[$KMER_FILTER_ABUND_OUTDIR] Wait for all ${!khmer_load_into_counting} processes to finish before proceed to next step."
waitalluntiltimeout "${PIDS_ARR[@]}" 2>/dev/null
logger_info "[$KMER_FILTER_ABUND_OUTDIR] All ${!khmer_load_into_counting} processes finished. Will proceed to next step ..."
PIDS_ARR=()

#
# Filtering k-mer abundance
#
logger_info "[$KMER_FILTER_ABUND_OUTDIR] Filtering k-mer abundance ..."
FILTER_ABUND_ERROR=$OUTPUT_DIR/$KMER_FILTER_ABUND_OUTDIR/${!current_sample_alias}_filter-abund.err

# build cli options
khmer_filter_abund_opts=($(buildCommandLineOptions "khmer_filter_abund" "$NAMESPACE" 2>$KMER_FILTER_ABUND_ERROR))
rtrn=$?
cli_opts_failed_msg="[$KMER_FILTER_ABUND_OUTDIR] An error occured while building the khmer_filter_abund command line options for current sample ${!current_sample_alias}."
exit_on_error "$KMER_FILTER_ABUND_ERROR" "$cli_opts_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL
opts="${khmer_filter_abund_opts[@]}"
logger_debug "[$KMER_FILTER_ABUND_OUTDIR] khmer_filter_abund options: $opts"

# build cli
declare -r khmer_filter_abund_C=$(toupper ${NAMESPACE}_khmer_filter_abund)_C
declare -r khmer_filter_abund=$(toupper ${NAMESPACE}_paths)_khmer_filter_abund
eval "$(toupper ${NAMESPACE}_sample)_abundfilt=$OUTPUT_DIR/$KMER_FILTER_ABUND_OUTDIR/${!current_sample_alias}_k${!khmer_load_into_counting_k}_C${!khmer_filter_abund_C}.abundfilt"
declare -r khmer_abundfilt=$(toupper ${NAMESPACE}_sample)_abundfilt

khmer_filter_abund_cli="${!khmer_filter_abund} $opts -o ${!khmer_abundfilt} ${!khmer_hash_count} ${DATA} 2>${FILTER_ABUND_ERROR} | logger_debug &"

# run cli
logger_debug "[$KMER_FILTER_ABUND_OUTDIR] $khmer_filter_abund_cli"
eval "$khmer_filter_abund_cli" 2>$KMER_FILTER_ABUND_ERROR
pid=$!
rtrn=$?
eval_failed_msg="[$KMER_FILTER_ABUND_OUTDIR] An error occured while eval $khmer_filter_abund_cli."
exit_on_error "$KMER_FILTER_ABUND_ERROR" "$eval_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL

# add pid to array
PIDS_ARR=("${PIDS_ARR[@]}" "$pid")
# wait until interleave reads process finish then proceed to next step
# and reinit pid array
pid_list_failed_msg="[$KMER_FILTER_ABUND_OUTDIR] Failed getting process status for process $p."
for p in "${PIDS_ARR[@]}"; do
    logger_trace "$(ps aux | grep $USER | gawk -v pid=$p '$2 ~ pid {print $0}' 2>${KMER_FILTER_ABUND_ERROR})"
    rtrn=$?
    exit_on_error "$KMER_FILTER_ABUND_ERROR" "$pid_list_failed_msg" $rtrn "$OUTPUT_DIR/$LOG_DIR/$DEBUGFILE" $SESSION_TAG $EMAIL
done

### checking errors at start
if [[ -s ${FILTER_ABUND_ERROR} ]] 
	then 
		logger_warn "[$KMER_FILTER_ABUND_OUTDIR] Some messages were thrown to standard error while executing ${!khmer_filter_abund}. See ${FILTER_ABUND_ERROR} file for more details."
	if [[ -n $(grep "Error" $FILTER_ABUND_ERROR) ]]; then
		cat $FILTER_ABUND_ERROR | logger_warn
		logger_fatal $eval_failed_msg
		exit 1
	fi
fi
### end checking errors at start

logger_info "[$KMER_FILTER_ABUND_OUTDIR] Wait for all ${!khmer_filter_abund} processes to finish before proceed to next step."
waitalluntiltimeout "${PIDS_ARR[@]}" 2>/dev/null
logger_info "[$KMER_FILTER_ABUND_OUTDIR] All ${!khmer_filter_abund} processes finished. Will proceed to next step ..."
PIDS_ARR=()
















### close appender
appender_exists kmerFiltAbundF && appender_close kmerFiltAbundF

#=====
# END
#=====

logger_info "[End] Run successfully the pipeline."
logger_info "[End] Will exit now."

# close all appenders
appender_exists stderr && appender_close stderr
appender_exists console && appender_close console
appender_exists debuggerF && appender_close debuggerF

exit 0



























