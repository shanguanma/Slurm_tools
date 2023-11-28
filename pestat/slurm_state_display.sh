#!/usr/bin/env bash

# Prints a Slurm cluster status with 1 line per node/partition and job info
# Author: Ole.H.Nielsen@fysik.dtu.dk
# Homepage: https://github.com/OleHolmNielsen/Slurm_tools/
my_version="pestat Github version"

#####################################################################################
#
# Environment configuration lines
#

# CONFIGURE the paths of commands:
# Directory where Slurm commands live:
#export prefix=/usr/bin
export prefix=/cm/shared/apps/slurm/21.08.8/bin/
# The awk command
my_awk=/usr/bin/awk
# Job grace time (seconds) before we may flag the node
export jobgracetime=300
# Global configuration file for pestat
export PESTAT_GLOBAL_CONFIG=/etc/pestat.conf
# Per-user configuration file for pestat
export PESTAT_CONFIG=$HOME/.pestat.conf
# Omit nodes with these states (list separated by spaces):
export statedown="down down~ idle~ alloc# drain drng resv maint boot"
# End of CONFIGURE lines

#####################################################################################
#
# Command usage:
#
function usage()
{
	cat <<EOF
Usage:slurm_state_display.sh  [-p partition(s)] [-P] [-u username] [-g groupname] [-A accountname] [-a]
	[-q qoslist] [-s/-t statelist] [-n/-w hostlist] [-j joblist] [-G] [-N]
	[-f | -F | -m free_mem | -M free_mem ] [-1|-2] [-d] [-S] [-E] [-T] [-C|-c] [-V] [-h]
 
example:  ./slurm_state_display.sh -G 
where:
	-p partition: Select only partion <partition>
        -P: Include all partitions, including hidden and unavailable ones
	-u username: Print only jobs of a single user <username> 
	-g groupname: Print only users in UNIX group <groupname>
	-A accountname: Print only jobs in Slurm account <accountname>
	-a: Print User(Account) information after each JobID
	-q qoslist: Print only QOS in the qoslist <qoslist>
	-R reservationlist: Print only node reservations <reservationlist>
	-s|-t statelist: Print only nodes with state in <statelist> 
	-n|-w hostlist: Print only nodes in hostlist
	-j joblist: Print only nodes in job <joblist>
	-G: Print GRES (Generic Resources) in addition to JobID
	-N: Print JobName in addition to JobID
	-f: Print only nodes that are flagged by * (unexpected load etc.)
	-F: Like -f, but only nodes flagged in RED are printed.
	-m free_mem: Print only nodes with free memory LESS than free_mem MB
	-M free_mem: Print only nodes with free memory GREATER than free_mem MB (under-utilized)
	-d: Omit nodes with states: $statedown
	-1: Default: Only 1 line per node (unique nodes in multiple partitions are printed once only)
	-2: 2..N lines per node which participates in multiple partitions 
	-S: Job StartTime is printed after each JobID/user
	-E: Job EndTime is printed after each JobID/user
	-T: Job TimeUsed is printed after each JobID/user
	-C: Color output is forced ON
	-c: Color output is forced OFF
	-h: Print this help information
	-V: Version information

Global configuration file for pestat: $PESTAT_GLOBAL_CONFIG
Per-user configuration file for pestat: $PESTAT_CONFIG
EOF
}

#####################################################################################
#
# Configuration of default pestat parameters.
# Default values are overridden by $PESTAT_GLOBAL_CONFIG and $PESTAT_CONFIG
#

# Flagging nodes
export flaglevel=-1
# Free memory threshold value (off by default)
export free_mem_less=-1
export free_mem_more=-1

# Thresholds for flagging nodes
export cpuload_delta1=2.0	# CPU load delta from ideal load (RED)
export cpuload_delta2=0.5	# CPU load delta from ideal load (MAGENTA)
export memory_thres1=0.1	# Fraction of memory which is free (RED)
export memory_thres2=0.2	# Fraction of memory which is free (MAGENTA)

