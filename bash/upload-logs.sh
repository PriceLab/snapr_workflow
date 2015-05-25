#!/bin/bash

if [[ $1 == */ ]]; then
    S3_PATH=${1}logs/
else
    S3_PATH=$1/logs/
fi

UPLOAD_LOG_FILE=$2

SNAPR_WF_HOME="/home/snapr_workflow"

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

NUM_TRIES=0
S3_LS_OUT="onevalue"
FS_LS_OUT="anothervalue"
echo `date` run-id `cat /home/run-id` >> /tmp/log-upload-log.log
while [ "$S3_LS_OUT" != "$FS_LS_OUT"  ] && [ $NUM_TRIES -lt $MAX_S3_UPLOAD_RETRIES ] 
do
    aws s3 cp $UPLOAD_LOG_FILE ${S3_PATH}${UPLOAD_LOG_FILE} >> /tmp/log-upload-log.log 2>&1

    S3_LS_OUT=$(aws s3 ls ${S3_PATH}${UPLOAD_LOG_FILE} | awk '{print $3}' | sort | tr -d ' \t\n\r\f')
    FS_LS_OUT=$(ls -la $UPLOAD_LOG_FILE | awk '{print $5}' | sort | tr -d ' \t\n\r\f')
    if [ "$S3_LS_OUT" != "$FS_LS_OUT" ]; then
        let NUM_TRIES++
        echo `date` S3 upload for $UPLOAD_LOG_FILE has FAILED on trial $NUM_TRIES. Retrying. >> /tmp/log-upload-log.log
    else
        echo `date` S3 upload for $UPLOAD_LOG_FILE has SUCCEEDED on trial $NUM_TRIES. >> /tmp/log-upload-log.log
    fi
done

if [ "$S3_LS_OUT" != "$FS_LS_OUT" ]; then
    let NUM_TRIES++
    echo `date` S3 upload for $UPLOAD_LOG_FILE has FAILED. Giving up. >> /tmp/log-upload-log.log
fi
