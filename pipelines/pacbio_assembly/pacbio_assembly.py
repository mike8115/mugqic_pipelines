#!/usr/bin/env python

# Python Standard Modules
import logging
import os
import sys

# Append mugqic_pipeline directory to Python library path
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(sys.argv[0])))))

# MUGQIC Modules
from core.config import *
from core.job import *
from bio.readset import *

from bio import blast
from bio import pacbio_tools
from bio import smrtanalysis
from pipelines import common

log = logging.getLogger(__name__)

class PacBioAssembly(common.MUGQICPipeline):

    @property
    def readsets(self):
        if not hasattr(self, "_readsets"):
            self._readsets = parse_pacbio_readset_file(self.args.readsets.name)
        return self._readsets

    """
    Filtering. This step uses smrtpipe.py (From the SmrtAnalysis package) and will filter reads and subreads based on their length and QVs.
    1- fofnToSmrtpipeInput.py.
    2- modify RS_Filtering.xml files according to reads filtering values entered in .ini file.
    3- smrtpipe.py with filtering protocol
    4- prinseq-lite.pl to write fasta file based on fastq file.
    Informative run metrics such as loading efficiency, readlengths and base quality are generated in this step as well.
    """
    def smrtanalysis_filtering(self):
        jobs = []

        for sample in self.samples:
            fofn = os.path.join("fofns", sample.name + ".fofn")
            bax_files = [bax_file for readset in sample.readsets for bax_file in readset.bax_files]
            filtering_directory = os.path.join(sample.name, "filtering")

            jobs.append(concat_jobs([
                Job([], [config.param('smrtanalysis_filtering', 'celera_settings'), config.param('smrtanalysis_filtering', 'filtering_settings')], command="cp -a -f " + os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "protocols") + " ."),
                Job(command="mkdir -p fofns"),
                Job(bax_files, [fofn], command="""\
`cat > {fofn} << END
{bax_files}
END
`""".format(bax_files="\n".join(bax_files), fofn=fofn)),
                Job(command="mkdir -p " + filtering_directory),
                smrtanalysis.filtering(
                    fofn,
                    os.path.join(filtering_directory, "input.xml"),
                    os.path.join(sample.name, "filtering.xml"),
                    filtering_directory,
                    os.path.join(filtering_directory, "smrtpipe.log")
                )
            ], name="smrtanalysis_filtering." + sample.name))

        return jobs

    """
    Cutoff value for splitting long reads from short reads is done here using
    estimated coverage and estimated genome size.

    You should estimate the overall coverage and length distribution for putting in
    the correct options in the configuration file. You will need to decide a
    length cutoff for the seeding reads. The optimum cutoff length will depend on
    the distribution of the sequencing read lengths, the genome size and the
    overall yield. Here, you provide a percentage value that corresponds to the
    fraction of coverage you want to use as seeding reads.

    First, loop through fasta sequences. put the length of each sequence in an array,
    sort it, loop through it again and compute the cummulative length coveredby each
    sequence as we loop though the array. Once that length is > (coverage * genome
    size) * $percentageCutoff (e.g. 0.10), we have our threshold. The idea is to
    consider all reads above that threshold to be seeding reads to which will be
    align lower shorter subreads.
    """
    def pacbio_tools_get_cutoff(self):
        jobs = []

        for sample in self.samples:
            log.info("Sample: " + sample.name)
            sample_nb_base_pairs = sum([readset.nb_base_pairs for readset in sample.readsets])
            log.info("nb_base_pairs: " + str(sample_nb_base_pairs))
            estimated_genome_size = sample.readsets[0].estimated_genome_size
            log.info("estimated_genome_size: " + str(estimated_genome_size))
            estimated_coverage = sample_nb_base_pairs / estimated_genome_size
            log.info("estimated_coverage: " + str(estimated_coverage))

            for coverage_cutoff in config.param('DEFAULT', 'coverage_cutoff', type='list'):
                cutoff_x = coverage_cutoff + "X"
                coverage_directory = os.path.join(sample.name, cutoff_x)

                log.info("COVERAGE_CUTOFF: " + coverage_cutoff + "_X_coverage")

                jobs.append(concat_jobs([
                    Job(command="mkdir -p " + os.path.join(coverage_directory, "preassembly")),
                    pacbio_tools.get_cutoff(
                        os.path.join(sample.name, "filtering", "data", "filtered_subreads.fasta"),
                        estimated_coverage,
                        estimated_genome_size,
                        coverage_cutoff,
                        os.path.join(coverage_directory, "preassemblyMinReadSize.txt")
                    )
                ], name="pacbio_tools_get_cutoff." + sample.name + ".coverage_cutoff" + cutoff_x))

        return jobs

    """
    Having in hand a cutoff value, filtered reads are splitted between short and long reads. Short reads
    are aligned against long reads and consensus (e.g. corrected reads) are generated from these alignments.
    1- split reads between long and short.
    2- blasr (Aligner for PacBio reads)
    3- m4topre (Converts .m4 blasr output in .pre format.)
    4- pbdagcon (generates corrected reads from alignments)
    """
    def preassembly(self):
        jobs = []

        for sample in self.samples:
            for coverage_cutoff in config.param('DEFAULT', 'coverage_cutoff', type='list'):
                cutoff_x = coverage_cutoff + "X"
                coverage_directory = os.path.join(sample.name, cutoff_x)
                preassembly_directory = os.path.join(coverage_directory, "preassembly", "data")
                job_name_suffix = sample.name + ".coverage_cutoff" + cutoff_x

                jobs.append(concat_jobs([
                    Job(command="mkdir -p " + preassembly_directory),
                    pacbio_tools.split_reads(
                        os.path.join(sample.name, "filtering", "data", "filtered_subreads.fasta"),
                        os.path.join(coverage_directory, "preassemblyMinReadSize.txt"),
                        os.path.join(preassembly_directory, "filtered_shortreads.fa"),
                        os.path.join(preassembly_directory, "filtered_longreads.fa")
                    )
                ], name="pacbio_tools_split_reads." + job_name_suffix))

                job = smrtanalysis.blasr(
                    os.path.join(sample.name, "filtering", "data", "filtered_subreads.fasta"),
                    os.path.join(preassembly_directory, "filtered_longreads.fa"),
                    os.path.join(preassembly_directory, "seeds.m4"),
                    os.path.join(preassembly_directory, "seeds.m4.fofn")
                )
                job.name = "smrtanalysis_blasr." + job_name_suffix
                jobs.append(job)

                job = smrtanalysis.m4topre(
                    os.path.join(preassembly_directory, "seeds.m4.filtered"),
                    os.path.join(preassembly_directory, "seeds.m4.fofn"),
                    os.path.join(sample.name, "filtering", "data", "filtered_subreads.fasta"),
                    os.path.join(preassembly_directory, "aln.pre")
                )
                job.name = "smrtanalysis_m4topre." + job_name_suffix
                jobs.append(job)

                job = smrtanalysis.pbdagcon(
                    os.path.join(preassembly_directory, "aln.pre"),
                    os.path.join(preassembly_directory, "corrected.fasta"),
                    os.path.join(preassembly_directory, "corrected.fastq")
                )
                job.name = "smrtanalysis_pbdagcon." + job_name_suffix
                jobs.append(job)

        return jobs

    """
    Corrected reads are assembled to generates contigs. Please see Celera documentation.
    http://sourceforge.net/apps/mediawiki/wgs-assembler/index.php?title=RunCA#ovlThreads
    Quality of assembly seems to be highly sensitive to paramters you give Celera.
    1- Generate celera config files using paramters provided in the .ini file.
    2- fastqToCA. Generates input file compatible with the Celera assembler
    3- runCA. Run the Celera assembler.
    """
    def assembly(self):
        jobs = []

        for sample in self.samples:
            for coverage_cutoff in config.param('DEFAULT', 'coverage_cutoff', type='list'):
                cutoff_x = coverage_cutoff + "X"
                coverage_directory = os.path.join(sample.name, cutoff_x)
                preassembly_directory = os.path.join(coverage_directory, "preassembly", "data")

                for mer_size in config.param('DEFAULT', 'mer_sizes', type='list'):
                    mer_size_text = "merSize" + mer_size
                    sample_cutoff_mer_size = "_".join([sample.name, cutoff_x, mer_size_text])
                    mer_size_directory = os.path.join(coverage_directory, mer_size_text)
                    assembly_directory = os.path.join(mer_size_directory, "assembly")

                    jobs.append(concat_jobs([
                        Job(command="mkdir -p " + assembly_directory),
                        pacbio_tools.celera_config(
                            mer_size,
                            config.param('DEFAULT', 'celera_settings'),
                            os.path.join(mer_size_directory, "celera_assembly.ini")
                        )
                    ], name="pacbio_tools_celera_config." + sample_cutoff_mer_size))

                    job = smrtanalysis.fastq_to_ca(
                        sample_cutoff_mer_size,
                        os.path.join(preassembly_directory, "corrected.fastq"),
                        os.path.join(preassembly_directory, "corrected.frg")
                    )
                    job.name = "smrtanalysis_fastq_to_ca." + sample_cutoff_mer_size
                    jobs.append(job)

                    jobs.append(concat_jobs([
                        Job(command="rm -rf " + assembly_directory),
                        smrtanalysis.run_ca(
                            os.path.join(preassembly_directory, "corrected.frg"),
                            os.path.join(mer_size_directory, "celera_assembly.ini"),
                            sample_cutoff_mer_size,
                            assembly_directory
                        )
                    ], name="smrtanalysis_run_ca." + sample_cutoff_mer_size))

                    job = smrtanalysis.pbutgcns(
                        os.path.join(assembly_directory, sample_cutoff_mer_size + ".gkpStore"),
                        os.path.join(assembly_directory, sample_cutoff_mer_size + ".tigStore"),
                        os.path.join(mer_size_directory, "unitigs.lst"),
                        os.path.join(assembly_directory, sample_cutoff_mer_size),
                        os.path.join(assembly_directory, "9-terminator"),
                        os.path.join(assembly_directory, "9-terminator", sample_cutoff_mer_size + ".ctg.fasta"),
                        os.path.join(config.param('smrtanalysis_pbutgcns', 'tmp_dir', type='dirpath'), sample_cutoff_mer_size)
                    )
                    job.name = "smrtanalysis_pbutgcns." + sample_cutoff_mer_size
                    jobs.append(job)

        return jobs

    """
    Align raw reads on the Celera assembly with BLASR. Load pulse information from bax files into aligned file. Sort that file and run quiver (variantCaller.py).
    
    1- Generate fofn
    2- Upload Celera assembly with smrtpipe refUploader
    3- Compare sequences
    4- Load pulses
    5- Sort .cmp.h5 file
    6- variantCaller.py
    """
    def polishing(self):
        jobs = []

        for sample in self.samples:
            for coverage_cutoff in config.param('DEFAULT', 'coverage_cutoff', type='list'):
                cutoff_x = coverage_cutoff + "X"
                coverage_directory = os.path.join(sample.name, cutoff_x)
                preassembly_directory = os.path.join(coverage_directory, "preassembly", "data")

                for mer_size in config.param('DEFAULT', 'mer_sizes', type='list'):
                    mer_size_text = "merSize" + mer_size
                    mer_size_directory = os.path.join(coverage_directory, mer_size_text)
                    assembly_directory = os.path.join(mer_size_directory, "assembly")

                    polishing_rounds = config.param('DEFAULT', 'polishing_rounds', type='posint')
                    if polishing_rounds > 4:
                        raise Exception("Error: polishing_rounds \"" + str(polishing_rounds) + "\" is invalid (should be between 1 and 4)!")

                    for polishing_round in range(1, polishing_rounds + 1):
                        polishing_round_directory = os.path.join(mer_size_directory, "polishing" + str(polishing_round))
                        sample_cutoff_mer_size_polishing_round = "_".join([sample.name, cutoff_x, mer_size_text, "polishingRound" + str(polishing_round)])

                        if polishing_round == 1:
                            fasta_file = os.path.join(assembly_directory, "9-terminator", "_".join([sample.name, cutoff_x, mer_size_text]) + ".ctg.fasta")
                        else:
                            fasta_file = os.path.join(mer_size_directory, "polishing" + str(polishing_round - 1), "data", "consensus.fasta")

                        jobs.append(concat_jobs([
                            Job(command="mkdir -p " + os.path.join(polishing_round_directory, "data")),
                            smrtanalysis.reference_uploader(
                                polishing_round_directory,
                                sample_cutoff_mer_size_polishing_round,
                                fasta_file
                            )
                        ], name="smrtanalysis_reference_uploader." + sample_cutoff_mer_size_polishing_round))

                        job = smrtanalysis.pbalign(
                            os.path.join(polishing_round_directory, "data", "aligned_reads.cmp.h5"),
                            os.path.join(sample.name, "filtering", "data", "filtered_regions.fofn"),
                            os.path.join(sample.name, "filtering", "input.fofn"),
                            os.path.join(polishing_round_directory, sample_cutoff_mer_size_polishing_round, "sequence", sample_cutoff_mer_size_polishing_round + ".fasta"),
                            os.path.join(config.param('smrtanalysis_pbalign', 'tmp_dir', type='dirpath'), sample_cutoff_mer_size_polishing_round)
                        )
                        job.name = "smrtanalysis_pbalign." + sample_cutoff_mer_size_polishing_round
                        jobs.append(job)

                        job = smrtanalysis.load_pulses(
                            os.path.join(polishing_round_directory, "data", "aligned_reads.cmp.h5"),
                            os.path.join(sample.name, "filtering", "input.fofn")
                        )
                        job.name = "smrtanalysis_load_pulses." + sample_cutoff_mer_size_polishing_round
                        jobs.append(job)

                        job = smrtanalysis.cmph5tools_sort(
                            os.path.join(polishing_round_directory, "data", "aligned_reads.cmp.h5"),
                            os.path.join(polishing_round_directory, "data", "aligned_reads.cmp.h5.sorted")
                        )
                        job.name = "smrtanalysis_cmph5tools_sort." + sample_cutoff_mer_size_polishing_round
                        jobs.append(job)

                        job = smrtanalysis.variant_caller(
                            os.path.join(polishing_round_directory, "data", "aligned_reads.cmp.h5.sorted"),
                            os.path.join(polishing_round_directory, sample_cutoff_mer_size_polishing_round, "sequence", sample_cutoff_mer_size_polishing_round + ".fasta"),
                            os.path.join(polishing_round_directory, "data", "variants.gff"),
                            os.path.join(polishing_round_directory, "data", "consensus.fasta.gz"),
                            os.path.join(polishing_round_directory, "data", "consensus.fastq.gz")
                        )
                        job.name = "smrtanalysis_variant_caller." + sample_cutoff_mer_size_polishing_round
                        jobs.append(job)

                        job = smrtanalysis.summarize_polishing(
                            "_".join([sample.name, cutoff_x, mer_size_text]),
                            os.path.join(polishing_round_directory, sample_cutoff_mer_size_polishing_round),
                            os.path.join(polishing_round_directory, "data", "aligned_reads.cmp.h5.sorted"),
                            os.path.join(polishing_round_directory, "data", "alignment_summary.gff"),
                            os.path.join(polishing_round_directory, "data", "coverage.bed"),
                            os.path.join(polishing_round_directory, "data", "aligned_reads.sam"),
                            os.path.join(polishing_round_directory, "data", "variants.gff"),
                            os.path.join(polishing_round_directory, "data", "variants.bed"),
                            os.path.join(polishing_round_directory, "data", "variants.vcf")
                        )
                        job.name = "smrtanalysis_summarize_polishing." + sample_cutoff_mer_size_polishing_round
                        jobs.append(job)

        return jobs

    """
    Blast polished assembly against nr using dc-megablast.
    """
    def blast(self):
        jobs = []

        for sample in self.samples:
            for coverage_cutoff in config.param('DEFAULT', 'coverage_cutoff', type='list'):
                cutoff_x = coverage_cutoff + "X"
                coverage_directory = os.path.join(sample.name, cutoff_x)
                preassembly_directory = os.path.join(coverage_directory, "preassembly", "data")

                for mer_size in config.param('DEFAULT', 'mer_sizes', type='list'):
                    mer_size_text = "merSize" + mer_size
                    mer_size_directory = os.path.join(coverage_directory, mer_size_text)
                    blast_directory = os.path.join(mer_size_directory, "blast")

                    polishing_rounds = config.param('DEFAULT', 'polishing_rounds', type='posint')
                    if polishing_rounds > 4:
                        raise Exception("Error: polishing_rounds \"" + str(polishing_rounds) + "\" is invalid (should be between 1 and 4)!")

                    polishing_round_directory = os.path.join(mer_size_directory, "polishing" + str(polishing_rounds))
                    sample_cutoff_mer_size = "_".join([sample.name, cutoff_x, mer_size_text])
                    blast_report = os.path.join(blast_directory, "blast_report.csv")

                    # Blast contigs against nt
                    jobs.append(concat_jobs([
                        Job(command="mkdir -p " + blast_directory),
                        blast.dcmegablast(
                            os.path.join(polishing_round_directory, "data", "consensus.fasta"),
                            "7",
                            blast_report,
                            os.path.join(polishing_round_directory, "data", "coverage.bed"),
                            blast_directory
                        )
                    ], name="blast_dcmegablast." + sample_cutoff_mer_size))

                    job = blast.blastdbcmd(
                        blast_report,
                        "$(grep -v '^#' < " + blast_report + " | head -n 1 | awk -F '\\t' '{print $2}' | sed 's/gi|\([0-9]*\)|.*/\\1/' | tr '\\n' '  ')",
                        os.path.join(blast_directory, "nt_reference.fasta"),
                    )
                    job.name = "blast_blastdbcmd." + sample_cutoff_mer_size
                    jobs.append(job)

        return jobs

    """
    Using MUMmer, align polished assembly against best hit from blast job. Also align polished assembly against itself to detect structure variation such as repeats, etc.
    """
    def mummer(self):
        jobs = []

        return jobs

    @property
    def steps(self):
        return [
            self.smrtanalysis_filtering,
            self.pacbio_tools_get_cutoff,
            self.preassembly,
            self.assembly,
            self.polishing,
            self.blast,
            self.mummer
        ]

if __name__ == '__main__':
    PacBioAssembly().submit_jobs()
