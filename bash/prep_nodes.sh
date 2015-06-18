#!/bin/bash

# This script perform the following tasks on each node: 1) mount SSD; 2) create
# standard directories used by downstream code; 3) copy and rename reference
# files to resources directory.

######## Specify defaults & examples ##########################################

# Default options for S3-stored references files
S3_BUCKET="s3://snapr-ref-assemblies"
SPECIES="human"
HUMAN_FASTA="Homo_sapiens.GRCh38.dna.SORTED.fa"
HUMAN_GTF="Homo_sapiens.GRCh38.77.gtf"
MOUSE_FASTA="Mus_musculus.GRCm38.75.dna.SORTED.fa"
MOUSE_GTF="Mus_musculus.GRCm38.75.gtf"
TRANSCRIPTOME_BUILD_OUT=`mktemp tr.XXXXX`

# Default for assuming input ref file is local or on S3
LOCAL=0

# Default options for SGE/qsub parameters
NAME="snapr_node_prep"
QUEUE=all.q
EMAIL="bob@bob.com"

# Default behavior for script (print job settings vs. submit with qsub)
DISPONLY=0

######## Parse inputs #########################################################

function usage {
	echo "$0: [-s species] [-g fasta_file] [-x gtf_file] [-L] [-q queue] [-N jobname] [-M mem(3.8G,15.8G)] [-E email_address] [-d]"
	echo
}


while getopts "s:g:x:Lq:N:E:dh" ARG; do
	case "$ARG" in
	    s ) SPECIES=$OPTARG;;
	    g ) FASTA_FILE=$OPTARG;;
	    x ) GTF_FILE=$OPTARG;;
	    L ) LOCAL=1;;
        q ) QUEUE=$OPTARG;;
		N ) NAME=$OPTARG;;
		E ) EMAIL=$OPTARG;;
	    d ) DISPONLY=1;;
		h ) usage; exit 0;;
		* ) usage; exit 1;;
	esac
done
shift $(($OPTIND - 1))


######## Specify human or mouse specific options ##############################

# Default reference paths
case "$SPECIES" in
    human )
        FASTA_SRC="${S3_BUCKET}/${SPECIES}/${HUMAN_FASTA}"
        GTF_SRC="${S3_BUCKET}/${SPECIES}/${HUMAN_GTF}"
        ;;
    mouse )
        FASTA_SRC="${S3_BUCKET}/${SPECIES}/${MOUSE_FASTA}"
        GTF_SRC="${S3_BUCKET}/${SPECIES}/${MOUSE_GTF}"
        ;;
esac

######## Construct submission file with qsub & job settings ###################

qhost | awk 'NR>2 {print $1}' | grep -v global | while read NODE; do

SUBMIT_FILE=`mktemp node-prep.XXXXXXXX`

cat > $SUBMIT_FILE <<EOF
#!/bin/bash

### SGE settings #################################################

#$ -S /bin/bash
#$ -V

# Change to current working directory (otherwise starts in $HOME)
#$ -cwd

# Set the name of the job
#$ -N job.${NAME}

# Combine output and error files into single output file (y=yes, n=no)
#$ -j y

# Specify the current node
#$ -l h=${NODE}

# Specify my email address for notification
#$ -M $EMAIL

# Specify what events to notify me for
# 'b'=job begins, 'e'=job ends, 'a'=job aborts, 's'=job suspended, 'n'=no email
#$ -m beas


### Job settings ###################################################


# Mount the SS hard drive (if not already mounted)

if ( ! df | awk '{print $1}' | grep -q xvdaa ); then
	sudo mkfs.ext4 /dev/xvdaa
	sudo mkdir -m 000 /mnt # isnt required if /mnt exists.
	echo "/dev/xvdaa /mnt auto noatime 0 0" | sudo tee -a /etc/fstab
	sudo mount /mnt
fi

# Create standard directories & symlinks

if [ ! -e "/mnt/resources" ]; then
    mkdir /mnt/resources
    ln -s /mnt/resources /resources

    # Create resource sub-directories

    mkdir /resources/assemblies
    mkdir /resources/genome
    mkdir /resources/transcriptome
fi

if [ ! -e "/mnt/data" ]; then
    mkdir /mnt/data
    ln -s /mnt/data /data
fi

if [ ! -e "/mnt/results/" ]; then
    mkdir /mnt/results
    ln -s /mnt/results /results
fi

# Install AWS CLI (this shouldn't be necessary once added to AMI)
# pip install awscli

export AWS_ACCESS_KEY_ID=$(head -1 /root/.isb)
export AWS_SECRET_ACCESS_KEY=$(tail -1 /root/.isb)
export AWS_DEFAULT_REGION=$(ec2metadata | grep availability-zone | cut -d ' ' -f 2)

# Copy and rename assembly files from S3

if [ $LOCAL == 0 ]; then
    time /home/snapr_workflow/bash/download_assemblies.sh $FASTA_SRC $GTF_SRC
else
    cp $FASTA_FILE /resources/assemblies/ref-genome.fa ;
    cp $GTF_FILE /resources/assemblies/ref-transcriptome.gtf ;
fi

# Build transcriptome index
time snapr transcriptome /resources/assemblies/ref-transcriptome.gtf /resources/assemblies/ref-genome.fa /resources/transcriptome/ -bSpace > $TRANSCRIPTOME_BUILD_OUT 2>&1 &

# Build genome index
time snapr index /resources/assemblies/ref-genome.fa /resources/genome/ -bSpace 

cat $TRANSCRIPTOME_BUILD_OUT

EOF

if [ $DISPONLY == 1 ]; then
    echo "#$ QSUBOPTS"
    cat $SUBMIT_FILE
else
    echo "Prepping node $NODE"
    echo
    qsub $QSUBOPTS < $SUBMIT_FILE
fi

rm $SUBMIT_FILE

done
