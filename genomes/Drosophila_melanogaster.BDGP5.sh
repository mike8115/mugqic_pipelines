#!/bin/bash
# Exit immediately on error
set -eu -o pipefail

SPECIES=Drosophila_melanogaster
COMMON_NAME="Fruit fly"
ASSEMBLY=BDGP5
ASSEMBLY_SYNONYMS=dm3
SOURCE=Ensembl
RELEASE=76

GENOME_INSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source $GENOME_INSTALL_SCRIPT_DIR/install_genome.sh

install_genome "$SPECIES" "$COMMON_NAME" "$ASSEMBLY" "$ASSEMBLY_SYNONYMS" "$SOURCE" "$RELEASE"

################################################################################
# Write below all commands to install additional data files specific to this genome assembly
