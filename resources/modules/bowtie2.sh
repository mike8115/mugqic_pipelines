#!/bin/bash
# Exit immediately on error
set -eu -o pipefail

SOFTWARE=bowtie2
VERSION=2.2.4
ARCHIVE=$SOFTWARE-$VERSION-source.zip
ARCHIVE_URL=http://sourceforge.net/projects/bowtie-bio/files/$SOFTWARE/$VERSION/$ARCHIVE
SOFTWARE_DIR=$SOFTWARE-$VERSION

# 'MUGQIC_INSTALL_HOME_DEV' for development, 'MUGQIC_INSTALL_HOME' for production (don't write '$' before!)
# 'MUGQIC_INSTALL_HOME' must be explicitely passed as first parameter, otherwise 'MUGQIC_INSTALL_HOME_DEV' is used
INSTALL_HOME=${1:-MUGQIC_INSTALL_HOME_DEV}

# Specific commands to extract and build the software
# $INSTALL_DIR and $INSTALL_DOWNLOAD have been set automatically
# $ARCHIVE has been downloaded in $INSTALL_DOWNLOAD
build() {
  cd $INSTALL_DOWNLOAD
  unzip $ARCHIVE

  cd $SOFTWARE_DIR
  make -j8

  # Install software
  cd $INSTALL_DOWNLOAD
  mv -i $SOFTWARE_DIR $INSTALL_DIR/
}

# Module file
MODULE_FILE="\
#%Module1.0
proc ModulesHelp { } {
  puts stderr \"\tMUGQIC - $SOFTWARE \"
}
module-whatis \"$SOFTWARE\"

set             root                \$::env($INSTALL_HOME)/software/$SOFTWARE/$SOFTWARE_DIR
prepend-path    PATH                \$root
"

# Call generic module install script once all variables and functions have been set
MODULE_INSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source $MODULE_INSTALL_SCRIPT_DIR/install_module.sh $@
