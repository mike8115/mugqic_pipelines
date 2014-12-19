#!/usr/bin/env python

# Python Standard Modules
import logging
import os

# MUGQIC Modules
from core.config import *
from core.job import *

log = logging.getLogger(__name__)

def trimmomatic(
    input1,
    input2,
    paired_output1,
    unpaired_output1,
    paired_output2,
    unpaired_output2,
    single_output,
    quality_offset,
    trim_log
    ):

    if input2:  # Paired end reads
        inputs = [input1, input2]
        outputs = [paired_output1, unpaired_output1, paired_output2, unpaired_output2]
    else:   # Single end reads
        inputs = [input1]
        outputs = [single_output]

    headcrop_length = config.param('trimmomatic', 'headcrop_length', required=False, type='posint')

    return Job(
        inputs,
        outputs + [trim_log],
        [
            ['trimmomatic', 'module_java'],
            ['trimmomatic', 'module_trimmomatic']
        ],

        # CAUTION: Trimmomatic settings order is IMPORTANT!
        # FIRST Illuminaclip settings, THEN headcrop length, THEN trailing min quality, THEN minimum length
        command="""\
java -XX:ParallelGCThreads=1 -Xmx{ram} -jar $TRIMMOMATIC_JAR {mode} \\
  -threads {threads} \\
  -phred{quality_offset} \\
  {inputs} \\
  {outputs} \\
  ILLUMINACLIP:{adapter_file}{illumina_clip_settings}{headcrop_length} \\
  TRAILING:{trailing_min_quality} \\
  MINLEN:{min_length}{tophred33} \\
  2> {trim_log}""".format(
        ram=config.param('trimmomatic', 'ram'),
        mode = "PE" if input2 else "SE",
        threads=config.param('trimmomatic', 'threads', type='posint'),
        quality_offset=quality_offset if quality_offset == 64 else "33",
        inputs=" \\\n  ".join(inputs),
        outputs=" \\\n  ".join(outputs),
        adapter_file=config.param('trimmomatic', 'adapter_fasta', type='filepath'),
        illumina_clip_settings=config.param('trimmomatic', 'illumina_clip_settings'),
        headcrop_length=" \\\n  HEADCROP:" + str(headcrop_length) if headcrop_length else "",
        trailing_min_quality=config.param('trimmomatic', 'trailing_min_quality', type='int'),
        min_length=config.param('trimmomatic', 'min_length', type='posint'),
        tophred33=" \\\n  TOPHRED33" if quality_offset == 64 else "",
        trim_log=trim_log
        ),
        removable_files=[paired_output1, unpaired_output1, paired_output2, unpaired_output2, single_output],
    )
