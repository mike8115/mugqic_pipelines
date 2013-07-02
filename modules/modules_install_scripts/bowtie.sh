
###################
################### Bowtie2
###################
VERSION="2.1.0"
INSTALL_PATH=$MUGQIC_INSTALL_HOME/software/bowtie/bowtie-$VERSION
mkdir -p $INSTALL_PATH
cd  $INSTALL_PATH

# Download and extract
wget http://sourceforge.net/projects/bowtie-bio/files/bowtie/${VERSION}/bowtie-${VERSION}-src.zip/download

unzip bowtie-$VERSION-src.zip
# Compile
cd bowtie-$VERSION
make -j8

# Module file
echo "#%Module1.0
proc ModulesHelp { } {
       puts stderr \"\tMUGQIC - Bowtie2 aligner \"
}
module-whatis \"MUGQIC - Bowtie2 aligner \"
                      
set             root               \$::env(MUGQIC_INSTALL_HOME)/software/bowtie/bowtie-$VERSION
prepend-path    PATH               \$root
" > $VERSION

# version file
echo "#%Module1.0
set ModulesVersion \"$VERSION\"
" > .version

mkdir -p $MUGQIC_INSTALL_HOME/modulefiles/mugqic/bowtie
mv .version $VERSION $MUGQIC_INSTALL_HOME/modulefiles/mugqic/bowtie/



