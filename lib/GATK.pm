#!/usr/env/perl

=head1 NAME

I<GATK>

=head1 SYNOPSIS

GATK->trim()

=head1 DESCRIPTION

B<GATK> is a library to manipulate and compute stats off of BAMs

Input = file_name

Output = array

=head1 AUTHOR

=head1 DEPENDENCY

B<Pod::Usage> Usage and help output.

B<Data::Dumper> Used to debbug

=cut

package GATK;

# Strict Pragmas
#--------------------------
use strict;
use warnings;

#--------------------------

# Dependencies
#-----------------------

# SUB
#-----------------------
sub recalibration {
  my $rH_cfg          = shift;
  my $sampleName      = shift;
  my $sortedBAM       = shift;
  my $outputPrefix    = shift;

  my $refGenome = LoadConfig::getParam($rH_cfg, 'default', 'referenceFasta');
  my $knownSites = LoadConfig::getParam($rH_cfg, 'recalibration', 'knownSites');
  my $recalOutput = $outputPrefix.'.recalibration_report.grp';
  my $bamOutput = $outputPrefix.'.recal.bam';

  my $ro_job = new Job();
  $ro_job->testInputOutputs([$sortedBAM], [$bamOutput]);

  if (!$ro_job->isUp2Date()) {
      my $command;
      $command .= 'module load '.LoadConfig::getParam($rH_cfg, 'recalibration', 'moduleVersion.java').' '.LoadConfig::getParam($rH_cfg, 'recalibration', 'moduleVersion.gatk').' ;';
      $command .= ' java -Djava.io.tmpdir='.LoadConfig::getParam($rH_cfg, 'recalibration', 'tmpDir').' '.LoadConfig::getParam($rH_cfg, 'recalibration', 'extraJavaFlags').' -Xmx'.LoadConfig::getParam($rH_cfg, 'recalibration', 'recalRam').'  -jar \${GATK_JAR}';
      $command .= ' -T BaseRecalibrator';
      $command .= ' -nct '.LoadConfig::getParam($rH_cfg, 'recalibration', 'threads');
      $command .= ' -R '.$refGenome;
      $command .= ' -knownSites '.$knownSites;
      $command .= ' -o '.$recalOutput;
      $command .= ' -I '.$sortedBAM;
      $command .= ' ; ';
      $command .= ' java -Djava.io.tmpdir='.LoadConfig::getParam($rH_cfg, 'recalibration', 'tmpDir').' '.LoadConfig::getParam($rH_cfg, 'recalibration', 'extraJavaFlags').' -Xmx'.LoadConfig::getParam($rH_cfg, 'recalibration', 'recalRam').' -jar \${GATK_JAR}';
      $command .= ' -T PrintReads';
      $command .= ' -nct '.LoadConfig::getParam($rH_cfg, 'recalibration', 'threads');
      $command .= ' -R '.$refGenome;
      $command .= ' -BQSR '.$recalOutput;
      $command .= ' -o '.$bamOutput;
      $command .= ' -I '.$sortedBAM;

      $ro_job->addCommand($command);
  }

  return $ro_job;
}

sub realign {
  my $rH_cfg          = shift;
  my $sampleName      = shift;
  my $sortedBAM       = shift;
  my $seqName         = shift;
  my $outputPrefix    = shift;
  my $processUnmapped = shift;
  my $rA_exclusions   = shift;

  my $refGenome = LoadConfig::getParam($rH_cfg, 'default', 'referenceFasta');
  my $intervalOutput = $outputPrefix.'.intervals';
  my $realignOutput = $outputPrefix.'.bam';

  my $ro_job = new Job();
  $ro_job->testInputOutputs([$sortedBAM], [$intervalOutput,$realignOutput]);

  if (!$ro_job->isUp2Date()) {  
      my $command;
      $command .= 'module load '.LoadConfig::getParam($rH_cfg, 'indelRealigner', 'moduleVersion.java').' '.LoadConfig::getParam($rH_cfg, 'indelRealigner', 'moduleVersion.gatk').' ;';
      $command .= ' java -Djava.io.tmpdir='.LoadConfig::getParam($rH_cfg, 'indelRealigner', 'tmpDir').' '.LoadConfig::getParam($rH_cfg, 'indelRealigner', 'extraJavaFlags').' -Xmx'.LoadConfig::getParam($rH_cfg, 'indelRealigner', 'realignRam').'  -jar \${GATK_JAR}';
      $command .= ' -T RealignerTargetCreator';
      $command .= ' -R '.$refGenome;
      $command .= ' -o '.$intervalOutput;
      $command .= ' -I '.$sortedBAM;
      if(defined($seqName)) {
        $command .= ' -L '.$seqName;
      }
      if(defined($rA_exclusions)) {
        $command .= ' --excludeIntervals '.join(' --excludeIntervals ', @{$rA_exclusions}).' --excludeIntervals unmapped';
      }
      $command .= ' ; ';
      $command .= ' java -Djava.io.tmpdir='.LoadConfig::getParam($rH_cfg, 'indelRealigner', 'tmpDir').' '.LoadConfig::getParam($rH_cfg, 'indelRealigner', 'extraJavaFlags').' -Xmx'.LoadConfig::getParam($rH_cfg, 'indelRealigner', 'realignRam').' -jar \${GATK_JAR}';
      $command .= ' -T IndelRealigner';
      $command .= ' -R '.$refGenome;
      $command .= ' -targetIntervals '.$intervalOutput;
      $command .= ' -o '.$realignOutput;
      $command .= ' -I '.$sortedBAM;
      if(defined($seqName)) {
        $command .= ' -L '.$seqName;
      }
      if(defined($rA_exclusions)) {
        $command .= ' --excludeIntervals '.join(' --excludeIntervals ', @{$rA_exclusions}).' --excludeIntervals unmapped';
      }
      elsif($processUnmapped == 1) {
        $command .= ' -L unmapped';
      }
      $command .= ' --maxReadsInMemory '.LoadConfig::getParam($rH_cfg, 'indelRealigner', 'realignReadsInRam');

      $ro_job->addCommand($command);
  }
  
  return $ro_job;
}

