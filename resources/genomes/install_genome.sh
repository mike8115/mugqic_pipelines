#!/bin/bash
# Exit immediately on error
set -eu -o pipefail

module_bowtie=mugqic/bowtie/2.1.0
module_bwa=mugqic/bwa/0.7.10
module_java=mugqic/java/openjdk-jdk1.7.0_60
module_mugqic_R_packages=mugqic/mugqic_R_packages/0.1
module_picard=mugqic/picard/1.108
module_R=mugqic/R_Bioconductor/3.1.2_3.0
module_samtools=mugqic/samtools/0.1.19
module_star=mugqic/star/2.4.0e
module_tophat=mugqic/tophat/2.0.11

init_install() {
  # '$MUGQIC_INSTALL_HOME_DEV' for development, '$MUGQIC_INSTALL_HOME' for production
  INSTALL_HOME=$MUGQIC_INSTALL_HOME_DEV

  INSTALL_DIR=$INSTALL_HOME/genomes/species/$SPECIES.$ASSEMBLY
  DOWNLOAD_DIR=$INSTALL_DIR/downloads
  LOG_DIR=$INSTALL_DIR/log
  TIMESTAMP=`date +%FT%H.%M.%S`

  # Standard names for our genome files whatever the source
  GENOME_DIR=$INSTALL_DIR/genome
  GENOME_FASTA=$SPECIES.$ASSEMBLY.fa
  ANNOTATIONS_DIR=$INSTALL_DIR/annotations
  GTF=$SPECIES.$ASSEMBLY.$SOURCE$VERSION.gtf
  NCRNA=$SPECIES.$ASSEMBLY.$SOURCE$VERSION.ncrna.fa
  RRNA=$SPECIES.$ASSEMBLY.$SOURCE$VERSION.rrna.fa
  VCF=$SPECIES.$ASSEMBLY.$SOURCE$VERSION.vcf.gz
  GO=$SPECIES.$ASSEMBLY.$SOURCE$VERSION.GO.tsv

  echo Installing genome for:
  echo species: $SPECIES
  echo assembly: $ASSEMBLY
  echo source: $SOURCE
  echo in: $INSTALL_DIR
  echo

  # Create install directory with permissions if necessary
  if [[ ! -d $INSTALL_DIR ]] ; then mkdir -p $INSTALL_DIR ; fi

  # Create subdirectories
  mkdir -p $DOWNLOAD_DIR $LOG_DIR $GENOME_DIR $ANNOTATIONS_DIR
}

download_path() {
  URL=$1

  # Download path is the URL without protocol prefix
  echo $DOWNLOAD_DIR/`echo $URL | perl -pe 's,^[^:]*://,,'`
}

download_url() {
  URL=$1

  echo
  echo Downloading $URL...
  echo

  cd $DOWNLOAD_DIR
  wget -r -c $URL
}

