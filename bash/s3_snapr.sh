#!/bin/bash

# Given a path to a file on S3 (or two files, in the case of paired-end FASTQ
# data, this script downloads the data, processes the file(s) with SNAPR, and
# uploads the results back to the original bucket.

######## Specify defaults & examples ##########################################

# Default options for file format and alignment mode
MODE=paired
REPROCESS=0
PAIR_LABEL="_R[1-2]_"

# Default reference paths
GENOME="/resources/genome/"
TRANSCRIPTOME="/resources/transcriptome/"
GTF_FILE="/resources/assemblies/ref-transcriptome.gtf"

# Default behavior for script
KEEP=0 # 0: upload outputs to S3 vs. 1: keep on local machine

######## Parse inputs #########################################################

function usage {
	echo "$0: [-m mode (paired/single)] [-r] -d dir_name -1 s3://path_to_file [-2 s3://path_to_paired_file] [-l pair_file_label] [-g genome_index] [-t transcriptome_index] [-x ref_transcriptome] [-k]"
	echo
}

while getopts "m:rd:1:2:l:g:t:x:kh" ARG; do
	case "$ARG" in
	    m ) MODE=$OPTARG;;
	    r ) REPROCESS=1;;
		d ) S3_DIR=$OPTARG;;
	    1 ) PATH1=$OPTARG;;
	    2 ) PATH2=$OPTARG;;
	    l ) PAIR_LABEL=$OPTARG;;
	    g ) GENOME=$OPTARG;;
	    t ) TRANSCRIPTOME=$OPTARG;;
	    x ) GTF_FILE=$OPTARG;;
	    k ) KEEP=1;;
	    h ) usage; exit 0;;
	    * ) usage; exit 1;;
	esac
done
shift $(($OPTIND - 1))


######## Assemble & prepare data for snapr ####################################

