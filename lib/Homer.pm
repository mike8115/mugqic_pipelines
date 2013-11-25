#!/usr/env/perl

=head1 NAME

I<HOMER>

=head1 SYNOPSIS

HOMER->parseGenome()
HOMER->makeTagDirectory()
HOMER->findMotifs()
HOMER->annotatePeaks()
HOMER->makeUCSCFile ()

=head1 DESCRIPTION

B<HOMER> is a software for motif discovery and next-gen sequecing analysis

Input = file_name

Output = array

=head1 AUTHOR

B<Johanna Sandoval> - I<johanna.sandoval@mail.mcgill.ca>

=head1 DEPENDENCY

B<Pod::Usage> Usage and help output.

B<Data::Dumper> Used to debbug

=cut

package HOMER;

# Strict Pragmas
#--------------------------
use strict;
use warnings;

# Dependencies
#-----------------------
use LoadConfig;

# SUB
#-----------------------

sub parseGenome {
  my $rH_cfg = shift;
  my $genomeName;
  # Retrieve genome name from ini file
  my $refGenome = LoadConfig::getParam($rH_cfg, 'default', 'genomeName');
  
  # Check if genome exists in homer config file. 
  my $config = HomerConfig::loadConfigFile();
  
  if (!exists({$config->{GENOMES}}->{$refGenome})) {
    print STDERR "\n#WARNING: Genome $refGenome not found in Homer config.txt file \n#QC, annotations and Motif analysis will not be executed\n\n";
    $genomeName = 'none';
  } else {
    $genomeName = $refGenome;
  }
  return $genomeName;
}

sub makeTagDirectory {
  my $rH_cfg          = shift;
  my $sampleName      = shift;
  my $sortedBAM       = shift;
  my $outputDir       = shift;
  my $processUnmapped = shift;

  my $refGenome = LoadConfig::getParam($rH_cfg, 'default', 'genomeName');
  #my $refGenome = parseGenome($rH_cfg);
  my $ro_job = new Job();

  if (defined $refGenome) {
    $ro_job->testInputOutputs([$sortedBAM], undef);

    my $command;
    $command = ' module load ' . LoadConfig::getParam($rH_cfg, 'qcTags', 'moduleVersion.python') . ' ' . LoadConfig::getParam($rH_cfg, 'qcTags', 'moduleVersion.homer') . ' ' . LoadConfig::getParam($rH_cfg, 'qcTags', 'moduleVersion.samtools') . ' &&';
    $command .= ' makeTagDirectory ' . $outputDir . '/' . $sampleName . ' ' . $sortedBAM . ' -checkGC -genome ' . $refGenome;

    $ro_job->addCommand($command);

  } else {
    $ro_job->setUp2Date(1);
    print STDERR "\n#WARNING: Genome $refGenome not defined \n#QC, annotations and Motif analysis will not be executed\n\n";
  }
  return $ro_job;
}

sub makeUCSCFile {
  my $rH_cfg       = shift;
  my $sampleName   = shift;
  my $tagDirectory = shift;
  my $outputWiggle = shift;

  my $command = undef;
  
  my $ro_job = new Job();
  $ro_job->testInputOutputs([$tagDirectory], [$outputWiggle]);

  if (!$ro_job->isUp2Date()) {
    $command .= ' module load ' . LoadConfig::getParam($rH_cfg, 'default' , 'moduleVersion.python') . ' ' . LoadConfig::getParam($rH_cfg, 'default', 'moduleVersion.homer') . ' &&';
    $command .= ' makeUCSCfile ' . $tagDirectory . ' -o ' . $outputWiggle;
    $ro_job->addCommand($command);
  }
  
  return $ro_job;
}

sub annotatePeaks {
  my $rH_cfg     = shift;
  my $designName = shift;
  my $InputBed   = shift;
  my $outputDir  = shift;
  my $command;
  my $genomeName = LoadConfig::getParam($rH_cfg, 'annotation', 'genomeName');

  my $ro_job = new Job();
  $ro_job->testInputOutputs([$InputBed], [$outputDir.'/'.$designName]);

  if (!$ro_job->isUp2Date()) {
    $command .= ' module load ' . LoadConfig::getParam($rH_cfg, 'default' , 'moduleVersion.python') . ' ' . LoadConfig::getParam($rH_cfg, 'default', 'moduleVersion.homer') . ' &&';
    $command .= ' annotatePeaks.pl ' . $InputBed . ' ' . $genomeName . ' -gsize ' . $genomeName . ' -cons -CpG -go ' . $outputDir . '/' . $designName . ' -genomeOntology ' . $outputDir . '/' . $designName . ' > ' . $outputDir . '/' . $designName . '.annotated.csv';
    $ro_job->addCommand($command);
  }
  return $ro_job;
  
}

sub generateMotif {
  my $rH_cfg     = shift;
  my $designName = shift;
  my $InputBed   = shift;
  my $outputDir  = shift;
  my $genomeName = LoadConfig::getParam($rH_cfg, 'motif', 'genomeName');

  my $optionsThreads;
  if (defined(LoadConfig::getParam($rH_cfg, 'motif', 'homermotifThreads')) &&  LoadConfig::getParam($rH_cfg, 'motif', 'homermotifThreads') ne "") {
    $optionsThreads = '-p ' . LoadConfig::getParam($rH_cfg, 'motif', 'homermotifThreads') . ' ';
  } else {
    $optionsThreads = ' ';
  }
  my $ro_job = new Job();
  $ro_job->testInputOutputs([$InputBed], undef);

  if (!$ro_job->isUp2Date()) {
    my $command;
    $command .= ' module load ' . LoadConfig::getParam($rH_cfg, 'default' , 'moduleVersion.python') . ' ' . LoadConfig::getParam($rH_cfg, 'default', 'moduleVersion.homer') . ' ' . LoadConfig::getParam($rH_cfg, 'default', 'moduleVersion.weblogo') . ' &&';
    $command .= ' findMotifsGenome.pl ' . $InputBed . ' ' . $genomeName . ' ' . $outputDir . ' ' . $optionsThreads;

    $ro_job->addCommand($command);
  }

  return $ro_job;
}

sub qcPlotsR {
  my $rH_cfg         = shift;
  my $designFile     = shift;
  my $outputDir      = shift;

  my $graphDirectory = $outputDir .'/graphs/';
  my $ro_job = new Job();
  $ro_job->testInputOutputs([$designFile], undef);

  if (!$ro_job->isUp2Date()) {
    my $command;
    $command .= ' module add ' . LoadConfig::getParam($rH_cfg, 'default', 'moduleVersion.tools') . ' ' . LoadConfig::getParam($rH_cfg, 'default', 'moduleVersion.R') . ' &&';
    $command .= ' Rscript ' . ' \$R_TOOLS/chipSeqGenerateQCMetrics.R ' . $designFile . ' ' . $outputDir;

    $ro_job->addCommand($command);
  }
  return $ro_job;
}
1;