set_urls() {
  #
  # Ensembl (vertebrate species)
  #
  if [[ $SOURCE == "Ensembl" ]]
  then
    URL_PREFIX=ftp://ftp.ensembl.org/pub/release-$VERSION
    GENOME_URL=$URL_PREFIX/fasta/${SPECIES,,}/dna/$SPECIES.$ASSEMBLY.dna.primary_assembly.fa.gz
    NCRNA_URL=$URL_PREFIX/fasta/${SPECIES,,}/ncrna/$SPECIES.$ASSEMBLY.ncrna.fa.gz
    GTF_URL=$URL_PREFIX/gtf/${SPECIES,,}/$SPECIES.$ASSEMBLY.$VERSION.gtf.gz
    VCF_URL=$URL_PREFIX/variation/vcf/${SPECIES,,}/$SPECIES.vcf.gz
    BIOMART_MART=ENSEMBL_MART_ENSEMBL
    # Retrieve species short name e.g. "mmusculus" for "Mus_musculus"
    SPECIES_SHORT_NAME=`echo ${SPECIES:0:1}${SPECIES#*_} | tr [:upper:] [:lower:]`
    BIOMART_DATASET=${SPECIES_SHORT_NAME}_gene_ensembl
    BIOMART_GENE_ID=ensembl_gene_id
    BIOMART_GO_ID=go_id
    BIOMART_GO_NAME=name_1006
    BIOMART_GO_DEFINITION=definition_1006
  
    # Before Ensembl release 76, release number was added in genome and ncrna file names
    if [ $VERSION -lt 76 ]
    then
      GENOME_URL=${GENOME_URL/$SPECIES.$ASSEMBLY/$SPECIES.$ASSEMBLY.$VERSION}
      NCRNA_URL=${NCRNA_URL/$SPECIES.$ASSEMBLY/$SPECIES.$ASSEMBLY.$VERSION}
    fi
  
    # Check if a genome primary assembly is available for this species, otherwise use the toplevel assembly
    set +e
    wget --spider $GENOME_URL
    EXIT_CODE=$?
    set -e
    if [ $EXIT_CODE != 0 ]
    then
      echo Primary assembly not available for $SPECIES, use toplevel assembly instead
      GENOME_URL=${GENOME_URL/primary_assembly/toplevel}
    fi

    # Check if a VCF is available for this species
    set +e
    wget --spider $VCF_URL
    EXIT_CODE=$?
    set -e
    if [ $EXIT_CODE != 0 ]
    then
      echo VCF not available for $SPECIES
      VCF_URL=
    fi
  
  #
  # Ensembl Genomes (non-vertebrate species)
  #
  elif [[ $SOURCE == "EnsemblGenomes" ]]
  then
    RELEASE_URL=ftp://ftp.ensemblgenomes.org/pub/release-$VERSION
  
    # Retrieve Ensembl Genomes species information
    SPECIES_URL=$RELEASE_URL/species.txt
    download_url $SPECIES_URL
    SPECIES_LINE="`awk -F"\t" -v species=${SPECIES,,} '$2 == species' $(download_path $SPECIES_URL)`"

    # Retrieve species division (Bacteria|Fungi|Metazoa|Plants|Protists)
    DIVISION=`echo "$SPECIES_LINE" | cut -f3 | sed "s/^Ensembl//"`
  
    # Escherichia coli bacteria file paths are different
    # Retrieve which bacteria collection it belongs to and adjust paths accordingly
    CORE_DB_PREFIX=`echo "$SPECIES_LINE" | cut -f13 | perl -pe "s/_core_${VERSION}_\d+_\d+//"`
    if [[ $CORE_DB_PREFIX != ${SPECIES,,} ]]
    then
      EG_SPECIES=$CORE_DB_PREFIX/${SPECIES,,}
      EG_BASENAME=$SPECIES.`echo "$SPECIES_LINE" | cut -f6`.$VERSION
    else
      EG_SPECIES=${SPECIES,,}
      EG_BASENAME=$SPECIES.$ASSEMBLY.$VERSION
    fi
  
    URL_PREFIX=$RELEASE_URL/${DIVISION,}
    GENOME_URL=$URL_PREFIX/fasta/$EG_SPECIES/dna/$EG_BASENAME.dna.genome.fa.gz
    NCRNA_URL=$URL_PREFIX/fasta/$EG_SPECIES/ncrna/$EG_BASENAME.ncrna.fa.gz
    GTF_URL=$URL_PREFIX/gtf/$EG_SPECIES/$EG_BASENAME.gtf.gz
    if [[ `echo "$SPECIES_LINE" | cut -f13` == "Y"  ]]
    then
      VCF_URL=$URL_PREFIX/vcf/${SPECIES,,}/${SPECIES,,}.vcf.gz
    else
      echo VCF not available for $SPECIES
    fi
    # Retrieve species short name e.g. "athaliana" for "Arabidopsis_thaliana"
    SPECIES_SHORT_NAME=`echo ${SPECIES:0:1}${SPECIES#*_} | tr [:upper:] [:lower:]`
    BIOMART_DATASET=${SPECIES_SHORT_NAME}_eg_gene
    BIOMART_GENE_ID=ensembl_gene_id
    BIOMART_GO_ID=go_accession
    BIOMART_GO_NAME=go_name_1006
    BIOMART_GO_DEFINITION=go_definition_1006
  fi
}

