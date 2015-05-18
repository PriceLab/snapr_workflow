#!/bin/bash

FASTA_SRC=$1
GTF_SRC=$2

MAX_RETRIES=5

function downloadWithRetries {
    local REMOTE=$1
    local LOCAL=$2

    local RAND=$RANDOM
    local S3_LS_FILE=/tmp/s3-ls-output$RAND
    local LOCAL_LS_FILE=/tmp/local-ls-output$RAND
    local DIFF_FILE=/tmp/s3-local-file-diff$RAND
    touch $DIFF_FILE
    echo "file has to start unempty for the while loop below to work" > $DIFF_FILE
    local NUM_RETRIES=0
    
    echo " beginning download of $REMOTE to $LOCAL"
    while [ -s $DIFF_FILE ] && [ $NUM_RETRIES -lt $MAX_RETRIES ]
    do
        # Download file
        aws s3 cp $REMOTE $LOCAL

        # Get the size in bytes of remote file and downloaded file
        aws s3 ls $REMOTE | awk '{print $3}'  | sort > $S3_LS_FILE
        ls -la $LOCAL | awk '{print $5}' | sort > $LOCAL_LS_FILE
        # See if there is a difference and save to diff file
        diff $S3_LS_FILE $LOCAL_LS_FILE  > $DIFF_FILE

        # If diff file is not empty then that means that there was an error in downloading the files
        if [ -s $DIFF_FILE ]; then
            echo "There was an unknown error in downloading $REMOTE from S3 on trial number $NUM_RETRIES. MAX_RETRIES=$MAX_RETRIES"
        else
            echo "Completed downloading $REMOTE to $LOCAL"
        fi
        let NUM_RETRIES++
    done

    rm /tmp/*$RAND
}


echo "Kicking off parallel download of $FASTA_SRC and $GTF_SRC."

# Kick off gtf file in background to save time and because we know it will complete downloading before the fasta file
# Capture process output into a file we can print to this process's stdout when done
TMP_OUTPUT_FILE=/tmp/background-proc-output$RANDOM
downloadWithRetries $GTF_SRC /resources/assemblies/ref-transcriptome.gtf > $TMP_OUTPUT_FILE 2>&1

downloadWithRetries $FASTA_SRC /resources/assemblies/ref-genome.fa

cat $TMP_OUTPUT_FILE

rm $TMP_OUTPUT_FILE
