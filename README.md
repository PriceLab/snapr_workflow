This is a set of simple tools I'm putting together to facilitate running SNAPR on an AWS EC2 cluster instance. The main tasks performed by the scripts below are as follows:

1. Set up environment for running SNAPR on EC2 cluster  
2. Download (in parallel) individual FASTQ/BAM files from specified S3 bucket/directory  
3. Run SNAPR on each FASTQ/BAM file  
4. Upload reprocessed SNAPR BAM files and other outputs to S3

*Note: all scripts under the* `/shell` *directory are deprecated and will be removed soon.*

## Basic infrastructure

The code is designed to run on an AMI that includes all required binaries for running `snapr` or interacting with Amazon S3. Reference files, by default, can be accessed from the S3 bucket s3://snapr-ref-assemblies; these files can also be provided in the local (EC2) environemnt.

Steps in the SNAPR pipeline - including node setup, index building, and alignment - are distributed across cluster nodes using the Sun Grid Engine scheduling system.

##### *Basic example of cluster details*

> **AMI:** ami-079daf37  
> **Instance type:** c3.8xlarge  
> **Availability zone:** us-west-2b


## Getting started

If not already present on the cluster, `cd` to a directory under `/home/` and clone this repository with the following command:

```
user@master:/home# git clone https://github.com/PriceLab/snapr_workflow.git
```

Go ahead and `cd` into the `/home/snapr_workflow/` directory before running any of the scripts below.

## Setting up SNAPR environment

This first script will ensure that solid-state drives (SSDs) are properly mounted on all nodes, set up the expected directory for downstream scripts, copy reference files from S3 and build snapr indices:

```
user@master:/home/snapr_workflow# bash/prep_nodes.sh
```

##### *Setup options*

By default, running this script with no additional inputs will prepare all nodes for `snapr` alignment with the following human reference files:

* **Genome assembly:** Homo_sapiens.GRCh38.dna.SORTED.fa  
* **Transcriptome assembly:** Homo_sapiens.GRCh38.77.gtf  

Additional options for each can be specified using the following arguments: `-g fasta_file` and `-x gtf_file` (to see a list of available reference files, use `aws s3 ls s3://snapr-ref-assemblies`). Note: if you want to copy files for aligning mouse RNA-seq, use the `-s mouse` argument to specify the species.

Other input arguments to `prep_nodes.sh` can be used to specify `qsub` submission settings.


## S3 data transfer and alignment

To run `snapr` on a target set of RNAseq files in an S3 bucket, use `submit_s3_snapr.sh` with the following options to submit an individual `s3_snapr.sh` job for each pair of fastq files or each bam file (using the `-f` flag) in the s3 path. `submit_s3_snapr.sh` will by default look for all pairs of fastq files in the path provided and create a snapr job for each pair. File pairs are determined based on their names so if sample-name-R1.fastq.gz and sample-name-R2.fastq.gz exist in the path they are considered a pair. But using the `-f` option one can instruct `submit_s3_snapr.sh` to look for bam files instead since snapr can reprocess the reads in bam files.

```
user@master:/home/snapr_workflow# bash/submit_s3_snapr.sh -p s3_path -o output_s3_path
```