download_urls() {
  download_url $GENOME_URL
  download_url $GTF_URL
  download_url $NCRNA_URL
  if [ ! -z "${VCF_URL:-}" ]
  then
    download_url $VCF_URL
  fi
}

# Test genome size to decide whether indexing requires more cores or memory
is_genome_big() {
  GENOME_SIZE_LIMIT=200000000

  if [ `stat --printf="%s" $GENOME_DIR/$GENOME_FASTA` -gt $GENOME_SIZE_LIMIT ]
  then
    return 0
  else
    return 1
  fi
}

# Test if a list of files given as parameters exist, are regular files and are not zero size
is_up2date() {
  # By default, files are up to date
  IS_UP2DATE=0

  for f in $@
  do
    if [[ ! -f $f || ! -s $f ]]
    then
      IS_UP2DATE=1
    fi
  done

  return $IS_UP2DATE
}

cmd_or_job() {
  CMD=$1
  JOB_PREFIX=${3:-$CMD}  # Job prefix = 3rd param if defined else cmd name

  # If genome is too big, run command in a separate job since login node memory is limited
  if is_genome_big
  then
    echo
    echo Submitting $JOB_PREFIX as job...
    echo
    CORES=${2:-1}  # Nb cores = 2nd param if defined else 1
    echo "${!CMD}" | qsub -m ae -M $JOB_MAIL -W umask=0002 -d $INSTALL_DIR -j oe -o $LOG_DIR/${JOB_PREFIX}_$TIMESTAMP.log -N $JOB_PREFIX.$GENOME_FASTA -l walltime=24:00:0 -q sw -l nodes=1:ppn=$CORES
  else
    echo
    echo Running $JOB_PREFIX...
    echo
    echo "${!CMD}" | bash
  fi
}

create_picard_index() {
  GENOME_DICT=$GENOME_DIR/${GENOME_FASTA/.fa/.dict}

  if ! is_up2date $GENOME_DICT
  then
    echo
    echo Creating genome Picard sequence dictionary...
    echo
    module load $module_picard $module_java
    java -jar $PICARD_HOME/CreateSequenceDictionary.jar REFERENCE=$GENOME_DIR/$GENOME_FASTA OUTPUT=$GENOME_DICT GENOME_ASSEMBLY=${GENOME_FASTA/.fa} > $LOG_DIR/picard_$TIMESTAMP.log 2>&1
  else
    echo
    echo Genome Picard sequence dictionary up to date... skipping
    echo
  fi
}

create_samtools_index() {
  if ! is_up2date $GENOME_DIR/$GENOME_FASTA.fai
  then
    echo
    echo Creating genome SAMtools FASTA index...
    echo
    module load $module_samtools
    samtools faidx $GENOME_DIR/$GENOME_FASTA > $LOG_DIR/samtools_$TIMESTAMP.log 2>&1
  else
    echo
    echo Genome SAMtools FASTA index up to date... skipping
    echo
  fi
}

create_bwa_index() {
  INDEX_DIR=$GENOME_DIR/bwa_index
  if ! is_up2date $INDEX_DIR/$GENOME_FASTA.sa
  then
    echo
    echo Creating genome BWA index...
    echo
    BWA_CMD="\
mkdir -p $INDEX_DIR && \
ln -s -f -t $INDEX_DIR ../$GENOME_FASTA && \
module load $module_bwa && \
LOG=$LOG_DIR/bwa_$TIMESTAMP.log && \
bwa index $INDEX_DIR/$GENOME_FASTA > \$LOG 2>&1 && \
chmod -R ug+rwX,o+rX $INDEX_DIR \$LOG"
    cmd_or_job BWA_CMD 2
  else
    echo
    echo Genome BWA index up to date... skipping
    echo
  fi
}