# Colored output by default:
export colors=1

# Print all nodes by default
export printallnodes=1
# Unique nodes only (nodes in multiple partitions are printed once only)
# export uniquenodes=0
# We have changed uniquenodes=1 to be the default now
export uniquenodes=1

# Omit nodes with states: $statedown
export omitdown=0

# Controls whether GRES (Generic Resources) will be printed
export printgres=0
# Controls whether User(Account) will be printed after each JobID
export printaccount=0
# Controls whether JobName will be printed
export printjobname=0
# Controls whether job StartTime and EndTime will be printed
export printjobstarttime=0
export printjobendtime=0

# Select UNIX group
export groupname=""

export partition=""
# By default sinfo does not show hidden and unavailable partitions
export all_partitions=""
export hostlist=""

# Remove any custom format for squeue and Slurm time format (may mess up output formatting)
export SQUEUE_FORMAT=""
export SLURM_TIME_FORMAT=""

# Check if output is NOT a terminal: Turn colors off (can be overruled by "-C" flag).
FD=1	# File Descriptor no. 1 = stdout
if test ! -t $FD
then
	export colors=0
fi

# First read the global configuration file for pestat
if test -s $PESTAT_GLOBAL_CONFIG
then
	source $PESTAT_GLOBAL_CONFIG
fi

# Next read the per-user configuration file for pestat
if test -s $PESTAT_CONFIG
then
	source $PESTAT_CONFIG
fi

#####################################################################################
#
# Parse command options
#