sub genomeCoverage {
  my $rH_cfg        = shift;
  my $sampleName    = shift;
  my $inputBam      = shift;
  my $outputPrefix  = shift;

  my $refGenome = LoadConfig::getParam($rH_cfg, 'default', 'referenceFasta');
  my $rA_thresholds = LoadConfig::getParam($rH_cfg, 'genomeCoverage', 'percentThresholds');

  my $ro_job = new Job();
  $ro_job->testInputOutputs([$inputBam], [$outputPrefix.'.coverage.sample_summary']);

  if (!$ro_job->isUp2Date()) {  
      my $command;
      $command .= 'module load '.LoadConfig::getParam($rH_cfg, 'genomeCoverage', 'moduleVersion.java').' '.LoadConfig::getParam($rH_cfg, 'genomeCoverage', 'moduleVersion.gatk').' ;';
      $command .= ' java -Djava.io.tmpdir='.LoadConfig::getParam($rH_cfg, 'genomeCoverage', 'tmpDir').' '.LoadConfig::getParam($rH_cfg, 'genomeCoverage', 'extraJavaFlags').' -Xmx'.LoadConfig::getParam($rH_cfg, 'genomeCoverage', 'genomeCoverageRam').'  -jar \${GATK_JAR}';
      $command .= ' -T DepthOfCoverage --omitDepthOutputAtEachBase --logging_level ERROR';
      my $highestThreshold = 0;
      for my $threshold (@$rA_thresholds) {
        $command .= ' --summaryCoverageThreshold '.$threshold;
        if($highestThreshold > $threshold) {
          die "Tresholds must be ascending: ".join(',', @$rA_thresholds);
        }
        $highestThreshold = $threshold;
      }
      $command .= ' --start 1 --stop '.$highestThreshold.' --nBins '.($highestThreshold-1).' -dt NONE';
      $command .= ' -R '.$refGenome;
      $command .= ' -o '.$outputPrefix;
      $command .= ' -I '.$inputBam;

      $ro_job->addCommand($command);
  }
  
  return $ro_job;
}

sub targetCoverage {
  my $rH_cfg        = shift;
  my $sampleName    = shift;
  my $inputBam      = shift;
  my $outputPrefix  = shift;

  my $refGenome = LoadConfig::getParam($rH_cfg, 'default', 'referenceFasta');
  my $targets = LoadConfig::getParam($rH_cfg, 'targetCoverage', 'coverageTargets');
  my $rA_thresholds = LoadConfig::getParam($rH_cfg, 'targetCoverage', 'percentThresholds');

  my $ro_job = new Job();
  $ro_job->testInputOutputs([$inputBam], [$outputPrefix.'.coverage.sample_summary']);

  if (!$ro_job->isUp2Date()) {
      my $command = "";
      $command .= 'module load '.LoadConfig::getParam($rH_cfg, 'targetCoverage', 'moduleVersion.java').' '.LoadConfig::getParam($rH_cfg, 'targetCoverage', 'moduleVersion.gatk').' ;';
      $command .= ' java -Djava.io.tmpdir='.LoadConfig::getParam($rH_cfg, 'targetCoverage', 'tmpDir').' '.LoadConfig::getParam($rH_cfg, 'targetCoverage', 'extraJavaFlags').' -Xmx'.LoadConfig::getParam($rH_cfg, 'targetCoverage', 'coverageRam').'  -jar \${GATK_JAR}';
      $command .= ' -T DepthOfCoverage --omitDepthOutputAtEachBase --logging_level ERROR';
      my $highestThreshold = 0;
      for my $threshold (@$rA_thresholds) {
        $command .= ' --summaryCoverageThreshold '.$threshold;
        if($highestThreshold > $threshold) {
          die "Tresholds must be ascending: ".join(',', @$rA_thresholds);
        }
        $highestThreshold = $threshold;
      }
      $command .= ' --start 1 --stop '.$highestThreshold.' --nBins '.($highestThreshold-1).' -dt NONE';
      $command .= ' -R '.$refGenome;
      $command .= ' -o '.$outputPrefix;
      $command .= ' -I '.$inputBam;
      $command .= ' -L '.$targets;

      $ro_job->addCommand($command);
  }
  
  return $ro_job;
}

1;