create_bowtie2_tophat_index() {
  BOWTIE2_INDEX_DIR=$GENOME_DIR/bowtie2_index
  BOWTIE2_INDEX_PREFIX=$BOWTIE2_INDEX_DIR/${GENOME_FASTA/.fa}
  TOPHAT_INDEX_DIR=$ANNOTATIONS_DIR/gtf_tophat_index
  TOPHAT_INDEX_PREFIX=$TOPHAT_INDEX_DIR/${GTF/.gtf}

  if ! is_up2date $BOWTIE2_INDEX_PREFIX.[1-4].bt2 $BOWTIE2_INDEX_PREFIX.rev.[12].bt2 $TOPHAT_INDEX_PREFIX.[1-4].bt2 $TOPHAT_INDEX_PREFIX.rev.[12].bt2
  then
    echo
    echo Creating genome Bowtie 2 index and gtf TopHat index...
    echo
    BOWTIE2_TOPHAT_CMD="\
mkdir -p $BOWTIE2_INDEX_DIR && \
ln -s -f -t $BOWTIE2_INDEX_DIR ../$GENOME_FASTA && \
module load $module_bowtie && \
LOG=$LOG_DIR/bowtie2_$TIMESTAMP.log && \
bowtie2-build $BOWTIE2_INDEX_DIR/$GENOME_FASTA $BOWTIE2_INDEX_PREFIX > \$LOG 2>&1 && \
chmod -R ug+rwX,o+rX $BOWTIE2_INDEX_DIR \$LOG && \
mkdir -p $TOPHAT_INDEX_DIR && \
ln -s -f -t $TOPHAT_INDEX_DIR ../$GTF && \
module load $module_samtools $module_tophat && \
LOG=$LOG_DIR/gtf_tophat_$TIMESTAMP.log && \
tophat --output-dir $TOPHAT_INDEX_DIR/tophat_out --GTF $TOPHAT_INDEX_DIR/$GTF --transcriptome-index=$TOPHAT_INDEX_PREFIX $BOWTIE2_INDEX_PREFIX > \$LOG 2>&1 && \
chmod -R ug+rwX,o+rX \$TOPHAT_INDEX_DIR \$LOG"
  cmd_or_job BOWTIE2_TOPHAT_CMD 2
  else
    echo
    echo Genome Bowtie 2 index and gtf TopHat index up to date... skipping
    echo
  fi
}

create_star_index() {
  if is_genome_big
  then
    runThreadN=6
  else
    runThreadN=1
  fi

  for sjdbOverhang in 49 99
  do
    INDEX_DIR=$INSTALL_DIR/genome/star_index/$SOURCE$VERSION.sjdbOverhang$sjdbOverhang
    if ! is_up2date $INDEX_DIR/SAindex
    then
      echo
      echo Creating STAR index with sjdbOverhang $sjdbOverhang...
      echo
      STAR_CMD="\
mkdir -p $INDEX_DIR && \
module load $module_star && \
LOG=$LOG_DIR/star_${sjdbOverhang}_$TIMESTAMP.log && \
STAR --runMode genomeGenerate --genomeDir $INDEX_DIR --genomeFastaFiles $GENOME_DIR/$GENOME_FASTA --runThreadN $runThreadN --sjdbOverhang $sjdbOverhang --sjdbGTFfile $ANNOTATIONS_DIR/$GTF --outFileNamePrefix $INDEX_DIR/ > \$LOG 2>&1 && \
chmod -R ug+rwX,o+rX $INDEX_DIR \$LOG"
      cmd_or_job STAR_CMD $runThreadN STAR_${sjdbOverhang}_CMD
    else
      echo
      echo STAR index with sjdbOverhang $sjdbOverhang up to date... skipping
      echo
    fi
  done
}