# Parse S3 file path
FILE_NAME=${PATH1##*/}

if ( echo $FILE_NAME | grep -q .gz );
then
    PREFIX=${FILE_NAME%.*.*};
else
    PREFIX=${FILE_NAME%.*};
fi

# If processing multiple FASTQ files, create a single name for the output file
if [ $MODE == paired ] && [ $REPROCESS == 0 ];
then
    PREFIX=$(echo $PREFIX \
        | awk -v tag="$PAIR_LABEL" '{gsub(tag, "")}1')
fi

# Create temporary directory for input files
TMP_DIR=/data/${PREFIX}_tmp/
if [ ! -e "$TMP_DIR" ]; then
    mkdir "$TMP_DIR"
fi

FILE1=${TMP_DIR}${FILE_NAME}

# Download S3 files
echo "Copying $PATH1 to $FILE1"

MAX_S3_UPLOAD_RETRIES=5
NUM_TRIES=0
S3_LS_OUT="onevalue"
FS_LS_OUT="anothervalue"
while [ "$S3_LS_OUT" != "$FS_LS_OUT"  ] && [ $NUM_TRIES -lt $MAX_S3_UPLOAD_RETRIES ] 
do
    aws s3 cp $PATH1 $FILE1 
    
    S3_LS_OUT=$(aws s3 ls $PATH1 | awk '{print $3}' | sort | tr -d ' \t\n\r\f')
    FS_LS_OUT=$(ls -la $FILE1 | awk '{print $5}' | sort | tr -d ' \t\n\r\f')
    if [ "$S3_LS_OUT" != "$FS_LS_OUT" ]; then
        let NUM_TRIES++
        echo S3 upload for $PATH1 has FAILED on trial $NUM_TRIES. Retrying.
    else
        echo S3 download for $PATH1 has SUCCEEDED on trial $NUM_TRIES. 
    fi
done

echo

# Get second FASTQ file if necessary
if [ $MODE == paired ] && [ $REPROCESS = 0 ];
then
    FILE2=${TMP_DIR}${PATH2##*/}

    echo "Copying $PATH2 to $FILE2"

    NUM_TRIES=0
    S3_LS_OUT="onevalue"
    FS_LS_OUT="anothervalue"
    while [ "$S3_LS_OUT" != "$FS_LS_OUT"  ] && [ $NUM_TRIES -lt $MAX_S3_UPLOAD_RETRIES ] 
    do
        aws s3 cp $PATH2 $FILE2

        S3_LS_OUT=$(aws s3 ls $PATH2 | awk '{print $3}' | sort | tr -d ' \t\n\r\f')
        FS_LS_OUT=$(ls -la $FILE2 | awk '{print $5}' | sort | tr -d ' \t\n\r\f')
        if [ "$S3_LS_OUT" != "$FS_LS_OUT" ]; then
            let NUM_TRIES++
            echo S3 upload for $PATH2 has FAILED on trial $NUM_TRIES. Retrying.
        else
            echo S3 download for $PATH2 has SUCCEEDED on trial $NUM_TRIES. 
        fi
    done
fi
echo

# Define set of input files; if FILE2 is unassigned, only FILE1 will be used
INPUT="${FILE1} ${FILE2}"

######## Assemble options for running snapr ##################################

SNAPR_EXEC="snapr"

# Define SNAPR output file
OUT_DIR=/results/${PREFIX}_results/
mkdir "$OUT_DIR"
OUTPUT_FILE=${OUT_DIR}${PREFIX}.snap.bam

REF_FILES="${GENOME} ${TRANSCRIPTOME} ${GTF_FILE}"
OTHER="-b -M -rg ${PREFIX} -so -ku"

SNAPR_OPTIONS="${MODE} ${REF_FILES} ${INPUT} -o ${OUTPUT_FILE} ${OTHER}"

echo "$SNAPR_EXEC $SNAPR_OPTIONS"

# Run SNAPR
time $SNAPR_EXEC $SNAPR_OPTIONS

# Sort output with samtools and get rid of unsorted file
#SAMTOOLS_COMMAND="samtools sort -@ `nproc` -m 50G ${OUTPUT_FILE} ${OUT_DIR}${PREFIX}.snap.sorted.bam"
#echo "Sorting output with samtools. Command: " $SAMTOOLS_COMMAND
#time $SAMTOOLS_COMAND #&& rm ${OUTPUT_FILE}

######## Copy and clean up results ############################################

UUID=$(cat /home/run-id)
SNAPR_RUN_DIR=${S3_DIR}snapr-run-$UUID
MAX_S3_UPLOAD_RETRIES=5
NUM_TRIES=0

if [ ${KEEP} == 0 ]; then
    S3_LS_OUT="onevalue"
    FS_LS_OUT="anothervalue"
    while [ "$S3_LS_OUT" != "$FS_LS_OUT" ] && [ $NUM_TRIES -lt $MAX_S3_UPLOAD_RETRIES ] 
    do
        # Copy snapr output files to S3
        aws s3 cp \
        $OUT_DIR \
        $SNAPR_RUN_DIR/output-data \
        --recursive --exclude "*.tmp" ;

        S3_LS_OUT=$(aws s3 ls ${SNAPR_RUN_DIR}/output-data/ | awk '{print $3}' | grep -v ".*\.tmp$" | sort | tr -d ' \t\n\r\f')
        FS_LS_OUT=$(ls -la $OUT_DIR | awk '{print $5}' | tail -n +4 | grep -v ".*\.tmp$" | sort | tr -d ' \t\n\r\f')

	echo s3 ls is: `aws s3 ls ${SNAPR_RUN_DIR}/output-data/`
	echo fs ls is: `ls -la $OUT_DIR`
	echo s3 output is $S3_LS_OUT
        echo fs output is $FS_LS_OUT
        if [ "$S3_LS_OUT" != "$FS_LS_OUT" ]; then
            let NUM_TRIES++
	    echo "S3 upload for $OUT_DIR has FAILED on trial $NUM_TRIES. Retrying."
	else
	    echo "S3 upload for $OUT_DIR has SUCCEEDED! on trial $NUM_TRIES"
	fi
    done

    if [ "$S3_LS_OUT" != "$FS_LS_OUT" ]; then
        echo "S3 upload for $OUT_DIR has FAILED after $NUM_TRIES attempts. Giving up."
        echo `date` Uploading logs for run-id: `cat /home/run-id` >> log-upload.log
        /home/snapr_workflow/bash/upload-logs.sh $SNAPR_RUN_DIR log-upload.log >> log-upload.log 2>&1
        exit 1 # We don't want to delete $TMP_DIR and $OUT_DIR if upload failed
    fi

    # Remove temporary directories
    rm -rf $TMP_DIR
	rm -rf $OUT_DIR
fi

echo Completed output upload. Beginning log upload
echo
echo `date` Uploading logs for run-id: `cat /home/run-id` >> log-upload.log
/home/snapr_workflow/bash/upload-logs.sh $SNAPR_RUN_DIR log-upload.log >> log-upload.log 2>&1