The `s3_path` and `output_s3_path` inputs should be valid S3 addresses/paths (e.g., s3://seq-file-bucket or s3://seq-file-bucket/subdirectory/). The `-o` is optional in this usage and will defailt to the value of `-p`.

One can also run `snapr` using `submit_s3_snapr.sh` by passing in a file containing a list of s3 paths with the `-L s3_path_list.txt` option, like so:

```
user@master:/home/snapr_workflow# bash/submit_s3_snapr.sh -L s3_path_list.txt -o output_s3_path
```

In this usage the `-o` flag is not optional and the script will throw an error. In addition, it is up to the user to ensure that both mates of the pairs of fastq files are in the file. The pairs in files don't need to be in sequence but the script automatically considers the first mate in the pair it sees as R1 so for consistency the R1 for a pair needs to come before the R2 in the file. Bam files can also be used in lists but not simultaneously with fastq files since the `-f` option informs the script which mode to run in. An example file for fastq files:

```
user@master:/snapr/snapr_workflow# head s3_path_list.txt
s3://seq-file-bucket/Case_Samples/sample1_reads_R1.fastq.gz
s3://seq-file-bucket/Case_Samples/sample1_reads_R2.fastq.gz
s3://seq-file-bucket/Case_Samples/sample2_reads_R1.fastq.gz
s3://seq-file-bucket/Case_Samples/sample2_reads_R2.fastq.gz
```

##### *Submit/data options*

The following input arguments can be used to provide more information about the data to be processed:

###### `-f format (fastq/bam)`

This specifies the file format to search for and download from the S3 bucket. The default format is `fastq`.

###### `-m mode (single/paired)`

Mode specifies whether the data contains single or paired-end reads. If `mode` is `paired` and `format` is `fastq`, the script will automatically group, download, and process the appropriate pair of files for each sample.

###### `-l pair_file_label`

This label or tag denotes the set of characters or regular expression that distinguish between two paired-end read FASTQ files. For example, in the files shown above under the `-L file_list` description, `pair_file_label` would be `"_R[1-2]"`. A default label is included in the script, but I recommend providing this whenever processing paired-end FASTQ files, to ensure that files are accurately grouped.

## Output

Processing (or reprocessing) data with `snapr` will produce the following outputs for each sample:

+ Sorted BAM file [.snap.bam]
+ BAM index file [.snap.bam.bai]
+ Read counts per gene ID [.snap.gene_id.counts.txt]
+ Read counts per gene name [.snap.gene_name.counts.txt]
+ Read counts per transcript ID [.snap.transcript_id.counts.txt]
+ Read counts per transcript name [.snap.transcript_name.counts.txt]

The following outputs are also produced, but will currently be empty files with the current `snapr` settings:

+ [.snap.fusions.reads.fa]
+ [.snap.fusions.txt]
+ [.snap.interchromosomal.fusions.gtf]
+ [.snap.intrachromosomal.fusions.gtf]
+ [.snap.junction_id.counts.txt]
+ [.snap.junction_name.counts.txt]

Files will be saved at `s3://seq-file-bucket/subdir/snapr/`, if the `-s subdir` option is given; otherwise, files will be saved to `s3://seq-file-bucket/snapr/`.

You can also add the `-k` flag when calling `submit_s3_snapr.sh` to prevent output data from being copied back to S3 and keep saved on the cluster node (this is not recommended for large jobs, as disk space would likely fill up). Input and output files for each sample will be saved under `/data/` and `/results/`, respectively, on whichever node the sample was processed.


#### Example: processing paired FASTQ files

For this example, reference assembly files specific to chromosome 8 are provided in the `s3://snapr-ref-assemblies` bucket:

+ **Genome:** Homo_sampiens.GRCh38.dna.chromosome.8.fa
+ **Transcriptome:** chrom8.gtf

**1)**  Use the following command to set up all nodes on the cluster:

```
user@master:/home/snapr_workflow# bash/prep_nodes.sh -g Homo_sampiens.GRCh38.dna.chromosome.8.fa -x chrom8.gtf
```

**2)** Once all `prep_nodes.sh` jobs have finished running (check progress with the `qstat` command), build genome and transcriptome indices on all nodes. 

```
user@master:/home/snapr_workflow# bash/build_indices.sh
```

**3)** Process all paired FASTQ files in the bucket `s3://rna-editing-exdata` under the subdirectory `chr8`.

```
user@master:/home/snapr_workflow# bash/submit_s3_snapr.sh -b s3://rna-editing-exdata -s chr8 -f fastq -m paired -l "_[1-2]"
```

**Note:** You can use the `-d` flag to preview the first job that will be submitted to SGE, along with all inputs that would be provided to `s3_snapr.sh`. The end of the printed output should look like this:

```
### Job settings ###################################################

time bash/s3_snapr.sh -m paired  -l _[1-2] -d s3://rna-editing-exdata/chr8 -1 s3://rna-editing-exdata/chr8/SRR388226chrom8_1.fastq -2 s3://rna-editing-exdata/chr8/SRR388226chrom8_2.fastq -g /resources/genome/ -t /resources/transcriptome/ -x /resources/assemblies/ref-transcriptome.gtf
```

#### Example: reprocessing BAM files

This example also uses the chromosome 8 reference files described above. Steps **(1)** and **(2)** would therefore be identical.

**3)** Process all BAM files in the bucket `s3://rna-editing-exdata` under the subdirectory `chr8`.

```
user@master:/home/snapr_workflow# bash/submit_s3_snapr.sh -b s3://rna-editing-exdata -s chr8 -f bam -m paired
```

With the `-d` flag included, the output should look like this:

```
### Job settings ###################################################

time bash/s3_snapr.sh -m paired -r -d s3://rna-editing-exdata/chr8 -1 s3://rna-editing-exdata/chr8/SRR388226.mq.bam -g /resources/genome/ -t /resources/transcriptome/ -x /resources/assemblies/ref-transcriptome.gtf
```
  
---

### Notes/warnings

+ `snapr` is run with the default options; changing these would currently require modifying the `s3_snapr.sh` code directly.
+ Lots of log files will be generated by SGE for the various steps above; I need to add some mechanisms to collate these logs and add some other relevant metadata about each specific pipeline run.