create_ncrna_bwa_index() {
  INDEX_DIR=$ANNOTATIONS_DIR/ncrna_bwa_index
  if ! is_up2date $INDEX_DIR/$NCRNA.sa
  then
    echo
    echo Creating ncRNA BWA index...
    echo
    mkdir -p $INDEX_DIR
    ln -s -f -t $INDEX_DIR ../$NCRNA
    module load $module_bwa
    bwa index $INDEX_DIR/$NCRNA > $LOG_DIR/ncrna_bwa_$TIMESTAMP.log 2>&1
  else
    echo
    echo ncRNA BWA index up to date... skipping
    echo
  fi
}

create_rrna_bwa_index() {
  if is_up2date $ANNOTATIONS_DIR/$RRNA
  then
    INDEX_DIR=$ANNOTATIONS_DIR/rrna_bwa_index
    if ! is_up2date $INDEX_DIR/$RRNA.sa
    then
      echo
      echo Creating rRNA BWA index...
      echo
      mkdir -p $INDEX_DIR
      ln -s -f -t $INDEX_DIR ../$RRNA
      module load $module_bwa
      bwa index $INDEX_DIR/$RRNA > $LOG_DIR/ncrna_bwa_$TIMESTAMP.log 2>&1
    else
      echo
      echo rRNA BWA index up to date... skipping
      echo
    fi
  fi
}

create_gene_annotations() {
  ANNOTATION_PREFIX=$ANNOTATIONS_DIR/${GTF/.gtf}

  if ! is_up2date $ANNOTATION_PREFIX.genes.length.tsv $ANNOTATION_PREFIX.geneid2Symbol.tsv $ANNOTATION_PREFIX.genes.tsv
  then
    echo
    echo Creating gene ID, symbol, length annotations from GTF...
    echo
    cd $ANNOTATIONS_DIR
    module load $module_R
    module load $module_mugqic_R_packages
    R --no-restore --no-save<<EOF
suppressPackageStartupMessages(library(gqSeqUtils))
gtf.fn     = "$GTF"
annotation = "$ANNOTATION_PREFIX"

genes = extractGeneAnnotationFromGtf(gtf.fn, feature.types = c("exon", "CDS"))
# NOTE: feature.types passed down to gqSeqUtils::calculateGeneLengthsFromGtf

write.table(genes[,c("featureID","gene.length"),],
  file = paste0(annotation, ".genes.length.tsv"), sep='\t', quote=F, row.names=F, col.names=F) # NOTE: this should not be necessary, all is in genes anyway

write.table(data.frame("ensembl"=genes[["featureID"]], "geneSymbol"=genes[["SYMBOL"]]),
  file = paste0(annotation, ".geneid2Symbol.tsv"), sep='\t', quote=F, row.names=F, col.names=F) # NOTE: this should not be necessary, all is in genes anyway

write.table(genes, file = paste0(annotation, ".genes.tsv"), sep='\t', quote=F, row.names=F, col.names=T)

EOF
  else
    echo
    echo Gene ID, symbol, length annotations from GTF up to date... skipping
    echo
  fi
}

create_go_annotations() {

  if [ ! -z "${BIOMART_HOST:-}" ]
  then
    if ! is_up2date $ANNOTATIONS_DIR/$GO
    then
      echo
      echo Retrieving GO annotations using BioMart...
      echo
      module load $module_R
      module load $module_mugqic_R_packages
      R --no-restore --no-save<<EOF
suppressPackageStartupMessages(library(gqSeqUtils))
res = getBMsimple("$BIOMART_HOST","$BIOMART_MART","$BIOMART_DATASET",c("$BIOMART_GENE_ID", "$BIOMART_GO_ID", "$BIOMART_GO_NAME", "$BIOMART_GO_DEFINITION"))
res = res[ res[["$BIOMART_GENE_ID"]] != '' & res[["$BIOMART_GO_ID"]] != '', ]
write.table(res, file="$ANNOTATIONS_DIR/$GO", quote=FALSE,sep='\t',col.names=FALSE,row.names=FALSE)
EOF
    else
      echo
      echo GO annotations up to date... skipping
      echo
    fi
  fi
}

