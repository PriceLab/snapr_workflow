#!/bin/sh

#copy fasta and gtf files and create indices for snapr

SNAPR_VOL=/mnt/

ROOT_DIR=/$1/ # input should be name of mounted EBS volume
ASSEMBLY_DIR=${ROOT_DIR}assemblies/human/
ASSEMBLY_NAME=Homo_sapiens.GRCh38
ASSEMBLY_VER=.77

# This should copy at least two files: the fasta and gtf file to the /mnt drive
cp ${ASSEMBLY_DIR}${ASSEMBLY_NAME}* $SNAPR_VOL

# Define SNAPR reference files
SNAPR_EXEC=${ROOT_DIR}bin/snapr/snapr
FASTA_FILE=${SNAPR_VOL}${ASSEMBLY_NAME}.dna.SORTED.fa
GENOME_DIR=${SNAPR_VOL}genome20
TRANSCRIPTOME_DIR=${SNAPR_VOL}transcriptome20
GTF_FILE=${SNAPR_VOL}${ASSEMBLY_NAME}${ASSEMBLY_VER}.gtf

# If these aren't already made on the /mnt drive, make them
if [ ! -e "$GENOME_DIR" ]; then
    mkdir "$GENOME_DIR"
fi

if [ ! -e "$TRANSCRIPTOME_DIR" ]; then
    mkdir "$TRANSCRIPTOME_DIR"
fi

ls $SNAPR_VOL

$SNAPR_EXEC index \
    $FASTA_FILE \
    $GENOME_DIR \
    -bSpace ;

$SNAPR_EXEC transcriptome \
    $GTF_FILE \
    $FASTA_FILE \
    $TRANSCRIPTOME_DIR \
    -bSpace ;
