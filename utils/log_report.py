#!/usr/bin/env python

"""
Plays the role of both "view" (report) and "controller" (main)
"""

import argparse

from create_job_records import JobLog, create_job_logs


# All dates are printed in this format, eg. '2016-01-01T09:02:03'
OUTPUT_DATE_FORMAT = '%Y-%m-%dT%H-%M-%S'

# If a field is undefined, represent it as follows:
UNDEFINED = 'N/A'


###################################################################################################
# SUMMARIZE JOBS
###################################################################################################

def min_max_field(job_logs, field):
    """
    Return name and field of the min and max JobLogs with respect to field
    Return UNDEFINED * 4 if we can't find values
    :param field: JobLog field
    :return: min_name, min_field, max_name, max_field strings
    """
    # Sort the jobs by 'field'
    jobs = sorted(filter(lambda log: hasattr(log, field), job_logs), key=lambda log: getattr(log, field))
    if len(jobs) > 0:
        min_job = jobs[0]
        max_job = jobs[-1]
        return min_job.job_name, str(getattr(min_job, field)), max_job.job_name, str(getattr(max_job, field))
    else:
        return UNDEFINED, UNDEFINED, UNDEFINED, UNDEFINED


def summarize_status(job_logs):
    """
    return the number of jobs that have status:
             SUCCESS, ACTIVE, INACTIVE, FAILED
    If 'status' is not defined on all jobs, return UNDEFINED's instead
    """
    # If every job has a status, return a breakdown of the jobs
    if len(filter(lambda log: hasattr(log, 'status'), job_logs)) > 0:
        return sum(log.status == 'SUCCESS' for log in job_logs), \
               sum(log.status == 'ACTIVE' for log in job_logs), \
               sum(log.status == 'INACTIVE' for log in job_logs), \
               sum(log.status == 'FAILED' for log in job_logs)
    else:
        return UNDEFINED, UNDEFINED, UNDEFINED, UNDEFINED


def get_start_date(job_logs):
    start_dates = [log.start_date for log in job_logs if hasattr(log, 'start_date')]

    if len(start_dates) > 0:
        return min(start_dates)
    return UNDEFINED


def get_end_date(job_logs):
    end_dates = [log.end_date for log in job_logs if hasattr(log, 'end_date')]
    if len(end_dates) > 0:
        return min(end_dates)
    return UNDEFINED


###################################################################################################
# FORMAT LOG
###################################################################################################

def format_field(log, field):
    """
    Lookup the field in log, and format the result for displaying in a table

    :param field: one of the fields of a JobLog
    :return: string representation of log's field
    """
    if hasattr(log, field):
        if field == 'start_date' or field == 'end_date':
            # Always format dates as OUTPUT_DATE_FORMAT
            return str(getattr(log, field).strftime(OUTPUT_DATE_FORMAT))
        else:
            return str(getattr(log, field))
    else:
        # If the field is not defined, display the field as 'N/A'
        return UNDEFINED


def format_log(log):
    """
    :param log: JobLog
    :return: tab-delimited string in order of JobLog.__slots__
    """
    # Eg:
    # 123   456 trimmomatic 789 SUCCESS 0   0   ...
    return '\t'.join(format_field(log, field) for field in JobLog.__slots__)


###################################################################################################
# REPORT
###################################################################################################

def get_log_text_report(job_logs, minimal_detail=False):
    """
    Unassigned fields are given the value 'N/A'
    :return: report string
    """
    report = ''

    if not minimal_detail:
        start_date = get_start_date(job_logs)
        end_date = get_end_date(job_logs)

        min_mem_name, min_mem, max_mem_name, max_mem = min_max_field(job_logs, 'mem')
        min_walltime_name, min_walltime, max_walltime_name, max_walltime = min_max_field(job_logs, 'walltime')

        num_successful, num_active, num_inactive, num_failed = summarize_status(job_logs)

        exec_time = start_date.strftime(OUTPUT_DATE_FORMAT) + ' - ' + end_date.strftime(OUTPUT_DATE_FORMAT) +\
                    ' (' + str(end_date - start_date) + ')'

        report += '''\
# Number of jobs: {num_jobs}
# Number of successful jobs: {successful}
# Number of active jobs: {active}
# Number of inactive jobs: {inactive}
# Number of failed jobs: {failed}

# Execution time: {exec_time}

# Shortest job: {shortest_name} ({shortest_duration})
# Longest job: {longest_name} ({longest_duration})

# Lowest memory job: {min_mem_name} ({min_mem})
# Highest memory job: {max_mem_name} ({max_mem})

'''.format(num_jobs=len(job_logs), successful=num_successful, active=num_active, inactive=num_inactive, failed=num_failed,
           exec_time=exec_time,
           shortest_name=min_walltime_name, shortest_duration=min_walltime,
           longest_name=max_walltime_name, longest_duration=max_walltime,
           min_mem_name=min_mem_name, min_mem=min_mem,
           max_mem_name=max_mem_name, max_mem=max_mem)

    report += '''\
#JOB_ID\tJOB_FULL_ID\tJOB_NAME\tJOB_DEPENDENCIES\tSTATUS\tJOB_EXIT_CODE\tCMD_EXIT_CODE\t\
REAL_TIME\tSTART_DATE\tEND_DATE\tCPU_TIME\tCPU_REAL_TIME_RATIO\tPHYSICAL_MEM\tVIRTUAL_MEM\t\
EXTRA_VIRTUAL_MEM_PCT\tLIMITS\tQUEUE\tUSERNAME\tGROUP\tSESSION\tACCOUNT\tNODES\tPATH
'''

    report += '\n'.join([format_log(log) for log in job_logs])

    return report


###################################################################################################
# MAIN
###################################################################################################

def parse_args():
    '''
    Build the argparse.ArgumentParser and parse arguments
    :return: arguments
    '''
    parser = argparse.ArgumentParser(description='Display information about a set of jobs')
    parser.add_argument('job_file', help='Path to file containing jobs and associated info')
    parser.add_argument('-r', '--report', help='Display a text report summarizing the jobs and their status', action='store_true')

    group = parser.add_mutually_exclusive_group()
    group.add_argument('-s', '--success', help='Show successful jobs only', action='store_true')
    group.add_argument('-nos', '--nosuccess', help='Show unsuccessful jobs only i.e. failed or uncompleted jobs', action='store_true')
    group.add_argument('-m', '--mimimal_detail', help="Only aggregate minimal information about each job", action='store_true')

    parser.add_argument('-t', '--top_to_bottom', help="Display an indented text showing job dependencies from first completed to last completed", action='store_true')
    parser.add_argument('-b', '--bottom_to_top', help="Display an indented text showing job dependencies from last completed to first completed", action='store_true')

    args = parser.parse_args()

    return args.job_file, args.report, args.success, args.nosuccess, args.mimimal_detail


def main():
    job_list_file, report, success_option, no_success_option, minimal_detail = parse_args()

    job_logs = create_job_logs(job_list_file,  success_option, no_success_option, minimal_detail=minimal_detail)

    if report:
        print(get_log_text_report(job_logs, minimal_detail=minimal_detail))

if __name__ == '__main__':
    main()