get_vcf_dbsnp() {
  # Try to retrieve VCF dbSNP latest version (set +e since zgrep exit code != 0 if not found)
  set +e
  DBSNP_VERSION=`zcat $ANNOTATIONS_DIR/$VCF | grep -v "^#" | cut -f8 | grep -Po "dbSNP_\d+" | sed s/dbSNP_// | sort -ug | tail -1`
  set -e
  echo Found VCF dbSNP version: $DBSNP_VERSION
  if [ $DBSNP_VERSION ]
  then
    # Add dbSNP version to VCF filename
    ln -s -f $VCF $ANNOTATIONS_DIR/$SPECIES.$ASSEMBLY.dbSNP$DBSNP_VERSION.vcf.gz
  fi
}

copy_files() {
  # Uncompress files
  if ! is_up2date $GENOME_DIR/$GENOME_FASTA ; then gunzip -c `download_path $GENOME_URL` > $GENOME_DIR/$GENOME_FASTA ; fi
  if ! is_up2date $ANNOTATIONS_DIR/$GTF ; then gunzip -c `download_path $GTF_URL` > $ANNOTATIONS_DIR/$GTF ; fi
  TRANSCRIPT_ID_GTF=$ANNOTATIONS_DIR/${GTF/.gtf/.transcript_id.gtf}
  if ! is_up2date $TRANSCRIPT_ID_GTF ; then grep -P "(^#|transcript_id)" $ANNOTATIONS_DIR/$GTF > $TRANSCRIPT_ID_GTF ; fi
  if ! is_up2date $ANNOTATIONS_DIR/$NCRNA ; then gunzip -c `download_path $NCRNA_URL` > $ANNOTATIONS_DIR/$NCRNA ; fi

  # Create rRNA FASTA as subset of ncRNA FASTA keeping only sequences with "gene_biotype:rRNA" in their description
  if [ $(grep -q "gene_biotype:rRNA" $ANNOTATIONS_DIR/$NCRNA)$? == 0 ]
  then
    if ! is_up2date $ANNOTATIONS_DIR/$RRNA
    then
      grep -Pzo "^>.*gene_biotype:rRNA[^>]*" $ANNOTATIONS_DIR/$NCRNA | grep -v "^$" > $ANNOTATIONS_DIR/$RRNA
    fi
  fi

  if [ ! -z "${VCF_URL:-}" ]
  then
    if ! is_up2date $ANNOTATIONS_DIR/$VCF
    then
      cp `download_path $VCF_URL` $ANNOTATIONS_DIR/$VCF
      get_vcf_dbsnp
    fi
  fi
}

build_files() {
  # Create indexes
  create_picard_index
  create_samtools_index
  create_bwa_index
  create_bowtie2_tophat_index
  create_star_index
  create_ncrna_bwa_index
  create_rrna_bwa_index
  create_gene_annotations
  create_go_annotations
}

create_genome_ini_file() {
  echo "\
[DEFAULT]
scientific_name=$SPECIES
common_name=$COMMON_NAME
assembly=$ASSEMBLY
assembly_synonyms=$ASSEMBLY_SYNONYMS
source=$SOURCE
version=$VERSION" > $INSTALL_DIR/$SPECIES.$ASSEMBLY.ini
}

install_genome() {

  SPECIES="$1"
  COMMON_NAME="$2"
  ASSEMBLY="$3"
  ASSEMBLY_SYNONYMS="$4"
  SOURCE="$5"
  VERSION="$6"

  init_install
  set_urls
  download_urls
  copy_files
  build_files
  create_genome_ini_file

  # Add permissions
  chmod -R ug+rwX,o+rX $INSTALL_DIR
}