while getopts "p:Pu:g:A:q:s:t:n:j:w:m:M:R:aCcdhVFf12SETNG" options; do
	case $options in
		p )	export partition="-p $OPTARG"
			echo Print only nodes in partition $OPTARG
			;;
		P )	export all_partitions="--all"
			;;
		u )	export username=$OPTARG
			# Only a single username is supported, so detect any non-alphanumeric characters
			if [[ "$username" =~ [^a-zA-Z0-9] ]]
			then
				echo "ERROR: Multiple usernames given: $username"
				exit -1
			fi
			if test "`$prefix/sacctmgr -p -n show assoc where users=$username`"
			then
				echo "Select a single Slurm user: $username"
			else
				# An incorrectly configured Slurm database may not contain user associations
				echo "Warning: No Slurm association found in the database for username $username"
			fi
			;;
		g )	export groupname="$OPTARG"
			if test "`getent group $OPTARG`"
			then
				echo Print only users in UNIX group $OPTARG
			else
				echo Error selecting UNIX group $OPTARG
				exit -1
			fi
			;;
		A )	export accountlist=$OPTARG
			if test "`$prefix/sacctmgr -n -p show account $accountlist`"
			then
				echo Select only Slurm account=$accountlist
			else
				echo Error selecting Slurm account $accountlist
				echo Print all available accounts by: sacctmgr show account
				exit -1
			fi
			;;
		a )	export printaccount=1
			echo "Print User(Account) after each JobID"
			;;
		q )	export qoslist=$OPTARG
			if test "`$prefix/sacctmgr -n -p show qos $qoslist`"
			then
				echo Select only QOS=$qoslist
			else
				echo Error selecting QOS $qoslist
				echo Print all available QOSes by: sacctmgr show qos
				exit -1
			fi
			;;
		s|t )	statelist="--states $OPTARG"
			echo Select only nodes with state=$OPTARG
			;;
		R )	export reservationlist="$OPTARG"
			echo Select only nodes with reservation=$OPTARG
			;;
		n|w )	hostlist="-n $OPTARG"
			echo Select only nodes in hostlist=$OPTARG
			;;
		d )	export omitdown=1
			echo Omit nodes with states: $statedown
			;;
		j )	joblist=$OPTARG
			# Check if joblist is running in the Slurm queue and squeue displays job information
			jobfound=`$prefix/squeue -j $joblist -t running -h -O JobID 2>/dev/null`
			if test $? -ne 0 -o -z "$jobfound"
			then
				echo ERROR: Jobs in the list $joblist are not running in the current Slurm queue
				exit 1
			fi
			echo Select only nodes with jobs in joblist=$joblist
			# The "readarray" built-in command was introduced in Bash ver.4
			# See https://www.baeldung.com/linux/join-multiple-lines
			hostlist="-n `$prefix/squeue -j $joblist -t running -h -O NodeList: | (readarray -t ARRAY; IFS=','; echo "${ARRAY[*]}")`"
			;;
		G )	export printgres=1
			echo "GPU GRES (Generic Resource) is printed after each JobID"
			;;
		N )	export printjobname=1
			echo "JobName is printed after each JobID"
			;;
		f|F )	export flaglevel=1
			flag_color="(RED and MAGENTA nodes)"
			if test $options = "F"
			then
				export flaglevel=2	# Flag RED nodes only
				flag_color="(RED nodes)"
			fi
			if test $free_mem_less -ge 0 -o $free_mem_more -ge 0
			then
				echo ERROR: The -f -m -M flags are mutually exclusive
				exit -1
			fi
			export printallnodes=0
			echo Print only nodes that are flagged by \* $flag_color
			;;
		m )	export free_mem_less=$OPTARG
			if test $flaglevel -gt 0 -o $free_mem_more -ge 0
			then
				echo ERROR: The -f -m -M flags are mutually exclusive
				exit -1
			fi
			export printallnodes=0
			echo Select only nodes with free memory LESS than $free_mem_less MB
			;;
		M )	export free_mem_more=$OPTARG
			if test $flaglevel -gt 0 -o $free_mem_less -ge 0
			then
				echo ERROR: The -f -m -M flags are mutually exclusive
				exit -1
			fi
			export printallnodes=0
			echo Select only nodes with free memory GREATER than $free_mem_more MB
			;;
		1 )	export uniquenodes=1
			echo "Only 1 line per node (Unique nodes in multiple partitions are printed once only)"
			;;
		2 )	export uniquenodes=0
			echo "2..N lines per node which participates in multiple partitions"
			;;
		S )	export printjobstarttime=1
			echo "Job StartTime is printed after each JobID/user"
			;;
		E )	export printjobendtime=1
			echo "Job EndTime is printed after each JobID/user"
			;;
		T )	export printtimeused=1
			echo "Job TimeUsed is printed after each JobID/user"
			;;
		C )	export colors=1
			echo Force colors ON in output
			;;
		c )	export colors=0
			echo Force colors OFF in output
			;;
		V ) echo $my_version
			exit 1;;
		h|? ) usage
			exit 1;;
		* ) usage
			exit 1;;
	esac
done

# Test for extraneous command line arguments
if test $# -gt $(($OPTIND-1))
then
	echo ERROR: Too many command line arguments: $*
	usage
	exit 1
fi

# Sanity check of arguments to sinfo
sinfo $all_partitions $partition $hostlist $statelist > /dev/null
# Trap any errors from sinfo
if [[ "$?" -ne 0 ]]
then
	echo "ERROR: sinfo returned with an error message"
	exit -1
fi

# Determine the longest hostname length in the cluster
# The sinfo header NODELIST will set the minimum to 8 chars
# Variable width of the hostname (NODELIST) column 
export hostnamelength=`sinfo -N $all_partitions $partition $hostlist $statelist -O NodeList:30 | tr -d '[:blank:]' | wc --max-line-length`
# Sanity checks of hostnamelength
if [[ $hostnamelength -lt 8 ]]	
then
	export hostnamelength=8
elif [[ $hostnamelength -gt 20 ]]	
then
	export hostnamelength=20
	echo "Notice: Longest hostname length is truncated to $hostnamelength"
fi

# Determine the longest node GRES (gres/gpu) string length
export nodegreswidth=`sinfo -h -N $all_partitions $partition $hostlist $statelist -O Gres:30 | sort | uniq | tr -d '[:blank:]' | wc --max-line-length`
# echo nodegreswidth is $nodegreswidth

