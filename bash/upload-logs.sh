#!/bin/bash

if [[ $1 == */ ]]; then
    S3_PATH=${1}logs/
else
    S3_PATH=$1/logs/
fi

SNAPR_WF_HOME="/home/snapr_tools"

if [ -z "$S3_PATH" ]; then
    echo "usage:  $0: <s3-path>"
    exit 1
fi

function logBucketDiff {
    PID=$$
    if [[ $1 == */ ]]; then
        S3_OUT_DIR=$1
    else
        S3_OUT_DIR=$1/
    fi
    LOCAL_DIR=$2
    JOB_NAME=$3
    aws s3 ls $S3_OUT_DIR | awk '{print $3}' | sort > /tmp/s3-output$PID
    ls -la $LOCAL_DIR/job.$JOB_NAME* | awk '{print $5}' | sort > /tmp/fs-output$PID
    echo `diff /tmp/s3-output$PID /tmp/fs-output$PID`
}

# Copy logs to S3
MAX_S3_UPLOAD_RETRIES=5
for jobName in `ls ${SNAPR_WF_HOME}/job.* | awk -F "." '{print $2}' | sort | uniq`
do
    NUM_TRIES=0
    DIFF="  "

    while [ -n "$DIFF" ] && [ $NUM_TRIES -lt $MAX_S3_UPLOAD_RETRIES ] 
    do
        aws s3 cp ${SNAPR_WF_HOME} ${S3_PATH}${jobName}-logs --exclude "*" --include "job.${jobName}*" --recursive
        DIFF=`logBucketDiff ${S3_PATH}${jobName}-logs ${SNAPR_WF_HOME} ${jobName}`
        if [ -n "$DIFF" ]; then
            let NUM_TRIES++
            echo "S3 upload for $jobName jobs in ${SNAPR_WF_HOME} has FAILED on trial $NUM_TRIES. Retrying."
        else
            echo "S3 upload for $jobName jobs in ${SNAPR_WF_HOME} has SUCCEEDED! on trial $NUM_TRIES"
            break
        fi
    done

    if [ -n "$DIFF" ]; then
        echo "S3 upload for $jobName jobs in ${SNAPR_WF_HOME} has FAILED after $NUM_TRIES attempts. Giving up.\n"
    fi
done