#####################################################################################
#
# Main pestat function: Execute Slurm commands and print output.
#

# Was: $prefix/sinfo -h -N $partition $hostlist $statelist -o "%N %P %C %O %m %e %t %Z %G" | $my_awk '
# $prefix/sinfo -h -N $partition $hostlist $statelist -O "NodeList: ,Partition: ,CPUsState: ,CPUsLoad: ,Memory: ,FreeMem: ,StateCompact: ,Threads: ,Gres: " | $my_awk '
# Column size(width)=30 hopefully suffices to separate columns
$prefix/sinfo -h -N $all_partitions $partition $hostlist $statelist -O "NodeList:30,Partition:30,CPUsState:30,CPUsLoad:30,Memory:30,FreeMem:30,StateCompact:30,Threads:30,Gres:30" | $my_awk '
BEGIN {
	#####################################################################################
	# Initialization

	# Read the environment variables configuring actions of pestat:
	prefix=ENVIRON["prefix"]
	username=ENVIRON["username"]
	groupname=ENVIRON["groupname"]
	qoslist=ENVIRON["qoslist"]
	accountlist=ENVIRON["accountlist"]
	printaccount=ENVIRON["printaccount"]
	reservationlist=ENVIRON["reservationlist"]
	free_mem_less=ENVIRON["free_mem_less"]
	free_mem_more=ENVIRON["free_mem_more"]
	cpuload_delta1=ENVIRON["cpuload_delta1"]
	cpuload_delta2=ENVIRON["cpuload_delta2"]
	memory_thres1=ENVIRON["memory_thres1"]
	memory_thres2=ENVIRON["memory_thres2"]
	printallnodes=ENVIRON["printallnodes"]
	omitdown=ENVIRON["omitdown"]
	statedown=ENVIRON["statedown"]
	printgres=ENVIRON["printgres"]
	nodegreswidth=ENVIRON["nodegreswidth"]
	jobgreswidth=0
	printjobname=ENVIRON["printjobname"]
	printjobstarttime=ENVIRON["printjobstarttime"]
	printjobendtime=ENVIRON["printjobendtime"]
	printtimeused=ENVIRON["printtimeused"]
	uniquenodes=ENVIRON["uniquenodes"]
	flaglevel=ENVIRON["flaglevel"]
	hostnamelength=ENVIRON["hostnamelength"]
	jobgracetime=ENVIRON["jobgracetime"]
	colors=ENVIRON["colors"]
	# Define terminal colors for the output if requested
	if (colors != 0) {
		# See http://en.wikipedia.org/wiki/ANSI_escape_code#Colors
		RED="\033[1;31m"
		GREEN="\033[1;32m"
		MAGENTA="\033[1;35m"
		NORMAL="\033[0m"
	}
	# Omit nodes with states: statedown
	if (omitdown > 0) {
		split(statedown,statedownlist," ")
	}

	if (accountlist != "") selection = selection " -A " accountlist
	if (qoslist != "") selection = selection " -q " qoslist
	if (reservationlist != "") selection = selection " -R " reservationlist
	# The "scontrol show hostnames" command is used to expand NodeList expressions
	HOSTLIST=prefix "/scontrol show hostnames "

	#####################################################################################
	# Gather the list of running jobs with squeue
	# Place JobName last, just in case it is a null string
	# Place NodeList second before last because it may be very long
	# JOBLIST = prefix "/squeue -t RUNNING -h -O State,JobID,UserName,GroupName,Account,StartTime,EndTime,TimeUsed,Partition,NumNodes,tres-alloc,NodeList,Name " selection
	# Column size(width)=30 hopefully suffices to separate columns
	# The -O output fields must be space-separated, so use :(space) "sufix" and enclose -O fields in '' (octal 047)
	# Older Slurm versions before 20.02 do not support the "sufix" after -O and may thus not work correctly
	JOBLIST = prefix "/squeue -t RUNNING -h -O \047State: ,JobID: ,JobArrayID: ,UserName: ,GroupName: ,Account: ,StartTime: ,EndTime: ,TimeUsed: ,Partition: ,NumNodes: ,tres-alloc: ,NodeList: ,Name:\047 " selection
	while ((JOBLIST | getline) > 0) {
		JobState=$1
		JobID=$2
		JobArrayID=$3
		User=$4
		Group=$5
		Account=$6
		StartTime=$7
		EndTime=$8
		TimeUsed=$9
		Partition=$10
		NumNodes=$11
		TresAlloc=$12
		NodeList=$13
		JobName=$14
		if (JobName=="") JobName="(None)"
		# Select job information to be printed for this job
		if (JobArrayID == JobID) 
			JobInfo = JobID 
		else {
			# Identify array jobs
			arrayjobs++
			JobInfo = JobID 
		}
		if (printaccount == 0) 
			JobInfo = JobInfo " " User " "
		else {
			JobInfo = JobInfo " " User "(" Account ") "
		}
		if (printgres == 1) {
			GRES = RED "(null)" NORMAL	# Default is null GRES in RED color
			# Parse the tres-alloc (TresAlloc) list to extract only GPU gres/gpu:
			split (TresAlloc, treslist, ",")
			for (i in treslist) {
				# Additional tres-alloc values could be extracted here if desired
				if (index(treslist[i], "gres/gpu=") > 0) {
					# The "generic" GPU field "gres/gpu="
					# Omit the "gres/" string and start at char 6:
					GRES = substr(treslist[i],6)
				} else if (index(treslist[i], "gres/gpu:") > 0) {
					# The "specific" GPU field "gres/gpu:" overrides the "generic" GPU field
					# Omit the "gres/" string and start at char 6:
					GRES = substr(treslist[i],6)
				}
			}
			JobInfo = JobInfo GRES " "
			# Job GRES width for formatting the width below:
			if (length(GRES) > jobgreswidth) jobgreswidth = length(GRES)
		}
		if (printjobname == 1) JobInfo = JobInfo JobName " "
		if (printjobstarttime == 1) JobInfo = JobInfo StartTime " "
		if (printjobendtime == 1) JobInfo = JobInfo EndTime " "
		if (printtimeused == 1) JobInfo = JobInfo TimeUsed " "
		# May select a UNIX group name
		if (groupname != "" && Group != groupname) continue
		# Convert job TimeUsed days-hours:minutes:seconds into seconds
		i = split(TimeUsed,hms,":")
		if (i == 1)
			TimeUsedSec = hms[1]			# Seconds 
		else if (i == 2)
			TimeUsedSec = hms[1]*60 + hms[2]	# Minutes:seconds
		else {
			if (split(hms[1],dh,"-") == 1)
				TimeUsedSec = hms[1]*3600 + hms[2]*60 + hms[3]	# No days- field
			else
				TimeUsedSec = dh[1]*86400 + dh[2]*3600 + hms[2]*60 + hms[3]
		}

		# Create the list of nodes for this job, and expand the list for multiple nodes
		if (index(NodeList,"[") == 0 && index(NodeList,",") == 0) {	# Just a single node name
			jobnodes[1] = NodeList
		} else {		# Multiple nodes when the characters , or [ appear in NodeList
			# Put hostname lines into an array jobnodes[]
			cmd = HOSTLIST NodeList
			i=0
			while ((cmd | getline) > 0) jobnodes[++i] = $1
			close (cmd)
		}
		# Populate the jobs arrays with "JobID User" (Multiple jobs may exist on each node, and EndTime may be added).
		# Populate the partitions array from job info.
		for (i in jobnodes) {
			n = jobnodes[i]
			hostname[n] = n
			jobs[n] = jobs[n] JobInfo
			# Record the TimeUsedSec for the most recently started job on this node
			if (mostrecentjob[n] == 0 || TimeUsedSec < mostrecentjob[n])
				mostrecentjob[n] = TimeUsedSec
			# Has partitions on this node been set previously?
			if (partitions[n] == "") {
				# Set the partition name from this running job
				partitions[n] = Partition
			} else if (partitions[n] != Partition) {
				# This node runs jobs from multiple, distinct partitions: Denote this by a "+"
				multipartitions[n] = "+"
			}
			numjobs[n]++
			if (NumNodes > 1) multinodejobs[n]++		# Increment for nodes running multi-node jobs (%D>1)
			# If username has been selected and node "n" runs job belonging to username:
			if (User == username) selecteduser[n] = User
			if (Group == groupname) selectedgroup[n] = Group
		}
		delete jobnodes
	}
	close (JOBLIST)

	# Format the column header:
	# The job information may include EndTime etc.
	if (arrayjobs == 0)
		JobInfo = "JobID"
	else
		JobInfo = "JobID(JobArrayID)"
	if (printaccount == 0)
		JobInfo = JobInfo " User"
	else
		JobInfo = JobInfo " User(Account)"
	if (printgres == 1) JobInfo = JobInfo " GRES/job"
	if (printjobname == 1) JobInfo = JobInfo " JobName"
	if (printjobstarttime == 1) JobInfo = JobInfo " StartTime"
	if (printjobendtime == 1) JobInfo = JobInfo " EndTime"
	if (printtimeused == 1) JobInfo = JobInfo " TimeUsed"
	JobInfo = JobInfo " ..."
	# Print a header line (variable hostnamelength)
	if (printgres == 1) {	# Print GRES column (if requested)
		printf("%-*s %15s %8s %7s %8s %8s %8s  %*-s %s\n", hostnamelength, "Hostname", "Partition", "Node", "Num_CPU", "CPUload", "Memsize", "Freemem", nodegreswidth, "GRES/node", "Joblist")
		printf("%-*s %15s %8s %7s %8s %8s %8s  %*-s %s\n", hostnamelength, "", "", "State", "Use/Tot", "(15min)", "(MB)", "(MB)", nodegreswidth, "", JobInfo)
	} else {
		printf("%-*s %15s %8s %7s %8s %8s %8s  %s\n", hostnamelength, "Hostname", "Partition", "Node", "Num_CPU", "CPUload", "Memsize", "Freemem", "Joblist")
		printf("%-*s %15s %8s %7s %8s %8s %8s  %s\n", hostnamelength, "", "", "State", "Use/Tot", "(15min)", "(MB)", "(MB)", JobInfo)
	}
}
{
	#####################################################################################
	# Main section: Process lines from sinfo

	node=$1
	# Selection of subset of nodes
	if (selection != "" && jobs[node] == "") next
	if (username != "" && selecteduser[node] == "") next
	if (groupname != "" && selectedgroup[node] == "") next

	# Get partition information from squeue (job centric info) if possible
	if (uniquenodes && node in partitions) {
		# Add the multipartitions "+" character if jobs from more than 1 partition run on the node
		partition = partitions[node] multipartitions[node]
		if (index($2, "*") > 0)	# Add "*" to nodename in default partition
			partition = partition "*"
	} else {
		# Fallback to node centric information from sinfo (also if uniquenodes is set from the option -2)
		partition = $2
	}
	# CPU info: sinfo -o %C gives number of CPUs by state in the format "allocated/idle/other/total"
	split($3, cpulist, "/")
	allocated_cores = cpulist[1]
	total_cores = cpulist[4]
	cpuload=$4
	memory=$5
	freemem=$6
	state=$7
	if (state == "idle~" || state == "drain~") next	# Skip nodes that are powered down (idle~,drain~)
	gsub("$", "", state)	# Strip "$" for state=maintenance
	gsub("@", "", state)	# Strip "@" for pending reboot nodes
	# Use the threads per CPU core to calculate "permissible" min/max CPU load:
	threadspercore=$8
	# Generic resources (GRES) associated with the node
	nodegres=$9

	# Select only subset of nodes with certain values/states
	listnode = printallnodes
	# Omit nodes with statedown states (a $ may be appended to state)
	if (omitdown > 0) {
		for (i in statedownlist) {
			if (index(state, statedownlist[i]) > 0) next
		}
	}

	if (free_mem_less > 0) {
		# Free memory on the node LESS than free_mem_less
		if (freemem < free_mem_less) listnode++
	} else if (free_mem_more > 0) {
		# Free memory on the node GREATER than free_mem_more
		if (freemem > free_mem_more) listnode++
	} else {
		if (state == "drain" || state == "drng" || state == "resv" || state == "down" || state == "down~" || state == "error" || state == "comp" || state == "maint" || state == "boot") {
			# Flag nodes with status down, drain etc.
			stateflag="*"
			statecolor=RED
			listnode++
		} else {
			stateflag=" "
			statecolor=NORMAL
		}
		# Flag unexpected CPU load average on allocated cores
		if (threadspercore == 1) {
			# Single thread per core: Ideal load equals number of physical cores.
			ideal_load_min = allocated_cores
			ideal_load_max = allocated_cores
		} else {
			# Multiple threads per CPU core: Load of 1..threadspercore per physical core is OK.
			ideal_load_min = allocated_cores / threadspercore
			ideal_load_max = allocated_cores
		}
		# Calculate if cpuload is outside ideal load bounds, plus some deltas
		if (cpuload > ideal_load_max + cpuload_delta1 || cpuload < ideal_load_min - cpuload_delta1) {
			loadflag="*"
			loadcolor=RED
			cpucolor=GREEN
			listnode++
		} else if (cpuload > ideal_load_max + cpuload_delta2 || cpuload < ideal_load_min - cpuload_delta2) {
			loadflag="*"
			loadcolor=MAGENTA
			cpucolor=GREEN
			if (flaglevel == 1) listnode++
		} else {
			loadflag=" "
			loadcolor=NORMAL
			cpucolor=NORMAL
		}
		# Check CPU core utilization
		if (numjobs[node] > allocated_cores) {
 			# Flag unexpected number of jobs: Should be at least 1 task per job
			jobflag="*"
			jobcolor=RED
			listnode++
		} else if (state == "mix" && multinodejobs[node] > 0) {
			# Flag multi-node jobs running on nodes in state==mixed (possibly incorrect node utilization)
			jobflag="*"
			jobcolor=MAGENTA
			listnode++
		} else {
			jobflag=" "
			jobcolor=NORMAL
		}

		# Free memory on the node
		if (freemem < memory*memory_thres1) {	# Very high memory usage (RED)
			memflag="*"
			freememcolor=RED
			memcolor=GREEN
			listnode++
		} else if (freemem < memory*memory_thres2) {	# High memory usage (MAGENTA)
			memflag="*"
			freememcolor=MAGENTA
			memcolor=GREEN
			if (flaglevel == 1) listnode++
		} else {
			memflag=" "
			freememcolor=NORMAL
			memcolor=NORMAL
		}
	}

	# Do not flag nodes whose most recently started job was < jobgracetime seconds ago
	# because Slurm reports the 5-minute load average.
	if (mostrecentjob[node] > 0 && mostrecentjob[node] < jobgracetime) {
		# Override the listnode flag which may have been set above
		listnode = printallnodes
	}
		
	if (listnode > 0 && nodewasprinted[node] == 0) {
		if (uniquenodes > 0) nodewasprinted[node]++	# Count this node (node may be in multiple partitions)
		printf("%-*s %15s ", hostnamelength, node, partition)
		printf("%s%7s%1s%s ", statecolor, state, stateflag, NORMAL)
		printf("%s%3d%s %3d ", cpucolor, allocated_cores, NORMAL, total_cores)
		printf("%s%7.2f%1s%s ", loadcolor, cpuload, loadflag, NORMAL)
		printf("%s%8d %s%8d%1s%s ", memcolor, memory, freememcolor, freemem, memflag, NORMAL)
		if (printgres == 1) printf("%*-s ", nodegreswidth, nodegres)
		printf("%s%s%1s%s", jobcolor, jobs[node], jobflag, NORMAL)
		printf("\n")
	}
	delete cpulist
}'
