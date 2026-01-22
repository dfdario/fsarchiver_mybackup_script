#!/bin/bash
#
# THIS SCRIPT IS BASED ON THE ONE AVAILABLE AT
# https://github.com/lexo-ch/
# fsarchiver-encrypted-full-system-backup-script-with-email-monitoring-full-system-backup-script-with-email-monitoring
# 
#####################################################################
# AUTOMATED BACKUP SCRIPT WITH FSARCHIVER AND VERSIONING
#####################################################################
# This script creates backups of filesystems
# with fsarchiver and supports:
# - UUID-based detection of local backup drives
# - Network drives (SMB/CIFS, NFS) via network path detection
# - Intelligent selection of optimal backup drive
# - Automatic versioning with configurable number of versions to keep
# - Encrypted archives (optional)
# - Msg notifications with configurable messages
# - Exclusion of specific paths from backup
# - ZSTD compression with configurable level
# - Backup validation (file size and existence)
# - Protection against backing up to same drive as source
# - Handling of temporary fsarchiver mount points
# - Proper handling of interruptions (CTRL+C, SIGTERM, etc.)
#####################################################################
###########################################################
# LOG FILE SETTINGS
###########################################################
# Backup Log File Location
BACKUP_LOG="/var/log/fsarchiver-bkp.log"
if [ -f ${BACKUP_LOG} ] ; then
	cp ${BACKUP_LOG}{,.bak}
fi
###########################################################
# For debug only
###########################################################
#exec > >(sudo tee -a ${BACKUP_LOG} )
#DEBUG_FILE="./debuglog.log"
#if [ -f ${DEBUG_FILE} ] ; then
#	cp ${DEBUG_FILE}{,.bak}
#fi
#exec 2> >(tee -a ${DEBUG_FILE} >&2) # Add to existing
#exec &> >(sudo tee "$DEBUG_FILE")
#####################################################################
# USER CONFIGURATION
#####################################################################

# Backup Parameters Configuration
# Format: BACKUP_PARAMETERS["Backup Name"]="Backup-File-Base-Name:Mount-Point or Device-Path for Backup"
# IMPORTANT: The backup file name is only the base name. The script automatically adds
# a timestamp for versioning (e.g. backup-efi-20250625-123456.fsa)

#declare -A BACKUP_PARAMETERS
#BACKUP_PARAMETERS["EFI"]="backup-efi:/boot/efi"
#BACKUP_PARAMETERS["System"]="backup-system:/"

# BACKUP_PARAMETERS["DATA"]="backup-data:/media/username/DATA"  # Example - commented out

# UUID array for local backup drives and network paths for network drives
# 
# LOCAL DRIVES:
# Add the UUIDs of your local backup drives here
# To find the UUID of a drive, use the command:
# lsblk -o NAME,UUID,LABEL,SIZE,VENDOR,MODEL,MOUNTPOINT
#
# NETWORK DRIVES:
# Add the network paths of your mounted network drives here
# Format for SMB/CIFS: "//server/share" or "//ip-address/share"
# Format for NFS: "server:/path" or "ip-address:/path"
# 
# The script automatically detects whether it's a local drive (UUID) or
# network drive (contains slashes).
#
# IMPORTANT FOR NETWORK DRIVES:
# - The network drive must already be mounted before the script is executed
# - The script checks if the network drive is available and writable
# - Use the exact path as shown by findmnt
BACKUP_DRIVE_UUIDS=(
#	"3cc1f5e4-9370-431c-b89a-ae2254e15e0f"
#    "12345678-1234-1234-1234-123456789abc"     # Local USB drive (UUID) - REPLACE WITH YOUR UUID
#    "//your-server.local/backup"               # SMB network drive - REPLACE WITH YOUR PATH
#	 "192.168.1.100:/mnt/backup"              # NFS network drive example - UNCOMMENT AND EDIT
)


# Password File Location (OPTIONAL)
# For increased security, this file should be stored on an encrypted volume 
# with root-only access
# Comment out this line to create backups without encryption
# PASSWORD_FILE="/root/backup-password.txt"

# Message Content Configuration
# Available placeholders: {BACKUP_DATE}, {RUNTIME_MIN}, {RUNTIME_SEC}, {ERROR_DETAILS}
MSG_BODY_SUCCESS="Backup completed successfully on: {BACKUP_DATE}\nRuntime: {RUNTIME_MIN} minutes and {RUNTIME_SEC} seconds."
MSG_BODY_ERROR="Backup failed!\n\nBackup start: {BACKUP_DATE}\nRuntime: {RUNTIME_MIN} minutes and {RUNTIME_SEC} seconds.\n\nERROR REPORT:\n{ERROR_DETAILS}"
MSG_BODY_INTERRUPTED="Backup was interrupted!\n\nBackup start: {BACKUP_DATE}\nInterrupted after: {RUNTIME_MIN} minutes and {RUNTIME_SEC} seconds.\n\nThe backup was terminated by user intervention (CTRL+C) or system signal.\nIncomplete backup files have been removed."

# Paths to exclude from backup
# 
# IMPORTANT: HOW FSARCHIVER EXCLUSIONS WORK:
# =====================================================
# 
# fsarchiver uses shell wildcards (glob patterns) for exclusions.
# The patterns are matched against the FULL PATH from the ROOT of the backed up filesystem.
# 
# CASE-SENSITIVITY:
# ==========================================
# The patterns are CASE-SENSITIVE!
# - "*/cache/*" does NOT match "*/Cache/*" or "*/CACHE/*"
# - For both variants: "*/[Cc]ache/*" or use separate patterns
# - Common variants: cache/Cache, temp/Temp, tmp/Tmp, log/Log
# 
# EXAMPLES:
# ---------
# For a path like: /home/user/.var/app/com.adobe.Reader/cache/fontconfig/file.txt
# 
# ✗ WRONG: "/cache/*"           - Does NOT match, as /cache is not at root
# ✗ WRONG: "cache/*"            - Does NOT match, as it doesn't cover the full path  
# ✓ CORRECT: "*/cache/*"        - Matches ANY cache directory at any level
# ✓ CORRECT: "/home/*/cache/*"  - Matches cache directories in any user directory
# ✓ CORRECT: "*/.var/*/cache/*" - Matches special .var application caches
# ✓ CORRECT: "*[Cc]ache*"       - Matches both "cache" and "Cache"
# 
# MORE PATTERN EXAMPLES:
# -------------------------
# "*.tmp"              - All .tmp files
# "/tmp/*"             - Everything in /tmp directory
# "*/logs/*"           - All logs directories at any level
# "/var/log/*"         - Everything in /var/log
# "*/.cache/*"         - All .cache directories (common in user directories)
# "*/Trash/*"          - Trash directories
# "*~"                 - Backup files (ending with ~)
# "*/tmp/*"            - All tmp directories
# "*/.thumbnails/*"    - Thumbnail caches
# 
# PERFORMANCE TIP:
# -----------------
# Specific patterns are more efficient than very general patterns.
# Use "*/cache/*" instead of "*cache*" when possible.
# Use general patterns before specific patterns.
#
# CONSOLIDATED LINUX EXCLUSION LIST:
# =====================================
EXCLUDE_PATHS=(
    # ===========================================
    # CACHE DIRECTORIES (ALL VARIANTS)
    # ===========================================
    
    # General cache directories (covers most browsers and apps)
#    "*/cache/*"                     # All cache directories (lowercase)
#    "*/Cache/*"                     # All Cache directories (uppercase)  
#    "*/.cache/*"                    # Hidden cache directories (Linux standard)
#    "*/.Cache/*"                    # Hidden Cache directories (uppercase)
#    "*/caches/*"                    # Plural form cache directories
#    "*/Caches/*"                    # Plural form Cache directories (uppercase)
#    "*/cache2/*"                    # Browser Cache2 directories (Firefox, etc.)
    
    # Specific cache directories (more robust patterns)
#    "/root/.cache/*"                # Root user cache (specific)
#    "/home/*/.cache/*"              # All user cache directories (specific)
#    "*/mesa_shader_cache/*"         # Mesa GPU shader cache
    
    # Special cache types
#    "*/.thumbnails/*"               # Thumbnail caches
#    "*/thumbnails/*"                # Thumbnail caches (without dot)
#    "*/GrShaderCache/*"             # Graphics shader cache (browser/games)
#    "*/GPUCache/*"                  # GPU cache (browser)
#    "*/ShaderCache/*"               # Shader cache (games/graphics)
#    "*/Code\ Cache/*"               # Code cache (Chrome/Chromium/Electron apps)
    
    # ===========================================
    # TEMPORARY DIRECTORIES AND FILES
    # ===========================================
    
    # Standard temporary directories
    "/tmp/*"                        # Temporary files
    "/var/tmp/*"                    # Variable temporary files
    "*/tmp/*"                       # All tmp directories
    "*/Tmp/*"                       # All Tmp directories (uppercase)
    "*/temp/*"                      # All temp directories
    "*/Temp/*"                      # All Temp directories (uppercase)
    "*/TEMP/*"                      # All TEMP directories (uppercase)
    "*/.temp/*"                     # Hidden temp directories
    "*/.Temp/*"                     # Hidden Temp directories (uppercase)
    
    # Browser-specific temporary directories
#    "*/Greaselion/Temp/*"           # Brave browser Greaselion temp directories
#    "*/BraveSoftware/*/Cache/*"     # Brave browser cache
#    "*/BraveSoftware/*/cache/*"     # Brave browser cache (lowercase)
    
    # Temporary files
    "*.tmp"                         # Temporary files
    "*.temp"                        # Temporary files
    "*.TMP"                         # Temporary files (uppercase)
    "*.TEMP"                        # Temporary files (uppercase)
    
    # ===========================================
    # LOG DIRECTORIES AND FILES
    # ===========================================
    
    # System logs
    "/var/log/*"                    # System log files (general)
    "/var/log/journal/*"            # SystemD journal logs (can become very large)
    "*/logs/*"                      # All log directories
    "*/Logs/*"                      # All Log directories (uppercase)
    
    # Log files
    "*.log"                         # Log files
    "*.log.*"                       # Rotated log files
    "*.LOG"                         # Log files (uppercase)
    "*/.xsession-errors*"           # X-session logs
    "*/.wayland-errors*"            # Wayland session logs
    
    # ===========================================
    # SYSTEM CACHE AND SPOOL
    # ===========================================
    
    # NOTE: All /var/cache/* patterns are covered by */cache/*
    "/var/spool/*"                  # Spool directories (print jobs, etc.)
    
    # ===========================================
    # MOUNT POINTS AND VIRTUAL FILESYSTEMS
    # ===========================================
    
    # External drives and mount points
    "/media/*"                      # External drives
    "/mnt/*"                        # Mount points
    "/run/media/*"                  # Modern mount points
    
    # Virtual filesystems (should not be in backups)
    "/proc/*"                       # Process information
    "/sys/*"                        # System information  
    "/dev/*"                        # Device files
    "/run/*"                        # Runtime information
    "/var/run/*"                    # Runtime variable files (usually symlink to /run)
    "/var/lock/*"                   # Lock files (usually symlink to /run/lock)
    
    # ===========================================
    # DEVELOPMENT AND BUILD DIRECTORIES
    # ===========================================
    
    # Node.js and JavaScript
    "*/node_modules/*"              # Node.js packages
    "*/.npm/*"                      # NPM cache
    "*/.yarn/*"                     # Yarn cache
    
    # Rust
#    "*/target/debug/*"              # Rust debug builds
#    "*/target/release/*"            # Rust release builds
#    "*/.cargo/registry/*"           # Rust cargo registry cache
    
    # Go
#    "*/.go/pkg/*"                   # Go package cache
    
    # Build directories (general)
#    "*/target/*"                    # Rust/Java build directories (general)
#    "*/build/*"                     # Build directories
#    "*/Build/*"                     # Build directories (uppercase)
#    "*/.gradle/*"                   # Gradle cache
#    "*/.m2/repository/*"            # Maven repository
    
    # Python
#    "*/__pycache__/*"               # Python cache
#    "*/.pytest_cache/*"             # Pytest cache
#    "*.pyc"                         # Python compiled files
    
    # ===========================================
    # CONTAINERS AND VIRTUALIZATION
    # ===========================================
    
#    "/var/lib/docker/*"             # Docker data
#    "/var/lib/containers/*"         # Podman/container data
    
    # ===========================================
    # FLATPAK AND SNAP CACHE DIRECTORIES
    # ===========================================
    
    # Flatpak repository and cache (safe to exclude - can be re-downloaded)
#    "/var/lib/flatpak/repo/*"       # OSTree repository objects (like Git objects)
#    "/var/lib/flatpak/.refs/*"      # OSTree references
#    "/var/lib/flatpak/system-cache/*" # System cache
#    "/var/lib/flatpak/user-cache/*" # User cache
    
    # Flatpak app-specific caches (user directories)
#    "/home/*/.var/app/*/cache/*"    # App-specific caches
#    "/home/*/.var/app/*/Cache/*"    # App-specific caches (uppercase)
#    "/home/*/.var/app/*/.cache/*"   # Hidden caches in apps
#    "*/.var/app/*/cache/*"          # All Flatpak app caches
#    "*/.var/app/*/Cache/*"          # All Flatpak app caches (uppercase)
    
    # Snap cache directories
#    "/var/lib/snapd/cache/*"        # Snap cache
#    "/home/*/snap/*/common/.cache/*" # Snap app caches
    
    # OPTIONAL - If you do not want to reinstall Flatpak apps, 
    # comment out these lines:
    # "/var/lib/flatpak/runtime/*"  # Runtime environments (can be reinstalled)
    # "/var/lib/flatpak/app/*"      # Installed apps (can be reinstalled)
    
    # ===========================================
    # BACKUP AND OLD FILES
    # ===========================================
    
    # Backup files
    "*~"                            # Backup files (editor backups - always exclude)
    
    # Backup files (OPTIONAL - uncomment if backup files should be kept)
    # "*.bak"                       # Backup files
    # "*.BAK"                       # Backup files (uppercase)
    # "*.backup"                    # Backup files
    # "*.BACKUP"                    # Backup files (uppercase)
    # "*.old"                       # Old files
    # "*.OLD"                       # Old files (uppercase)
    
    # ===========================================
    # TRASH (OPTIONAL - commented out, as trash should be backed up by default)
    # ===========================================
    
    # NOTE: Trash directories are NOT excluded by default,
    # as they may contain important deleted files that need to be restored.
    # Uncomment these lines only if you are sure the trash
    # should not be backed up:
    
    # "*/.Trash/*"                  # Trash
    # "*/Trash/*"                   # Trash (without dot)
    # "*/.local/share/Trash/*"      # Trash (modern Linux location)
    # "*/RecycleBin/*"              # Windows-style trash (if present)
    
    # ===========================================
    # SWAP FILES
    # ===========================================
    
    "/swapfile"                     # Standard swap file
    "/swap.img"                     # Alternative swap file
    "*.swap"                        # Swap files
    "*.SWAP"                        # Swap files (uppercase)
    
    # ===========================================
    # OTHER COMMON EXCLUSIONS
    # ===========================================
    
    # Other common exclusions
    # NOTE: Specific Flatpak/Snap cache patterns are redundant, as already covered by 
    # */cache/* and */.cache/*
    
    # Lock and socket files
#    "*/.X11-unix/*"                 # X11 sockets
#    "*/lost+found/*"                # Lost+found directories
#    "*/.gvfs/*"                     # GVFS mount points
    
    # Multimedia caches
#    "*/.dvdcss/*"                   # DVD CSS cache
#    "*/.mplayer/*"                  # MPlayer cache
#    "*/.adobe/Flash_Player/*"       # Flash Player cache
   
    # Encrypted directories when unmounted
#    "*/.ecryptfs/*"                 # eCryptFS
    
    # ===========================================
    # LARGE IMAGE FILES (OPTIONAL - commented out as they can be very large)
    # ===========================================
    
    # NOTE: These patterns are commented out, as image files often
    # contain important data. Uncomment these only if you are sure
    # these files should not be backed up:
    
    # "*.iso"                       # ISO image files 
    # "*.img"                       # Disk image files
    # "*.vdi"                       # VirtualBox images (can be very large)
    # "*.vmdk"                      # VMware images (can be very large)
    
    # Games and Steam (specific caches/logs not covered by */cache/*)
#    "*/.steam/steam/logs/*"         # Steam logs
#    "*/.steam/steam/dumps/*"        # Steam crash dumps
#    "*/.local/share/Steam/logs/*"   # Steam logs (alternative location)
)

#####################################################################
# SYSTEM FUNCTIONS AND HELPER FUNCTIONS
#####################################################################

# Color codes for formatted output
RED='\033[1;93;41m'     # Bold yellow text on red background for maximum visibility of errors
GREEN='\033[1;92m'
YELLOW='\033[1;33;104m'
BLUE='\033[0;34;106m'
NC='\033[0m' # No Color
# Color codes for formatted dialog
nc="\Zn" # Reset all Styling
bold="\Zb" # Start Bold
nbold="\ZB" # End Bold
rev="\Zr" # Start Reverse
nrev="\ZR" # End Reverse
und="\Zu" # Start Underline
nund="\ZU" # End Underline
black="\Z0" # ANSI Colors: Black (Default)
red="\Z1" # ANSI Colors: Red
green="\Z2" # ANSI Colors: Green
yellow="\Z3" # ANSI Colors: Yellow
blue="\Z4" # ANSI Colors: Blue
magenta="\Z5" # ANSI Colors: Magenta
cyan="\Z6" # ANSI Colors: Cyan
white="\Z7" # ANSI Colors: White

# Global variables for error handling and signal handling
ERROR=0
ERROR_MSG=""
SCRIPT_INTERRUPTED=false
CURRENT_BACKUP_FILE=""
CURRENT_FSARCHIVER_PID=""

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Script must be run as root. Exiting...${NC}"
   exit 1
fi

#####################################################################
# SIGNAL HANDLING AND CLEANUP FUNCTIONS
#####################################################################
function showMenu() {
# Input: TITLE, BACKTITLE, MENU, HEIGHT, WIDTH, CHOICE_HEIGHT, ARRAY
# Output: SELECTION
	CHOICE=""
	local TITLE="$1"
	local BACKTITLE="$2"
	local MENU="$3"
	local HEIGHT="$4"
	local WIDTH="$5"
	local CHOICE_HEIGHT="$6"; shift
	local OPTIONS=( "$@" )
	local SELECTION
	#printf "%s\n" "${OPTIONS[@]}"
	#echo "${TITLE}"'|'"${BACKTITLE}"'|'"${MENU}"'|'"${HEIGHT}"'|'"${WIDTH}"'|'"${CHOICE_HEIGHT}" 
	for (( i=${#OPTIONS[@]}-1; i>=0; i-- ));
	do
	# echo "${ARR_CHOICE[i]}"
	if [[ ${OPTIONS[i]} = @("${TITLE}"|"${BACKTITLE}"|"${MENU}"|"${HEIGHT}"|"${WIDTH}"|"${CHOICE_HEIGHT}") ]]; then
		unset 'OPTIONS[i]' # Cleanup spurious elements in array
	fi
	done
	# display the menu dialog box
	SELECTION=$(dialog --clear \
	--colors \
	--backtitle "$BACKTITLE" \
	--title "$TITLE" \
	--menu "$MENU" \
	$HEIGHT $WIDTH $CHOICE_HEIGHT \
	"${OPTIONS[@]}" \
	2>&1 >/dev/tty)
	if [[ $? -ne 0 || ! "$SELECTION" ]]; then
		return 1
	fi
	CHOICE=`echo ${SELECTION}| tr -d '"'`
	return 0
}

function askPass() {
	# Input: "Title" "Height" "width"
	# Output: the password
	local rcode=0
	while test $rcode != 1 && test $rcode != 250 
	do
		exec 3>&1
		psw=`dialog  --colors --title "PASSWORD" \
	--clear \
	--insecure \
	--passwordbox "$1" "$2" "$3" 2>&1 1>&3`
		rcode=$?
		exec 3>&-
		if [ $psw ]; then
			psw=`echo "${psw}" | awk '{ if (length($0)>=6 && match($0,/[A-Z] || [a-z] || [0-9] || [#$&~@^]/)) print $0; }' `
			echo $psw
			if [ $psw ]; then export psw; return 0; fi
			showMsg "password have character(s) not allowed,\nor lenght is less than the requested." 8 50
		else
			return 1;
		fi
	done
}

function defPsw() {
	backtitle="PASSWORD DEFINITION:"
	local retcode=0
	local psw1, psw2
	while test $retcode != 1 && test $retcode != 250
	do
		askPass "${bold}Enter the desired password or ${red}leave empty${nc}${bold} for no Password.${nc}\nPassword should have at least ${bold}${red}6${nc} characters long, and may include a combination of ${bold}${red}letters, numbers, and symbols${nc}." 12 50
		retcode=$?
		if [[ $retcode = 1 || $retcode = 255 ]]; then return 1; fi
		psw1=$psw
		askPass "${bold}Please reenter the password.\nPassword should have at least ${bold}6${nc} characters long, and may include a combination of ${bold}letters, numbers, and symbols${nc}." 12 50
		retcode=$?
		psw2=$psw
		case $retcode in
		255)
			echo "pressed cancel"
			FSPASS=""
			return 1
		;;
		0)
			echo "1: $psw1"
			echo "2: $psw2"
			if [[ ! "${psw1}" && ! "${psw2}" ]]; then return 1; fi # No password entered
			if [ "${psw1}" = "${psw2}" ]; then 
				FSPASS=`echo "${psw1}" | awk '{ if (length($0)>=6 && match($0,/[A-Z] || [a-z] || [0-9] || [#$&~@^]/)) print $0; }' `
				echo $FSPASS
				if [ ! $FSPASS ]; then
					showMsg "\npassword have character(s) not allowed,\nor lenght is less than the requested." 14 40
				else
					export FSPASS
					return 0;
				fi
			else
				showMsg "\nPasswords did not match\nReenter please." 10 40
			fi
		;;
		*)
			echo "Return code was $retcode"
			return 1
			;;
		esac
	done
}


#####################################################################
# Select the backup directory
#####################################################################
# Input: "Starting DIRECTORY", Type of selection: "d" for directory, "f" for files,  or file extension eg. "fsa",
#        "" stands for don't care
# Output: The complete path of the selected directory/file  
# Note:   The possible selections never go below the starting point
function select_bkup_d-f() {
	IFS=$'\n'
	#START_DIR=(`pwd`)
	#CURR_UUID=$1
	START_DIR=$1
	if [ $2 ]; then
		if [ ${#2} -gt 1  ]; then 
			local tipo="";
			local fsel=$2
		else
			local tipo="-type $2"
			local fsel=""
		 fi
	fi
	CURR_DIR=$START_DIR
	#local DIR_ARR=(`find "${START_DIR}" -maxdepth 1 -type d`)
	local DIR_ARR=()
	local PREV_DIR=$START_DIR
	local ARR_PARAMETER=()
	while true; do
		if [[ "$CURR_DIR" != "$START_DIR"  ]]; then
			PREV_DIR=`dirname "${CURR_DIR}"`
		fi
		#CURR_DIR="${CURR_DIR}/"
		local ARR_PARAMETER=()
		local DIR_ARR=()
		local LIST_DIR=()
		CURR_DIR=${CURR_DIR%*/}
		#echo "curr_dir= "${CURR_DIR}
		#read -p "Press enter to continue"
		printf '%s\n' "${LIST_DIR[@]}"
		LIST_DIR=(`sh -c "find '${CURR_DIR}' -maxdepth 1 $tipo"`)
		LIST_DIR=("${LIST_DIR[@]:1}")  # Remove the directory in which list is done
		for dir in "${LIST_DIR[@]}"; do    # list directories in the form "/tmp/dirname/"
			dir=${dir%*/}      # remove the trailing "/"
			if [[ -d "$dir" ]] || [[ "${dir##*.}" = $fsel ]]; then    # check if is a file and has an the passed extension
				DIR_ARR+=(`echo "${dir##*/}"`)    # print everything after the final "/"
			fi
		done
		#DIR_ARR=("${DIR_ARR[@]:1}")
		#printf '%s\n' "${DIR_ARR[@]}"
		#read -p "Press enter to continue"
		for (( i=${#DIR_ARR[@]}-1; i>=0; i-- ));
		do
			# if needed, remove [xxx] from device name as it gives trouble with grep
			DIRS=`echo "${DIR_ARR[i]}"`
			if [[ "${DIRS}" != @(*".Trash"*|*"\$RECYCLE.BIN"*|*"lost+found"*|*"$ARCH_DIR"*) ]]; then
				# add it to the parameters list
				ARR_PARAMETER=( "${DIRS}" " " ${ARR_PARAMETER[@]} )
			fi
		done
		#
		#if [ ! "${CURR_DIR}" = "${START_DIR}" ]; then
		if [ ! "${START_DIR}${CURR_DIR}" = "${START_DIR}/" ]; then
			ARR_PARAMETER=( "< Back >" "Back one directory" ${ARR_PARAMETER[@]} )
			ARR_PARAMETER=( "< Finish >" "Select current directory" ${ARR_PARAMETER[@]} )
		fi

	# display the dialog box to choose devices
		DRILL="Please select a directory/file from:\n${bold}${CURR_DIR}${nc}.\n< Finish > confirm, < OK > drill down, < Cancel > exit."
		showMenu  "DIRECTORY SELECTION" "FSarchiver-Backup" "$DRILL" "18" "70" "5" "${ARR_PARAMETER[@]}"
		if [[ $? -ne 0 ]]; then
			return 1
		fi
		CHOICE="${CHOICE}"
		case "$CHOICE" in
			"< Back >")
				CURR_DIR="${PREV_DIR%*}"
				# echo "CURR_DIR bak= "$CURR_DIR
				#read -p "Press enter to continue"
			;;
			"< Finish >")
				CHOICE=${CURR_DIR}
				echo ${CURR_DIR}
				return 0
				#read -p "Press enter to continue"
			;;
			*)
				PREV_DIR="$CURR_DIR"
				CURR_DIR="${CURR_DIR%*}/$CHOICE"
				#CURR_DIR="${CURR_DIR%/}" 
				#read -p "Press enter to continue"
			;;
		esac
		#read -p "Press enter to continue"
	done
	IFS="\ "
	echo ${CURR_DIR}
    return 0
}

function best_dir() {
# Since storage directories might result in multiple mount points
# it find the best storage dir path from the passed UUID or directory path
	IFS=$'\ \| \n'
	local best_dir
	if [[ "$1" =~ ^/ ]]; then
		best_dir="${1}"
	else
		if ! check_uuid_mounted "${1}"; then
			showYN "Device ${DEVICE} appears not mounted.\nYou might want to mount it outside this program or either\n\ndo you want I mount it for you on /tmp/fsa?" 10 40
			if [[ $? -eq 1 ]]; then
				return 1
			fi
			if [ ! -d /tmp/fsa ]; then
				mkdir /tmp/fsa
			fi
			mount $(readlink -f /dev/disk/by-uuid/"$1") /tmp/fsa
			sleep 3
		fi
		best_dir=$(echo `findmnt -n -o TARGET $(blkid -U "${1}")`)
		#IFS=$'\n'
	fi
	BEST_DIR=""
	for dir in ${best_dir}
	do
    dir=$(echo $dir | sed 's/\/$//')
    if [[ "${dir}" = @("/media"*|"/mnt"*|"/run/media"*|"/tmp/fsa"*) ]]; then
		BEST_DIR=$dir
		echo $BEST_DIR
		return 0;
	fi
	return 1;
done
}

#####################################################################
# Select a disk/partition
#####################################################################
# Input:
# $1 Containing the prompt to show in menu
# $2 Containing filter between "disk" and "part" for disk and partition
# $3 Containing "-i" for include or "-v" to exclude
# $4 Containing for example "vfat" or "extX" in combination with $3
# Output:
# Selected disk/partition
function select_device() {
	#Function to choose a device
	#
	IFS=$'\n'
	ARR_TOT=()
	DEVICE_ID=()
	LIST_DEVICE=()
	ARR_PARAMETER=()
	NO_UNMOUNT="$5"
	# list all USB devices, excluding root & hubs
	BLK=(`lsblk -l -o NAME,SIZE,FSTYPE,UUID,TYPE | grep -e $2`)
	if [ $3 ]; then BLK=(`printf '%s\n' "${BLK[@]}" | grep $3 $4`); fi
	ARR_TOT=(`printf '%s\n' "${BLK[@]}" | awk -F' '  '{print $1" ",$2" ",$3" ",$4" "}'`) 
	DEVICE_ID=(`printf '%s\n' "${BLK[@]}" | awk -F' '  '{print $1}'`)
	LIST_DEVICE=(`printf '%s\n' "${BLK[@]}" | awk -F' '  '{print $3,$2,$4}'`)
	# loop through the devices array to generate menu parameter
	for (( i=${#DEVICE_ID[@]}-1; i>=0; i-- ));
	do
		# if needed, remove [xxx] from device name as it gives trouble with grep
		DEVID=`echo "${DEVICE_ID[i]}"`
		DEVICE=`echo "${LIST_DEVICE[i]}" | sed 's/\[.*\]//g'`
		# add it to the parameters list
		# ARR_PARAMETER=( ${DEVID} ${DEVICE} "OFF" ${ARR_PARAMETER[@]} )
		ARR_PARAMETER+=( ${DEVID} ${DEVICE} )
	done
	printf '%s\n' "${ARR_PARAMETER[@]}" 
	showMenu  "DEVICE CHOICE" "FSarchiver-Backup" "$1" "18" "60" "5" "${ARR_PARAMETER[@]}"
	if [[ ! "${DEVICE}" || $? -ne 0 ]]; then
		return 1
	fi
	DEVICE=`echo ${CHOICE}| tr -d '"'`
	for i in "${!ARR_TOT[@]}"; do
		if [[ "${DEVICE_ID[$i]}" = "${CHOICE}" ]]; then
			echo "trovato:" "${ARR_TOT[$i]}";
			UUID=`echo "${ARR_TOT[$i]}" | awk -F' '  '{print $4}' | tr -d '"'`
			if check_uuid_mounted ${UUID} && [ ! "${NO_UNMOUNT}" ]; then
				if [ `df -P / | sed -n '$s/[[:blank:]].*//p'` = "/dev/${DEVICE}" ]; then
					showInfo "The partition ${red}${bold}/dev/${DEVICE}${nc} you have selected is the one you are running on, then for security reasons it ${red}${bold}will not be unmounted${nc}." 8 50 5
				else
					umount /dev/${DEVICE}
				fi
			fi
		fi
	done

	#UUID=`echo ${CHOICE}| awk -F' '  '{print $2}' | tr -d '"'`
	sgdisk -v /dev/$(echo $DEVICE | sed 's/[0-9]//g') # Check GPT partition table and repair
	if [ $? != 0 ]; then
		showYN "The "$(echo $DEVICE | sed 's/[0-9]//g')" disk has problems and FSarchiver may not work properly\n \
		before use you should repair with commands:\n \
		sudo sgdisk -r /dev/"$(echo $DEVICE | sed 's/[0-9]//g')"\n \
		or other expert commands\n      Would you continue anyway?" 15 70
		if [[ $? -eq 1 ]]; then
			#cleanup_on_interrupt
			return 1;
		fi
	fi
	local fstype=$(findmnt -n -o FSTYPE "/dev/$DEVICE" 2>/dev/null)
	if [[ "${fstype}" = @("ext4"|"ext3"|"ext2") ]]; then # If EXTn verify partition consistency
		e2fsck -vfy "/dev/${DEVICE}"
	fi

	echo "device: "$DEVICE
	echo "UUID: "$UUID
	IFS="\ " read -a ARR_CHOICE <<< "$CHOICE"
	#printf '%s\n' "${ARR_CHOICE[@]}" 
}

#########################################################
# Function to check if a UUID is mounted or not
# Input:  The UUID of the drive, such as that reported by blkid
# Output: Returns value 0 if mounted, 1 if not mounted
function check_uuid_mounted() {
	local input_path=$(readlink -f /dev/disk/by-uuid/"$1")
	local input_maj_min=$(stat -c '%T %t' "$input_path")

	cat /proc/mounts | cut -f-1 -d' ' | while read block_device; do
		if [ -b "$block_device" ]; then
			local block_device_real=$(readlink -f "$block_device")
			local blkdev_maj_min=$(stat -c '%T %t' "$block_device_real")
			if [ "$input_maj_min" == "$blkdev_maj_min" ]; then
				return 255
			fi
		fi
	done
	if [ $? -eq 255 ]; then
		return 0
	else
		return 1
	fi
}

# Function to clean up on interruption
function cleanup_on_interrupt() {
	echo -e "\n${YELLOW}Backup interruption detected...${NC}"
	SCRIPT_INTERRUPTED=true
	ERROR=1
	ERROR_MSG+="Backup was interrupted by user intervention or system signal.\n"

	# Try to terminate fsarchiver process if still active
	if [[ -n "$CURRENT_FSARCHIVER_PID" ]]; then
		echo -e "${YELLOW}Terminating fsarchiver process (PID: $CURRENT_FSARCHIVER_PID)...${NC}"
		kill -TERM "$CURRENT_FSARCHIVER_PID" 2>/dev/null
		sleep 2
		# If process is still running, force kill
		if kill -0 "$CURRENT_FSARCHIVER_PID" 2>/dev/null; then
			echo -e "${YELLOW}Force terminating fsarchiver process...${NC}"
			kill -KILL "$CURRENT_FSARCHIVER_PID" 2>/dev/null
		fi
		CURRENT_FSARCHIVER_PID=""
	fi

	# Remove incomplete backup file
	if [[ -n "$CURRENT_BACKUP_FILE" && -f "$CURRENT_BACKUP_FILE" ]]; then
		echo -e "${YELLOW}Removing incomplete backup file: $(basename "$CURRENT_BACKUP_FILE")${NC}"
		rm -f "$CURRENT_BACKUP_FILE"
		if [[ $? -eq 0 ]]; then
			echo -e "${GREEN}✓ Incomplete backup file removed${NC}"
		else
			echo -e "${RED}✗ Error removing incomplete backup file${NC}"
			ERROR_MSG+="Error removing incomplete backup file: $CURRENT_BACKUP_FILE\n"
		fi
		CURRENT_BACKUP_FILE=""
	fi

	# Clean up fsarchiver mount points on interruption
	echo -e "${YELLOW}Cleaning up fsarchiver mount points after interruption...${NC}"
	cleanup_fsarchiver_mounts true

	# Log entry for interruption
	if [[ -n "$BACKUP_LOG" ]]; then
		echo "Backup interrupted: $(date +%d.%B.%Y,%T)" >> "$BACKUP_LOG"
	fi

	echo -e "${YELLOW}Cleanup completed. Script will exit.${NC}"
}

# Set up signal handlers
# Handles SIGINT (Ctrl+C), SIGTERM (termination), and SIGHUP (terminal closed)
trap 'cleanup_on_interrupt; send_interrupted_message_and_exit' SIGINT SIGTERM SIGHUP

# Function to send interruption email and exit
function send_interrupted_message_and_exit() {
	# Calculate runtime
	if [[ -n "$TIME_START" ]]; then
		TIME_DIFF=$(($(date +"%s")-${TIME_START}))
		RUNTIME_MINUTES=$((${TIME_DIFF} / 60))
		RUNTIME_SECONDS=$((${TIME_DIFF} % 60))
	else
		RUNTIME_MINUTES=0
		RUNTIME_SECONDS=0
	fi

	# Show interruption message
	local msg_body="${MSG_BODY_INTERRUPTED}"
	msg_body="${msg_body//\{BACKUP_DATE\}/${BACKUP_START_DATE:-$(date +%d.%B.%Y,%T)}}"
	msg_body="${msg_body//\{RUNTIME_MIN\}/$RUNTIME_MINUTES}"
	msg_body="${msg_body//\{RUNTIME_SEC\}/$RUNTIME_SECONDS}"
	
	showError "$msg_body" 15 50

	echo -e "${YELLOW}Interruption message showed${NC}"
	echo -e "${YELLOW}========================================${NC}"
	echo -e "${YELLOW}BACKUP WAS INTERRUPTED${NC}"
	echo -e "${YELLOW}Runtime: $RUNTIME_MINUTES minutes and $RUNTIME_SECONDS seconds${NC}"
	echo -e "${YELLOW}========================================${NC}"

	exit 130  # Standard exit code for SIGINT
}

function showError() {
	# Input "Error_msg" "Height" "Width"
	CUR_DATE=`date '+%Y-%m-%d %H:%M:%S'`
	echo "$CUR_DATE - ERROR :: $1" >> $BACKUP_LOG
	dialog --colors --title "ERROR" --backtitle "${bold}ERROR MANAGER${nc}" --msgbox "\n${red}${rev}ERROR: ${nc}\n   ${red}${bold}$1${nc}\n\n${black}${bold}       Program will exit${nc}" "$2" "$3"
	#cleanup_on_interrupt
	return 1
}

function showInfo() {
	# Input "Infor_msg" "Height" "Width" "Prompt_duration"
	dialog --colors --infobox "$1" "$2" "$3"
	sleep "$4"
}

function showMsg() {
	# Input "Msg" "Height" "Width"
	dialog --colors --msgbox "$1" "$2" "$3" 2>&1 >/dev/tty
}

function showYN() {
	# Input "Question" "Height" "Width"
	answer=$(dialog --colors --clear --stdout --title "What to do?" \
	--backtitle "FSarchiver-Backup" \
	--yesno "$1" "$2" "$3")
	return $answer
}

function showInput() {
	# Input:   "Title" "Prompt_message" "Width" "Default_value"
	# Output:  The value inserted
	# example: showInput "Title" "Message prompt" "Width" "Height" "Default value"
	dialog --clear --colors --title "$1"  --backtitle "FSarchiver-Backup" --inputbox "$2" "$3" "$4" "$5" 2>&1 >/dev/tty
}

#####################################################################
# FSARCHIVER MOUNT POINT CLEANUP FUNCTIONS
#####################################################################

# Function to find all fsarchiver mount points
function find_fsarchiver_mounts() {
	# Find all mount points under /tmp/fsa/ (with -r for raw output without tree formatting)
	findmnt -n -r -o TARGET | grep "^/tmp/" | grep "^/fsa/" 2>/dev/null | sort -r || true
}

# Function to cleanly unmount fsarchiver mount points
function cleanup_fsarchiver_mounts() {
	local force_cleanup="${1:-false}"

	echo -e "${BLUE}Searching for fsarchiver mount points...${NC}"

	local temp_mounts
	temp_mounts=$(find_fsarchiver_mounts)

	if [[ -z "$temp_mounts" ]]; then
		echo -e "${GREEN}✓ No fsarchiver mount points found${NC}"
		return 0
	fi

	echo -e "${YELLOW}Found fsarchiver mount points:${NC}"
	echo "$temp_mounts" | while read -r mount; do
		if [[ -n "$mount" ]]; then
			echo -e "${YELLOW}  - $mount${NC}"
		fi
	done

	if [[ "$force_cleanup" == "true" ]]; then
		echo -e "${BLUE}Automatic cleanup of mount points...${NC}"
		local cleanup_success=true
		
		# Unmount mount points in reverse order (deepest first)
		while IFS= read -r mount; do
			if [[ -n "$mount" ]]; then
				echo -e "${YELLOW}Unmounting: $mount${NC}"
				
				# Try normal umount
				if umount "$mount" 2>/dev/null; then
					echo -e "${GREEN}  ✓ Successfully unmounted${NC}"
				else
					# On failure: try lazy umount
					echo -e "${YELLOW}  - Normal umount failed, trying lazy umount...${NC}"
					if umount -l "$mount" 2>/dev/null; then
						echo -e "${GREEN}  ✓ Lazy umount successful${NC}"
					else
						# On further failure: force umount
						echo -e "${YELLOW}  - Lazy umount failed, trying force umount...${NC}"
						if umount -f "$mount" 2>/dev/null; then
							echo -e "${GREEN}  ✓ Force umount successful${NC}"
						else
							echo -e "${RED}  ✗ All umount attempts failed for: $mount${NC}"
							cleanup_success=false
						fi
					fi
				fi
			fi
		done <<< "$temp_mounts"
		
		# Check if all mount points were removed
		sleep 1
		local remaining_mounts
		remaining_mounts=$(find_fsarchiver_mounts)
		
		if [[ -z "$remaining_mounts" ]]; then
			echo -e "${GREEN}✓ All fsarchiver mount points successfully removed${NC}"
			
			# Try to remove empty /tmp/fsa directories
			if [[ -d "/tmp/fsa" ]]; then
				echo -e "${BLUE}Cleaning up empty /tmp/fsa directories...${NC}"
				find /tmp/fsa -type d -empty -delete 2>/dev/null || true
				if [[ ! -d "/tmp/fsa" || -z "$(ls -A /tmp/fsa 2>/dev/null)" ]]; then
					rmdir /tmp/fsa 2>/dev/null || true
					echo -e "${GREEN}✓ /tmp/fsa directory cleaned up${NC}"
				fi
			fi
			
			return 0
		else
			echo -e "${RED}✗ Some mount points could not be removed:${NC}"
			echo "$remaining_mounts" | while read -r mount; do
				if [[ -n "$mount" ]]; then
					echo -e "${RED}  - $mount${NC}"
				fi
			done
			return 1
		fi
	else
		echo -e "${YELLOW}Automatic cleanup not activated.${NC}"
		echo -e "${YELLOW}For manual cleanup, run:${NC}"
		echo -e "${YELLOW}sudo umount /tmp/fsa/*/media/* 2>/dev/null || true${NC}"
		echo -e "${YELLOW}sudo umount /tmp/fsa/* 2>/dev/null || true${NC}"
		return 1
	fi
}

# Function to create timestamped backup filenames
function create_timestamped_filename() {
	local base_name="$1"
	local timestamp=$(date +"%Y%m%d-%H%M%S")
	echo "${base_name}-${timestamp}.fsa"
}

# Function to find all versions of a backup file
function find_backup_versions() {
	local backup_drive="$1"
	local base_name="$2"

	# Search for files with pattern: base_name-YYYYMMDD-HHMMSS.fsa
	find "$backup_drive" -maxdepth 1 -name "${base_name}-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].fsa" -type f 2>/dev/null | sort -r
}

# Function to find the latest version of a backup file
function find_latest_backup_version() {
	local backup_drive="$1"
	local base_name="$2"
	find_backup_versions "$backup_drive" "$base_name" | head -n1
}

# Function to clean up old backup versions
function cleanup_old_backups() {
	local backup_drive="$1"
	local base_name="$2"
	local keep_versions="$3"

	echo -e "${BLUE}Cleaning up old backup versions for $base_name (keeping $keep_versions versions)...${NC}"

	local versions
	versions=$(find_backup_versions "$backup_drive" "$base_name")

	if [[ -z "$versions" ]]; then
		echo -e "${YELLOW}No existing backup versions found for $base_name${NC}"
		return 0
	fi

	local version_count
	version_count=$(echo "$versions" | wc -l)

	if [[ $version_count -le $keep_versions ]]; then
		echo -e "${GREEN}✓ All $version_count versions will be kept${NC}"
		return 0
	fi

	local versions_to_delete
	versions_to_delete=$(echo "$versions" | tail -n +$((keep_versions + 1)))

	echo -e "${YELLOW}Deleting $(echo "$versions_to_delete" | wc -l) old versions:${NC}"

	while IFS= read -r old_version; do
		if [[ -n "$old_version" ]]; then
			echo -e "${YELLOW}  - Deleting: $(basename "$old_version")${NC}"
			rm -f "$old_version"
			if [[ $? -eq 0 ]]; then
				echo -e "${GREEN}    ✓ Successfully deleted${NC}"
			else
				echo -e "${RED}    ✗ Error deleting${NC}"
				ERROR=1
				ERROR_MSG+="Error deleting old backup version: $old_version\n"
			fi
		fi
	done <<< "$versions_to_delete"
}

function show_available_drives() {
	echo -e "${YELLOW}Available drives for backup configuration:${NC}"
	echo -e "${BLUE}Use the following command to display all local drives:${NC}"
	echo "lsblk -o NAME,UUID,LABEL,SIZE,VENDOR,MODEL,MOUNTPOINT"
	echo ""
	echo -e "${BLUE}Use the following command to display all network drives:${NC}"
	echo "findmnt -t nfs,nfs4,cifs -o TARGET,SOURCE,FSTYPE,OPTIONS"
	echo ""
	echo -e "${BLUE}Formatted output of available local drives:${NC}"

	# Header
	printf "%-36s | %-12s | %-8s | %-8s | %-12s | %-20s | %s\n" "UUID" "LABEL" "NAME" "SIZE GB" "VENDOR" "MODEL" "MOUNTPOINT"
	printf "%s\n" "$(printf '=%.0s' {1..120})"

	# List drives with formatted output
	while IFS= read -r line; do
		if [[ $line =~ ^[├└│]?─?([a-zA-Z0-9]+)[[:space:]]+([a-f0-9-]*)[[:space:]]*([^[:space:]]*)[[:space:]]*([0-9.,]+[KMGT]?)[[:space:]]*([^[:space:]]*)[[:space:]]*([^[:space:]]*)[[:space:]]*(.*)$ ]]; then
			name="${BASH_REMATCH[1]}"
			uuid="${BASH_REMATCH[2]}"
			label="${BASH_REMATCH[3]}"
			size="${BASH_REMATCH[4]}"
			vendor="${BASH_REMATCH[5]}"
			model="${BASH_REMATCH[6]}"
			mountpoint="${BASH_REMATCH[7]}"
			
			# Convert size to GB if possible
			if [[ $size =~ ^([0-9.,]+)([KMGT])$ ]]; then
				num="${BASH_REMATCH[1]//,/.}"
				unit="${BASH_REMATCH[2]}"
				case $unit in
					K) size_gb=$(echo "scale=1; $num / 1024 / 1024" | bc -l 2>/dev/null || echo "$size") ;;
					M) size_gb=$(echo "scale=1; $num / 1024" | bc -l 2>/dev/null || echo "$size") ;;
					G) size_gb="$num" ;;
					T) size_gb=$(echo "scale=1; $num * 1024" | bc -l 2>/dev/null || echo "$size") ;;
					*) size_gb="$size" ;;
				esac
			else
				size_gb="$size"
			fi
			
			# Only show lines with UUID (real partitions)
			if [[ -n "$uuid" && "$uuid" != "-" ]]; then
				printf "%-36s | %-12s | %-8s | %-8s | %-12s | %-20s | %s\n" \
					"$uuid" "$label" "$name" "$size_gb" "$vendor" "$model" "$mountpoint"
			fi
		fi
	done < <(lsblk -o NAME,UUID,LABEL,SIZE,VENDOR,MODEL,MOUNTPOINT 2>/dev/null)

	echo ""
	echo -e "${BLUE}Available network drives:${NC}"
	findmnt -t nfs,nfs4,cifs -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || echo "No network drives mounted"
}

# Function to determine device path for a mount point
function get_device_path() {
	local mount_point="$1"

	# Check if findmnt command is available
	if ! command -v findmnt &> /dev/null; then
		echo "Error: findmnt command not found. This script requires findmnt to function properly." >&2
		echo "You can install it with: 'sudo apt update && sudo apt install util-linux'" >&2
		return 1
	fi

	findmnt -no SOURCE "$mount_point"
}

# Function to find backup drive by UUID or network path
function find_backup_drive_by_uuid() {
	local identifier="$1"

	# Check if it's a network path (contains slashes)
	if [[ "$identifier" == *"/"* ]]; then
		# Network drive: search for mount point for the network path
		local mount_point
		mount_point=$(findmnt -n -o TARGET -S "$identifier" 2>/dev/null)
		
		if [[ -n "$mount_point" && -d "$mount_point" ]]; then
			echo "$mount_point"
			return 0
		else
			return 1
		fi
	else
		# Local drive: UUID-based search (original logic)
		local device_path=""
		local mount_points=""
		local best_mount_point=""
	local source_uuid=""

	local backup_drive_path="$(echo -e "${BACKUP_DRIVE_PATH}" | tr -d '[:space:]')"
	local backup_drive_uuid=$(findmnt -n -o UUID "$backup_drive_path" 2>/dev/null)

	for source_uuid in "${SOURCE_UUID[@]}"; do
		#echo $source_uuid;
		if [[ "${source_uuid}" == "${identifier}" ]]; then
			error="source' (UUID: $source_uuid) is on the same drive as backup target '$backup_drive_path'"
			echo -e "${RED}Source '$source' (UUID: $source_uuid) is on the same drive as backup target '$backup_drive_path'${NC}"
			return 1
		fi
	done   
		# Search for device with specified UUID
		device_path=$(blkid -U "$identifier" 2>/dev/null)
		
		if [[ -z "$device_path" ]]; then
			return 1
		fi
		
		# Find all mount points for the device
		mount_points=$(findmnt -n -o TARGET "$device_path" 2>/dev/null | tr ' ' '\n')
		
		if [[ -z "$mount_points" ]]; then
			return 1
		fi
		
		# Select the best mount point (prefer real mount points over temporary ones)
		for mount_point in $mount_points; do
			# Skip fsarchiver temporary mount points
			best_mount_point=$(best_dir "$mount_point")
		done
		
		if [[ -n "$best_mount_point" ]]; then
			echo "$best_mount_point"
			return 0
		else
			return 1
		fi
	fi
}

# Function to find the best available backup drive
function find_best_backup_drive() {
	local available_drives=()
	local best_drive=""
	local oldest_newest_backup=999999999999

	echo -e "${BLUE}Searching for configured backup drives (local and network)...${NC}" >&2

	# Check if UUID array is configured
	if [[ ${#BACKUP_DRIVE_UUIDS[@]} -eq 0 ]]; then
		echo -e "${RED}ERROR: No backup drive UUIDs/network paths configured!${NC}" >&2
		echo -e "${YELLOW}Please add UUIDs or network paths to BACKUP_DRIVE_UUIDS array.${NC}" >&2
		echo "" >&2
		show_available_drives >&2
		return 1
	fi

	# Search through all configured identifiers (UUIDs and network paths)
	for identifier in "${BACKUP_DRIVE_UUIDS[@]}"; do
		if [[ -n "$identifier" && "$identifier" != "#"* ]]; then  # Ignore empty and commented lines
			local mount_path
			mount_path=$(find_backup_drive_by_uuid "$identifier")
			if [[ $? -eq 0 && -n "$mount_path" ]]; then
				available_drives+=("$mount_path")
				if [[ "$identifier" == *"/"* ]]; then
					echo -e "${GREEN}✓ Network backup drive found: $mount_path (Network path: $identifier)${NC}" >&2
				else
					echo -e "${GREEN}✓ Local backup drive found: $mount_path (UUID: $identifier)${NC}" >&2
				fi
			fi
		fi
	done

	# Check if drives were found
	if [[ ${#available_drives[@]} -eq 0 ]]; then
		echo -e "${RED}ERROR: None of the configured backup drives are available!${NC}" >&2
		echo -e "${YELLOW}Configured identifiers:${NC}" >&2
		for identifier in "${BACKUP_DRIVE_UUIDS[@]}"; do
			if [[ -n "$identifier" && "$identifier" != "#"* ]]; then
				if [[ "$identifier" == *"/"* ]]; then
					echo "  - $identifier (Network path)" >&2
				else
					echo "  - $identifier (UUID)" >&2
				fi
			fi
		done
		echo "" >&2
		show_available_drives >&2
		return 1
	fi

	# If only one drive is available, use it
	if [[ ${#available_drives[@]} -eq 1 ]]; then
		printf "%s" "${available_drives[0]}"
		return 0
	fi

	# If multiple drives are available, find the one with the oldest "newest" backup
	echo -e "${YELLOW}Multiple backup drives available. Analyzing backup versions...${NC}" >&2

	for drive in "${available_drives[@]}"; do
		local newest_backup_on_drive=0
		
		echo -e "${BLUE}Analyzing drive: $drive${NC}" >&2
		
		# Check all configured backup types on this drive
		for backup_name in "${!BACKUP_PARAMETERS[@]}"; do
			IFS=':' read -r backup_base_name source <<< "${BACKUP_PARAMETERS[$backup_name]}"
			
			local latest_version
			latest_version=$(find_latest_backup_version "$drive" "$backup_base_name")
			
			if [[ -n "$latest_version" && -f "$latest_version" ]]; then
				local file_time
				file_time=$(stat -c %Y "$latest_version" 2>/dev/null)
				if [[ $? -eq 0 && $file_time -gt $newest_backup_on_drive ]]; then
					newest_backup_on_drive=$file_time
				fi
				echo -e "${GREEN}  ✓ $backup_name: $(basename "$latest_version") ($(date -d @$file_time '+%d.%m.%Y %H:%M:%S' 2>/dev/null))${NC}" >&2
			else
				echo -e "${YELLOW}  - $backup_name: No backups found${NC}" >&2
			fi
		done
		
		# Check if this drive has the oldest "newest" backup
		if [[ $newest_backup_on_drive -lt $oldest_newest_backup ]]; then
			oldest_newest_backup=$newest_backup_on_drive
			best_drive="$drive"
		fi
		
		if [[ $newest_backup_on_drive -eq 0 ]]; then
			echo -e "${YELLOW}  → Drive has no backups (will be preferred)${NC}" >&2
		else
			echo -e "${BLUE}  → Newest backup from: $(date -d @$newest_backup_on_drive '+%d.%m.%Y %H:%M:%S' 2>/dev/null)${NC}" >&2
		fi
	done

	if [[ -n "$best_drive" ]]; then
		if [[ $oldest_newest_backup -eq 0 ]]; then
			echo -e "${GREEN}Using backup drive: $best_drive (no previous backups)${NC}" >&2
		else
			echo -e "${GREEN}Using backup drive: $best_drive (oldest newest backup from $(date -d @$oldest_newest_backup '+%d.%m.%Y %H:%M:%S' 2>/dev/null))${NC}" >&2
		fi
		printf "%s" "$best_drive"
		return 0
	else
		echo -e "${RED}Error selecting backup drive${NC}" >&2
		return 1
	fi
}

# Function to check if backup drive is not the same as source drives
function validate_backup_drive() {
	local backup_drive_path="$(echo -e "${1}" | tr -d '[:space:]')"
	local backup_dir_path="$(echo -e "${2}" | tr -d '[:space:]')"

	echo -e "${BLUE}Validating backup drive...${NC}"

	# Check if path exists and is mounted
	if [[ ! -d "$backup_drive_path" ]]; then
		echo -e "${RED}ERROR: Backup drive path does not exist: $backup_drive_path${NC}"
		return 1
	fi

	# Check if it's a network drive
	local fstype
	fstype=$(findmnt -n -o FSTYPE "$backup_dir_path" 2>/dev/null)

	case "$fstype" in
		"nfs"|"nfs4")
			echo -e "${GREEN}✓ NFS network drive detected${NC}"
			
			# Test access to NFS drive
			if ! timeout 10 ls "$backup_drive_path" >/dev/null 2>&1; then
				echo -e "${RED}ERROR: NFS drive not accessible or timeout${NC}"
				return 1
			fi
			
			# Test write permission
			local test_file="$backup_drive_path/.backup-test-$$"
			if timeout 10 touch "$test_file" 2>/dev/null; then
				rm -f "$test_file" 2>/dev/null
				echo -e "${GREEN}✓ NFS drive is writable${NC}"
			else
				echo -e "${RED}ERROR: No write permission on NFS drive${NC}"
				return 1
			fi
			
			echo -e "${GREEN}✓ NFS backup drive validation successful${NC}"
			return 0
			;;
		"cifs")
			echo -e "${GREEN}✓ CIFS/SMB network drive detected${NC}"
			
			# Test access to CIFS drive
			if ! timeout 10 ls "$backup_drive_path" >/dev/null 2>&1; then
				echo -e "${RED}ERROR: CIFS drive not accessible or timeout${NC}"
				return 1
			fi
			
			# Test write permission
			local test_file="$backup_drive_path/.backup-test-$$"
			if timeout 10 touch "$test_file" 2>/dev/null; then
				rm -f "$test_file" 2>/dev/null
				echo -e "${GREEN}✓ CIFS drive is writable${NC}"
			else
				echo -e "${RED}ERROR: No write permission on CIFS drive${NC}"
				return 1
			fi
			
			echo -e "${GREEN}✓ CIFS backup drive validation successful${NC}"
			return 0
			;;
		*)
			# Local drive - original validation
			echo -e "${GREEN}✓ Local backup drive detected${NC}"
			
			# Determine UUID of backup drive
			local backup_drive_uuid
			backup_drive_uuid=$(findmnt -n -o UUID "$backup_drive_path" 2>/dev/null)
			
			if [[ -z "$backup_drive_uuid" ]]; then
				echo -e "${RED}ERROR: Could not determine UUID of backup drive: $backup_drive_path${NC}"
				echo -e "${YELLOW}Trying alternative methods...${NC}"
				
				# Alternative: determine UUID via mounted device
				local device_path
				device_path=$(findmnt -n -o SOURCE "$backup_drive_path" 2>/dev/null)
				if [[ -n "$device_path" ]]; then
					backup_drive_uuid=$(blkid -s UUID -o value "$device_path" 2>/dev/null)
				fi
				
				if [[ -z "$backup_drive_uuid" ]]; then
					echo -e "${RED}ERROR: UUID could not be determined even with alternative methods${NC}"
					echo -e "${YELLOW}Backup drive path: $backup_drive_path${NC}"
					echo -e "${YELLOW}Device path: ${device_path:-'not found'}${NC}"
					return 1
				fi
			fi
			
			echo -e "${GREEN}✓ Backup drive UUID: $backup_drive_uuid${NC}"
			printf '%s\n' "${BACKUP_PARAMETERS[@]}"
			# Check if any of the sources is on the same drive
			for name in "${!BACKUP_PARAMETERS[@]}"; do
				IFS=':' read -r backup_file source <<< "${BACKUP_PARAMETERS[$name]}"
				
				if [[ $source != /dev/* ]]; then
					local source_uuid
					source_uuid=$(findmnt -n -o UUID "$source" 2>/dev/null)
					
					if [[ -n "$source_uuid" && "$source_uuid" == "$backup_drive_uuid" ]]; then
						echo -e "${RED}ERROR: Backup drive is the same as source drive!${NC}"
						echo -e "${RED}Source '$source' (UUID: $source_uuid) is on the same drive as backup target '$backup_drive_path'${NC}"
						echo -e "${YELLOW}You cannot backup to the same drive you're backing up from!${NC}"
						echo ""
						show_available_drives
						return 1
					fi
				fi
				if [[ ! -z "$backup_dir_path" ]]; then
					# Test access to local drive
					if ! timeout 10 ls "$backup_dir_path" >/dev/null 2>&1; then
						echo -e "${RED}ERROR: Local backup drectory is not accessible or not mounted${NC}"
						return 1
					fi
					# Test write permission
					local test_file="$backup_dir_path/.backup-test-$$"
					if timeout 10 touch "$test_file" 2>/dev/null; then
						rm -f "$test_file" 2>/dev/null
						echo -e "${GREEN}✓ Local backup drectory is writable${NC}"
					else
						echo -e "${RED}ERROR: No write permission on local backup drectory${NC}"
						return 1
					fi
				fi	
			done
			# read -p "Press enter to continue"
			echo -e "${GREEN}✓ Local backup drive validation successful${NC}"
			return 0
			;;
	esac
}

# Function to show critical error
function log_critical_error() {
	local error_message="$1"
	local runtime_min="${2:-0}"
	local runtime_sec="${3:-0}"

	msg_body="${MSG_BODY_ERROR}"
	msg_body="${msg_body//\{BACKUP_DATE\}/${BACKUP_START_DATE:-$(date +%d.%B.%Y,%T)}}"
	msg_body="${msg_body//\{RUNTIME_MIN\}/$runtime_min}"
	msg_body="${msg_body//\{RUNTIME_SEC\}/$runtime_sec}"
	msg_body="${msg_body//\{ERROR_DETAILS\}/$error_message}"

	showError "$msg_body" 10 50
}

	#####################################################################
	# BACKUP FUNCTIONS
	#####################################################################

# Main function for performing a backup
function do_backup() {
	local backup_file="$1"
	local device="$2"
	local exclusions=()
	if  [[ "$backup_file" == *"backup-efi"* ]]; then
		exclusions=()
	else
		exclusions=("${EXCLUDE_STATEMENTS[@]}")
	fi
	# Set current backup file for signal handler
	CURRENT_BACKUP_FILE="$backup_file"
	echo -e "${BLUE}Backing up device: $device${NC}" | tee -a $BACKUP_LOG
	ls -l "$device" >> $BACKUP_LOG 2>&1
	lsblk "$device" >> $BACKUP_LOG 2>&1
	COMPRESSION_VALUE=""
	if [[ "$ZSTD_COMPRESSION_VALUE" > "0" ]]; then
		COMPRESSION_VALUE="-Z"$ZSTD_COMPRESSION_VALUE
	fi
	
	# fsarchiver command depending on encryption configuration
	if [[ "$USE_ENCRYPTION" == true ]]; then
			ERROR_MSG=$({ fsarchiver "${exclusions[@]}" -o -v -A -j$(nproc) ${COMPRESSION_VALUE} -c "${FSPASS}" savefs "$backup_file" "$device"; } 2>&1 | tee -a $BACKUP_LOG )
			#fsarchiver "${EXCLUDE_STATEMENTS[@]}" -o -v -d -A -j$(nproc) -Z$ZSTD_COMPRESSION_VALUE -c "${FSPASS}" savefs "$backup_file" "$device" 2>&1 | tee -a $BACKUP_LOG &
	else
			ERROR_MSG=$({ fsarchiver "${exclusions[@]}" -o -v -A -j$(nproc) ${COMPRESSION_VALUE} savefs "$backup_file" "$device"; } 2>&1 | tee -a $BACKUP_LOG )
			#fsarchiver "${EXCLUDE_STATEMENTS[@]}" -o -v -d -A -j$(nproc) -Z$ZSTD_COMPRESSION_VALUE savefs "$backup_file" "$device" 2>&1 | tee -a $BACKUP_LOG &
   	fi

	local fsarchiver_exit_code=$?
	# Store PID of fsarchiver process for signal handler
	#CURRENT_FSARCHIVER_PID=$!
	
	# Wait for fsarchiver process
	#wait $CURRENT_FSARCHIVER_PID
	#local fsarchiver_exit_code=$?
	
	# Reset fsarchiver PID (finished)
	CURRENT_FSARCHIVER_PID=""
	
	# Check if script was interrupted
	if [[ "$SCRIPT_INTERRUPTED" == true ]]; then
		echo -e "${YELLOW}Backup was interrupted while processing $device${NC}"
		return 1
	fi

	# Check fsarchiver exit code
	if [[ $fsarchiver_exit_code -ne 0 ]]; then
		echo -e "${RED}fsarchiver exited with code: $fsarchiver_exit_code${NC}"
		ERROR=1
		ERROR_MSG+="fsarchiver exit code $fsarchiver_exit_code for device $device\n"
	fi

	check_backup_errors "$device" "$backup_file"
	
	# After backup: check for new fsarchiver mount points and clean them up
	echo -e "${BLUE}Checking for fsarchiver mount points after backup...${NC}"
	local post_backup_mounts
	post_backup_mounts=$(find_fsarchiver_mounts)

	if [[ -n "$post_backup_mounts" ]]; then
		echo -e "${YELLOW}New fsarchiver mount points detected after backup - cleaning up...${NC}"
		if ! cleanup_fsarchiver_mounts true; then
			echo -e "${YELLOW}Warning: Some mount points could not be automatically removed${NC}"
			ERROR_MSG+="Warning: fsarchiver mount points after backup of $device could not be completely removed\n"
		fi
	else
		echo -e "${GREEN}✓ No fsarchiver mount points present after backup${NC}"
	fi

	# Reset backup file (finished)
	CURRENT_BACKUP_FILE=""

	return $fsarchiver_exit_code
}

# Function to check backup errors
function check_backup_errors() {
	local BKP_SOURCE="$1"
	local BKP_FILE="$2"

	# Ensure BACKUP_LOG variable is available
	if [ -z "$BACKUP_LOG" ]; then
		ERROR_MSG+="[ $BACKUP_LOG ] is empty after backup of [ $BKP_SOURCE ]. Something is wrong. Please check the logs and the entire backup process."
		return 1
	fi

	local LOG_OUTPUT
	LOG_OUTPUT=$(tail -n 5 "$BACKUP_LOG" | grep -Ei "(files with errors)|\b(cannot|warning|error|errno|Errors detected)\b")

	# Check for errors in log output
	local has_errors=false
	if  [[ ${LOG_OUTPUT,,} =~ (^|[[:space:]])("cannot"|"warning"|"error"|"errno"|"errors detected")([[:space:]]|$) ]]; then
		has_errors=true
		ERROR=1
		ERROR_MSG+="Errors detected in backup of [ $BKP_SOURCE ]:\n$LOG_OUTPUT\n"
	elif [[ $LOG_OUTPUT =~ regfiles=([0-9]+),\ directories=([0-9]+),\ symlinks=([0-9]+),\ hardlinks=([0-9]+),\ specials=([0-9]+) ]]; then
		for val in "${BASH_REMATCH[@]:1}"; do
			if [ "$val" -ne 0 ]; then
				has_errors=true
				ERROR=1
				ERROR_MSG+="Errors detected in backup of [ $BKP_SOURCE ]:\n$LOG_OUTPUT\n"
				break;
			fi
		done
	fi

	# Check if backup file was actually created
	if [[ ! -f "$BKP_FILE" ]]; then
		has_errors=true
		ERROR=1
		ERROR_MSG+="Backup file was not created: $BKP_FILE\n"
		echo -e "${RED}✗ Backup file not found: $BKP_FILE${NC}"
	else
		# Check size of backup file (at least 1 MB)
		local file_size
		file_size=$(stat -c%s "$BKP_FILE" 2>/dev/null)
		if [[ $? -eq 0 ]]; then
		if [[ ${BKP_FILE} != "*efi*" ]]; then
			SIZE=5;
		else
			SIZE=1048576;
		fi
		if [[ $file_size -lt $SIZE ]]; then  # 1 MB = 1048576 Bytes
			has_errors=true
			ERROR=1
			ERROR_MSG+="Backup file is too small ($(( file_size / 1024 )) KB): $BKP_FILE\n"
			echo -e "${RED}✗ Backup file too small: $BKP_FILE ($(( file_size / 1024 )) KB)${NC}"
		else
			echo -e "${GREEN}✓ Backup file created: $(basename "$BKP_FILE") ($(( file_size / 1024 / 1024 )) MB)${NC}"
		fi
		else
			has_errors=true
			ERROR=1
			ERROR_MSG+="Could not determine backup file size: $BKP_FILE\n"
			echo -e "${RED}✗ Could not determine backup file size: $BKP_FILE${NC}"
		fi
	fi

	# Output overall result
	if [[ "$has_errors" == true ]]; then
		echo -e "${RED}✗ Backup of $BKP_SOURCE failed${NC}"
	else
		echo -e "${GREEN}✓ Backup of $BKP_SOURCE successful${NC}"
	fi
}

function MainBackup() {
	#####################################################################
	#  FSARCHIVER BACKUP PART STARTS HERE
	#####################################################################
	#
	#####################################################################
	# FSARCHIVER DEFINE USEFUL VARIABLES
	#####################################################################
	# ZSTD compression level (0-22)
	# 0 = no compression, 1 = fastest/worst compression, 22 = slowest/best compression
	# Default is 3. Values above 19 are considered "ultra" settings and should be used carefully.
	local efisys=$1
	# Backup Parameters Configuration
	# Format: BACKUP_PARAMETERS["Backup Name"]="Backup-File-Base-Name:Mount-Point or Device-Path for Backup"
	# IMPORTANT: The backup file name is only the base name. The script automatically adds
	# a timestamp for versioning (e.g. backup-efi-20250625-123456.fsa)

	declare -A BACKUP_PARAMETERS
	if [[ "$efisys" == *"EFI"* ]]; then
		BACKUP_PARAMETERS["EFI"]="backup-efi:/boot/efi"
	fi
	if [[ "$efisys" == *"SYS"* ]]; then
		BACKUP_PARAMETERS["System"]="backup-system:/"
	fi
	# BACKUP_PARAMETERS["DATA"]="backup-data:/media/username/DATA"  # Example - commented out
	set DEVICE, UUID, BK_FILE, BACKUP_DIR_PATH, BACKUP_DRIVE_PATH, CHOICE
	ARCH_DIR="FSarchives" # Default directory where backup are stored
	while true;
	do
		ZSTD_COMPRESSION_VALUE=$(showInput "Compression level" "Select compression level (0-22):\n   ${bold}0${nc} = no compression\n   ${bold}1${nc} = fastest/worst compression,\n  ${bold}22${nc} = slowest/best compression. Default is 3.\nValues above 19 are considered -ultra- settings\nand should be used carefully.\n" "15" "60" 11)
		exitstatus=$?
		if [ $exitstatus = 0 ]; then
			echo "User selected Ok and entered " $ZSTD_COMPRESSION_VALUE
			if [ "${ZSTD_COMPRESSION_VALUE}" -lt 0 ] ||  [ "${ZSTD_COMPRESSION_VALUE}" -gt 22 ]; then
				showYN "Compression value out of the expected range\nWould you retry?" 20 70
				if [ "$?" == "1" ]; then
					cleanup_on_interrupt
					return 1;
				fi
			else
				break;
			fi
		else
			echo "User selected Cancel."
			cleanup_on_interrupt
			return 1;
		fi
	done

	# Versioning Configuration
	# Number of backup versions to keep per backup type
	# The script creates timestamped backups (e.g. backup-efi-20250625-123456.fsa)
	# and keeps the latest X versions. Older versions are automatically deleted.
	# 
	# BACKUP DRIVE SELECTION WITH MULTIPLE AVAILABLE DRIVES:
	# The script compares the newest backup of each type on all available
	# drives (local and network) and selects the drive whose newest backup 
	# is oldest. This ensures that the drive that most urgently needs an update is used.
	#VERSIONS_TO_KEEP=1
	while true;
	do
		VERSIONS_TO_KEEP=$(showInput "Select number of version to keep (1-5)" "The script creates timestamped backups (e.g. backup-efi-20250625-123456.fsa)\n and keeps the latest X versions.\nOlder versions are automatically deleted." "13" "60" "3")
		exitstatus=$?
		if [ $exitstatus = 0 ]; then
			echo "User selected Ok and entered " $ZSTD_COMPRESSION_VALUE
			if [ "${VERSIONS_TO_KEEP}" -lt 1 ] ||  [ "${VERSIONS_TO_KEEP}" -gt 5 ]; then
				showYN "The entered number of versions is not valid\nWould you retry?" 20 70
				if [ "$?" == "1" ]; then
					cleanup_on_interrupt
					return 1;
				fi
			else
				break;
			fi
		else
			echo "User selected Cancel."
			return  1;
		fi
	done

	#####################################################################
	# DEFINE THE PARTITIONS TO BE BACKED-UP
	#####################################################################
	declare -a SOURCE_UUID=()
	if [[ "$efisys" == *"EFI"* ]]; then
		while true;
			do
			select_device "\n${bold}Please select the ${red}EFI${nc}${bold} boot Partition${nc}" "part" "-i" "vfat"
			if [[ $? -ne 0 || ! "${DEVICE}" ]]; then
				showYN "Nothing was selected\nWould you retry?" 10 40
				if [[ $? -ne 0 ]]; then
					cleanup_on_interrupt
					return 1;
				fi
			else
				echo "${DEVICE}"
				echo "${UUID}"
				SOURCE_UUID=("${UUID}")
				BACKUP_PARAMETERS["EFI"]="backup-efi:/dev/${DEVICE}"
				break;
			fi
		done
	fi
	if [[ "$efisys" == *"SYS"* ]]; then
		while true;
			do
			select_device "\n${bold}Please select the ${red}SYSTEM${nc}${bold} Partition to be archived${nc}" "part" "-v" "fat"
			if [[ $? -ne 0 || ! "${DEVICE}" ]]; then
				showYN "Nothing was selected\nWould you retry?" 10 40
				if [[ $? -ne 0 ]]; then
					cleanup_on_interrupt
					return 1;
				fi
			else
				echo "${DEVICE}"
				echo "${UUID}"
				SOURCE_UUID+=("${UUID}")
				BACKUP_PARAMETERS["System"]="backup-system:/dev/${DEVICE}"
				break;
			fi
		done
	fi
	# printf '%s\n' "${SOURCE_UUID[@]}" 
	# read -p "Press enter to continue"
	# Process backup parameters and update paths
	echo -e "${BLUE}Configuring backup parameters...${NC}"
	for name in "${!BACKUP_PARAMETERS[@]}"; do
		IFS=':' read -r backup_base_name source <<< "${BACKUP_PARAMETERS[$name]}"
		# Create timestamped backup filename
		timestamped_filename=$(create_timestamped_filename "$backup_base_name")
		full_backup_path="$BACKUP_DIR_PATH/$timestamped_filename" # not used
		full_filename="/$timestamped_filename"
		if [[ $source == /dev/* ]]; then
			device=$source
		else
			if [ ! -d "$source" ]; then
				ERROR=1
				ERROR_MSG+="Mount point $source does not exist or is not accessible\n"
				echo -e "${YELLOW}Warning: Mount point $source does not exist or is not accessible${NC}" >&2
				continue
			fi
			device=$(get_device_path "$source")
			if [ -z "$device" ]; then
				ERROR=1
				ERROR_MSG+="Could not determine device path for $source\n"
				echo -e "${YELLOW}Warning: Could not determine device path for $source${NC}" >&2
				continue
			fi
		fi

		# Format for backup parameters: "full_path:device:base_name"
		BACKUP_PARAMETERS[$name]="$full_filename:$device:$backup_base_name"
		echo -e "${GREEN}Configured backup: $name${NC}"
		echo -e "${GREEN}  - File: $timestamped_filename${NC}"
		echo -e "${GREEN}  - Device: $device${NC}"
		echo -e "${GREEN}  - Base name: $backup_base_name${NC}"
	done
	# Check if configuration errors occurred
	if [ "$ERROR" -eq 1 ]; then
		echo -e "${RED}Configuration errors occurred:${NC}" >&2
		echo -e "$ERROR_MSG" >&2
		log_critical_error "$ERROR_MSG" 0 0
		exit 1
	fi

	#####################################################################
	# SELECT THE DRIVE and DIRECTORY WHERE THE BACKUP SHOULD BE STORED
	#####################################################################
	while true;
	do
		select_device "\n${bold}Please select the ${red}Drive ${nc}${bold} where to ${red}store Backup(s)${nc}" "part" "-v" "fat\|${DEVICE}"  "no_unmount"
		if [[ $? -ne 0 || ! "${DEVICE}" ]]; then
			showYN "Nothing was selected\nWould you retry?" 10 40
			if [[ $? -ne 0 ]]; then
				#cleanup_on_interrupt
				return 1;
			fi
		fi

		BACKUP_DRIVE_UUIDS=(
		${UUID}
		)
		if ! check_uuid_mounted ${UUID}; then
			showYN "Device ${DEVICE} appears not mounted.\nYou might want to mount it outside this program or either\n\ndo you want I mount it for you on /tmp/fsa?" 10 40
			if [[ $? -eq 1 ]]; then
				return 1
			fi
			if [ ! -d /tmp/fsa ]; then
				mkdir /tmp/fsa
			fi
			mount /dev/${DEVICE} /tmp/fsa
			sleep 3
		fi
		BACKUP_DRIVE_PATH=$(find_best_backup_drive)
		if [[ $? -ne 0 || -z "$BACKUP_DRIVE_PATH" ]]; then
			ERROR=1
			ERROR_MSG+="Possible reasons:\n- No suitable backup drive (local or network) found.\n- The drive is not mounted.\n- The selected drive is the same as the one to be archived."
			echo -e "${RED}Critical error: No backup drive available. Script will exit.${NC}"
			showError "${ERROR_MSG}" 18 60
			return 1
			# Show error message
			#log_critical_error "$ERROR_MSG" 0 0
			#exit 1
		else
			echo -e "${GREEN}Backup drive successfully found: $BACKUP_DRIVE_PATH${NC}"
			select_bkup_d-f $(best_dir ${UUID}) "d"
			if [[ $? -ne 0 ]]; then
				return 1
			fi
			BACKUP_DRIVE=$(find_best_backup_drive)
			BACKUP_DIR_PATH=${CHOICE}
			#echo `select_bkup_d-f ${UUID}`
			echo ""
			echo "backup: $BACKUP_DIR_PATH"

			# Validate backup drive (not the same as source drives for local drives)

			if ! validate_backup_drive "$BACKUP_DRIVE_PATH" "$BACKUP_DIR_PATH"; then
				ERROR=1
				ERROR_MSG+="Backup drive validation failed.\n"
				echo -e "${RED}Critical error: Backup drive validation failed. Script will exit.${NC}"
				showError "${ERROR_MSG}" 18 60
				if [[ $? -ne 0 ]]; then
					cleanup_on_interrupt
					exit 1;
				fi
			else
				break;
			fi
		fi
	done
	BACKUP_DIR_PATH=$(echo $BACKUP_DIR_PATH | sed 's/\(^.*\/\).*$ARCH_DIR\//\1/g') # remove FSarchives from path
	#
	DIR_DATE=`date '+%Y-%m-%d-%H%M'`
	#BACKUP_DIR_PATH=$BACKUP_DIR_PATH/$DIR_DATE"-$ARCH_DIR"
	BACKUP_DIR_PATH=$BACKUP_DIR_PATH/$ARCH_DIR
	if [ ! -d $BACKUP_DIR_PATH ]; then mkdir -p $BACKUP_DIR_PATH; fi

	#####################################################################
	# PASSWORD CONFIGURATION (OPTIONAL)
	#####################################################################

	# Load archive password from external file (if configured)
	FSPASS=""
	USE_ENCRYPTION=false

	if [[ -n "${PASSWORD_FILE:-}" ]]; then
		echo -e "${BLUE}Checking encryption configuration...${NC}"
		
		if [ ! -f "$PASSWORD_FILE" ]; then
			echo -e "${RED}Error: Password file $PASSWORD_FILE not found.${NC}" >&2
			ERROR=1
			ERROR_MSG+="Password file $PASSWORD_FILE not found.\n"
			log_critical_error "$ERROR_MSG" 0 0
			exit 1
		fi

		if [ ! -r "$PASSWORD_FILE" ]; then
			echo -e "${RED}Error: Password file $PASSWORD_FILE is not readable.${NC}" >&2
			ERROR=1
			ERROR_MSG+="Password file $PASSWORD_FILE is not readable.\n"
			log_critical_error "$ERROR_MSG" 0 0
			exit 1
		fi

		FSPASS=$(cat "$PASSWORD_FILE" | tr -d '\n')

		if [ -z "$FSPASS" ]; then
			echo -e "${RED}Error: Password file $PASSWORD_FILE is empty.${NC}" >&2
			ERROR=1
			ERROR_MSG+="Password file $PASSWORD_FILE is empty.\n"
			log_critical_error "$ERROR_MSG" 0 0
			exit 1
		fi

		export FSPASS
		USE_ENCRYPTION=true
		echo -e "${GREEN}✓ Encryption enabled${NC}"
	else
		defPsw
		if [ "$?" == "0" ]; then
			export FSPASS
			USE_ENCRYPTION=true
			echo -e "${GREEN}✓ Encryption enabled${NC}"
		fi
		echo -e "${YELLOW}ℹ Encryption disabled (PASSWORD_FILE not configured)${NC}"
	fi

	#####################################################################
	# PERFORM BACKUP
	#####################################################################

	# Generate exclusion statements for fsarchiver as array
	EXCLUDE_STATEMENTS=()
	for path in "${EXCLUDE_PATHS[@]}"; do
	  EXCLUDE_STATEMENTS+=("-e=$path")
	done

	# Record backup start time
	TIME_START=$(date +"%s")
	BACKUP_START_DATE=$(date +%d.%B.%Y,%T)

	echo -e "${GREEN}========================================${NC}"
	echo -e "${GREEN}BACKUP PROCESS STARTED${NC}"
	echo -e "${GREEN}Start: $BACKUP_START_DATE${NC}"
	echo -e "${GREEN}========================================${NC}"

	# Initialize log file
	if [[ -e $BACKUP_LOG ]]; then
		rm -f $BACKUP_LOG
	fi
	touch $BACKUP_LOG

	echo "Backup started: $BACKUP_START_DATE" >> $BACKUP_LOG
	CONDITIONS="\nBackups will be "
	if  [[ "$USE_ENCRYPTION" == true ]]; then 
		CONDITIONS=$CONDITIONS"${bold}protected by password${green} ($FSPASS)${nc} and ";
	else
		CONDITIONS=$CONDITIONS"${bold}without any password protection${nc} and \n";
	fi
	CONDITIONS=$CONDITIONS"stored on device: "
	CONDITIONS=$CONDITIONS"${bold}"$(echo `df -hB1 --output=source ${BACKUP_DIR_PATH} | awk 'NR>1'`)"${nc}\n"
	CONDITIONS=$CONDITIONS"On the path: ${bold}${BACKUP_DIR_PATH}${nc}\n"
	for KEY in $(echo "${!BACKUP_PARAMETERS[@]}" | tr ' ' '\n' | sort -n); do
		IFS=':' read -r BKP_IMAGE_FILE SOURCE_DEVICE BKP_BASE_NAME <<< "${BACKUP_PARAMETERS[$KEY]}"
		CONDITIONS=$CONDITIONS"\nBackup: ${bold}$KEY${nc}\nDevice: ${bold}${SOURCE_DEVICE}${nc}\nImage: ${bold}${BKP_IMAGE_FILE}${nc}\n"
	done
	CONDITIONS=$CONDITIONS"\n${bold}      Do you confirm the above parameters?${nc}\n"
	showYN "${CONDITIONS}" 20 70
	if [ "$?" == "1" ]; then
		#cleanup_on_interrupt
		#exit 1;
		return 1
	fi
	# printf '%s\n' "${BACKUP_PARAMETERS[@]}"

	# Execute backup jobs by iterating over the associative array

	for KEY in $(echo "${!BACKUP_PARAMETERS[@]}" | tr ' ' '\n' | sort -n); do
		# Check if script was interrupted
		if [[ "$SCRIPT_INTERRUPTED" == true ]]; then
			echo -e "${YELLOW}Script interruption detected. Stopping further backups.${NC}"
			break;
		fi
		# printf '%s\n' "${BACKUP_PARAMETERS[@]}"
		IFS=':' read -r BKP_IMAGE_FILE SOURCE_DEVICE BKP_BASE_NAME <<< "${BACKUP_PARAMETERS[$KEY]}"
		echo -e "${BLUE}Starting backup: $KEY${NC}"
		echo "img: "$BKP_IMAGE_FILE " source: " $SOURCE_DEVICE " baseN: " $BKP_BASE_NAME
		if do_backup "${BACKUP_DIR_PATH}""$BKP_IMAGE_FILE" "$SOURCE_DEVICE"; then
			# After successful backup: clean up old versions (only if not interrupted)
			if [[ "$SCRIPT_INTERRUPTED" == false && $ERROR -eq 0 ]]; then
				cleanup_old_backups "$BACKUP_DIR_PATH" "$BKP_BASE_NAME" "$VERSIONS_TO_KEEP"
			fi
		else
			echo -e "${RED}Backup of $KEY failed or was interrupted${NC}"
			if [[ "$SCRIPT_INTERRUPTED" == true ]]; then
				break;
			fi
		fi
		# At the end copy logfile to the directory where backups are saved
		cp ${BACKUP_LOG} ${BACKUP_DIR_PATH}
	done

	#####################################################################
	# COMPLETION AND LOG NOTIFICATION
	#####################################################################

	# Calculate runtime
	TIME_DIFF=$(($(date +"%s")-${TIME_START}))
	RUNTIME_MINUTES=$((${TIME_DIFF} / 60))
	RUNTIME_SECONDS=$((${TIME_DIFF} % 60))

	echo -e "${GREEN}========================================${NC}"

	# Check if script was interrupted
	if [[ "$SCRIPT_INTERRUPTED" == true ]]; then
		echo -e "${RED}BACKUP WAS INTERRUPTED${NC}"
		echo -e "${RED}Runtime: $RUNTIME_MINUTES minutes and $RUNTIME_SECONDS seconds${NC}"
		echo -e "${RED}========================================${NC}"
		
		# Interruption message
		msg_body="${MSG_BODY_INTERRUPTED}"
		msg_body="${msg_body//\{BACKUP_DATE\}/$BACKUP_START_DATE}"
		msg_body="${msg_body//\{RUNTIME_MIN\}/$RUNTIME_MINUTES}"
		msg_body="${msg_body//\{RUNTIME_SEC\}/$RUNTIME_SECONDS}"
		
		showError "msg_body" 10 50

		echo -e "${YELLOW}Interruption messagge showed${NC}"
		
		exit 130  # Standard exit code for SIGINT
	elif [ "$ERROR" -eq 1 ]; then
		echo -e "${RED}BACKUP COMPLETED WITH ERRORS${NC}"
		echo -e "${GREEN}End: $(date +%d.%B.%Y,%T)${NC}"
		echo -e "${GREEN}Runtime: $RUNTIME_MINUTES minutes and $RUNTIME_SECONDS seconds${NC}"
		echo -e "${GREEN}========================================${NC}"
		
		# Error msg
		msg_body="${MSG_BODY_ERROR}"
		msg_body="${msg_body//\{BACKUP_DATE\}/$BACKUP_START_DATE}"
		msg_body="${msg_body//\{RUNTIME_MIN\}/$RUNTIME_MINUTES}"
		msg_body="${msg_body//\{RUNTIME_SEC\}/$RUNTIME_SECONDS}"
		msg_body="${msg_body//\{ERROR_DETAILS\}/$ERROR_MSG}"
		showError "$msg_body" 10 50

	else
		echo -e "${GREEN}BACKUP COMPLETED SUCCESSFULLY${NC}"
		echo -e "${GREEN}End: $(date +%d.%B.%Y,%T)${NC}"
		echo -e "${GREEN}Runtime: $RUNTIME_MINUTES minutes and $RUNTIME_SECONDS seconds${NC}"
		echo -e "${GREEN}========================================${NC}"

		# Success msg
		msg_body="${MSG_BODY_SUCCESS}"
		msg_body="${msg_body//\{BACKUP_DATE\}/$BACKUP_START_DATE}"
		msg_body="${msg_body//\{RUNTIME_MIN\}/$RUNTIME_MINUTES}"   
		msg_body="${msg_body//\{RUNTIME_SEC\}/$RUNTIME_SECONDS}"
		showMsg "$msg_body" 10 50

	fi

	# Exit script with appropriate exit code
	if [[ "$SCRIPT_INTERRUPTED" == true ]]; then
		exit 130  # Standard exit code for SIGINT
	elif [ "$ERROR" -eq 1 ]; then
		return 1
	else
		return 0
	fi
}


#####################################################################
#  CHECK BACKUP FILE
#####################################################################
#
function CheckBackup() {
	# Added for compatibility with backup function
	ARCH_DIR=".." # Default directory where backup are stored
	###########################
	while true;
		do
		select_device "\nPlease select the file you wish information about" "part" "-v" "fat" "no_unmount"
		if [[ $? -ne 0 || ! "${DEVICE}" ]]; then
			showYN "No file selected\nWould you retry?" 10 40
			if [[ $? -ne 0 ]]; then
				return 1;
			fi
		else
			echo "${DEVICE}"
			echo "${UUID}"
			SOURCE_UUID+=("${UUID}")
			BACKUP_PARAMETERS["System"]="backup-system:/dev/${DEVICE}"
			break;
		fi
	done
	local B_D=$(best_dir ${UUID})
	if [[ $? -ne 0 || ! "$B_D" ]]; then
		return 1;
	fi
	while true;
	do
		fsel="fsa"
		local B_D=$(best_dir ${UUID})
		if [[ $? -ne 0 || ! "$B_D" ]]; then
			return 1;
		fi
		CK_FILE=$(echo `select_bkup_d-f "$B_D" "$fsel"`)
		if [[ $? -ne 0 || ! "$CK_FILE" || "${CK_FILE##*.}" != "$fsel" ]]; then
			showYN "Nothing selected\nWould you retry?" 10 40
			if [[ $? -ne 0 ]]; then
				return 1;
			fi
		else
			break;
		fi
	done
	if [[ $? -ne 0 || ! "${CK_FILE}" ]]; then
		return 1
	fi
	RESULT=$({ fsarchiver archinfo "$CK_FILE"; } 2>&1 | tee -a $BACKUP_LOG )
	if [[ $RESULT == *"provide the password"* ]]; then
		askPass "\nThe file is secured by password.\nPlease provide it." 10 50
		if [[ $? -ne 0 ]]; then return 1; fi
		MSG=$({ fsarchiver archinfo -c "${FSPASS}" "$CK_FILE"; } 2>&1 )
		if [[ $? -ne 0 ]]; then showMsg "\nWrong password, exit now" 6 30; return 1; fi
	else
		MSG=$({ fsarchiver archinfo "$CK_FILE"; } 2>&1 )
		if [[ $? -ne 0 ]]; then showMsg "\nSomething went wrong, exit now" 6 30; return 1; fi
	fi
		echo "$MSG" 2>&1 | tee -a $BACKUP_LOG
		showMsg "$MSG" 30 70
}

#####################################################################
#  PERFORM RESTORE
#####################################################################
#
function MainRestore() {
	# Added for compatibility with backup function
	ARCH_DIR=".." # Default directory where backup are stored
	###########################
	set DEVICE, UUID, BK_FILE
	while true;
		do
		select_device "\nPlease select the file to restore" "part" "-v" "fat"  "no_unmount"
		if [[ $? -ne 0 || ! "${DEVICE}" ]]; then
			showYN "Nothing selected\nWould you retry?" 10 40
			if [[ $? -ne 0 ]]; then
				cleanup_on_interrupt
				exit 1;
			fi
		else
			echo "${DEVICE}"
			echo "${UUID}"
			S_DEVICE="/dev/${DEVICE}"
			S_UUID=("${UUID}") # Source UUID
			BACKUP_PARAMETERS["System"]="backup-system:/dev/${DEVICE}"
			break;
		fi
	done
	if [[ $? -ne 0 ]]; then
		return 1
	fi
	while true;
	do
		fsel="fsa"
		local B_D=$(best_dir ${UUID})
		if [[ $? -ne 0 || ! "$B_D" ]]; then
			return 1;
		fi
		BK_FILE=$(echo `select_bkup_d-f "$B_D" "$fsel"`)
		if [[ $? -ne 0 || ! "$BK_FILE" || "${BK_FILE##*.}" != "$fsel" ]]; then
			showYN "Nothing selected\nWould you retry?" 10 40
			if [[ $? -ne 0 ]]; then
				return 1;
			fi
		else
			break;
		fi
	done
	#F_INFO=$(fsarchiver archinfo "$BK_FILE" 2>&1)
	F_INFO=$({ fsarchiver archinfo "$BK_FILE"; } 2>&1 )
	if [[ $F_INFO == *"provide the password"* ]]; then
		askPass "\nThe file is secured by password.\nPlease provide it." 10 50
		if [[ $? -ne 0 ]]; then return 1; fi
		F_INFO=$({ fsarchiver archinfo -c "${FSPASS}" "$BK_FILE"; } 2>&1 )
		if [[ $? -ne 0 ]]; then showMsg "\nWrong password, exit now" 6 30; return 1; fi
	else
		F_INFO=$({ fsarchiver archinfo "$BK_FILE"; } 2>&1 )
		if [[ $? -ne 0 ]]; then showMsg "\nSomething went wrong, exit now" 6 30; return 1; fi
	fi
	echo "$F_INFO" 2>&1 | tee -a $BACKUP_LOG
	showMsg "$F_INFO" 30 70
	F_INFO=`echo $F_INFO | tr -d '[:cntrl:]'`  # Cleanup because of spurious characters in variable
	echo $F_INFO
	ORG_DEV=$(echo $F_INFO | sed -e 's/.*device:\s*\(\/dev\/[^ ]*\).*/\1/g')
	ORG_FORM=$(echo $F_INFO | sed -e "s/.*system format:\s\+\([a-z|A-Z|0-9]\w\+\).*/\1/g")
	ORG_USIZE=$(echo $F_INFO | sed -e 's/^.*size:.*(\([0-9]\+\).*)/\1/g')
	ORG_UUID=$(echo $F_INFO | sed -e 's/.*uuid:\s*\([a-zA-Z0-9\-]\+\).*/\1/g')
	ORG_LABEL=$(echo $F_INFO | sed -e 's/.*label:\s\([<>a-z A-Z]\+\)\(.*Minimum.*\)/\1/g' | tr -d ' ')
	if [ "${ORG_LABEL}" = "<none>" ]; then ORG_LABEL=""; fi
#
	echo "Original device: "$ORG_DEV
	echo "Bkup fIle: "$BK_FILE
	echo "Original format: "$ORG_FORM
	echo "Original size: "$ORG_USIZE
	echo "Original label: "$ORG_LABEL
#
	while true;
		do
		select_device "\nPlease select the disk/partition where to restore to" "disk" "-v" "fat"
		if [[ $? -ne 0 || ! "${DEVICE}" ]]; then
			showYN "No partition selected\nWould you retry?" 10 40
			if [[ $? -ne 0 ]]; then
				return 1;
			fi
		else
			echo "${DEVICE}"
			echo "${UUID}"
			D_DISK="${DEVICE}"
			D_UUID=("${UUID}") # Destination UUID
			RESTORE_PARAMETERS="backup-system:/dev/${DEVICE}"
			break;
		fi
	done
	if [[ ! $(partprobe -d -s /dev/$DEVICE | sed -e 's/^.*partitions\s*//g') ]]; then
		showMsg "The $DEVICE device you selected has no partitions yet.\nPlease run gpart or other useful program to partitioning first.\n\nProgram will exit now." 15 60
		#cleanup_on_interrupt
		#exit 1;
		return 1
	fi
	while true;
		do
		select_device "\nPlease select the partition where to restore" "part" "$DEVICE" ""
		if [[ $? -ne 0 || ! "${DEVICE}" ]]; then
			showYN "No partition selected\nWould you retry?" 10 40
			if [[ $? -ne 0 ]]; then
				return 1;
			fi
		else
			echo "${DEVICE}"
			echo "${UUID}"
			D_DEVICE="/dev/${DEVICE}"
			D_UUID=("${UUID}")
			RESTORE_PARAMETERS="restore-system:/dev/${DEVICE}"
			if [[ "${S_DEVICE: :-1}" == "${D_DEVICE: :-1}" ]]; then
				showError "Source' (UUID: $S_UUID) is on the same drive as restore target '/dev/${D_DISK}'" 10 60
				echo -e "${RED}Source '$source' (UUID: $source_uuid) is on the same drive as backup target '$backup_drive_path'${NC}"
				return 1
			fi
			exit
			break;
		fi
	done
	if check_uuid_mounted ${UUID}; then
		showYN "\n${red}${bold}The selected partition '$DEVICE' is currently mounted!\n\\n
The restore couldn't be done on a mounted partition!${nc}\n\
\n     ${bold}Would you like I unmount '$DEVICE' for you?\n\n
${magenta}You may choose to do it by yourself by saying 'No' but in this \
case the restore process will be interrupted.${nc}" 16 60
		if [[ $? -ne 0 ]]; then
			return 1
		fi
		if umount "/dev/$DEVICE" 2>/dev/null; then
			showInfo "\n${green}${bold}$DEVICE  ✓ Successfully unmounted${nc}" 8 40 3
		else
			 "${yellow} - Umount failed, you have to do by yourself. Now exiting...${nc}" 8 40 10
			return 1
		fi
	fi
	PAR_SIZE=$(lsblk -b --output SIZE -n -d /dev/"${DEVICE}")
#
	#RS_FILE=$(echo `select_bkup_d-f $(best_dir ${UUID}) "fsa"`)
	echo "Original device: "$ORG_DEV
	echo "Bkup fIle: "$BK_FILE
	echo "Original format: "$ORG_FORM
	echo "Original used size: "$ORG_USIZE
	echo "Partition size: "$PAR_SIZE
	echo "Original UUID: "$ORG_UUID
	if [[ $? -ne 0 ]]; then
		return 1
	fi
	if [[ $PAR_SIZE -lt $ORG_USIZE ]]; then
		showError "The selected partition size is lower than the required." 15 50
		return 1
	fi
	REF_SIZE=`echo $(($ORG_USIZE+$ORG_USIZE*10/100))`
	if [[ $REF_SIZE -gt $PAR_SIZE ]]; then
		showYN "\n${red}${bold}The space of the selected partition '$DEVICE' is a smaller than the calculated safe space.${nc}\n\
This may cause problems and system may not work properly.\n\
The required space has been calculated by increasing the original \
used space by 10 percent to guarantee enouth space for the system \
to work.\n\
Available space: ${bold}$((${PAR_SIZE}/1048576)) MB${nc}\n\
Backup partition dimension: ${bold}$((${ORG_USIZE}/1048576)) MB${nc}\n\
Minimum space required: ${bold}$((${REF_SIZE}/1048576)) MB (Backup+10%)${nc}\n\
\n          {red}${bold}Do you want to continue anyway?${nc}" 16 70
		if [[ $? -eq 1 ]]; then
			return 1;
		fi
	fi
	showYN "\nCurrent UUID is: ${bold}$ORG_UUID${nc}\nDo you want to change it with a new one?\n\n${bold}If you choose YES don't forghet to modify it in /etc/fstab.${nc}" 10 60
	if [[ $? -eq 0 ]]; then
		if [[ $ORG_USIZE -le 629145600 || `grep -E "efi|EFI"<<< ${BK_FILE##*/}` ]]; then # if size less or equal 600MB assumed is EFI
			UUID=$(uuidgen | head -c8)
		else
			UUID=$(uuidgen)
		fi
	else
		UUID=$ORG_UUID
	fi
	showYN "\nCurrent file system format is ${bold}$ORG_FORM${nc}\n\nDo you want to change it with a different one?" 10 60
	if [[ $? -eq 0 ]]; then
		arr=('ext2' '' 'ext3' '' 'ext4' '' 'reiserfs' '' 'reiser4' '' 'xfs' '' 'jfs' '' 'btrfs' '')
		showMenu  "FORMAT SELECTION" "FSarchiver-Backup" "${bold}Current format is: $ORG_FORM${nc}\nChoose the new format you like:" "15" "50" "5" "${arr[@]}"
		FORM=$CHOICE
	else
		FORM=$ORG_FORM
	fi
	LABEL=$(showInput "INPUT LABEL" "Current FS label is: ${bold}${LABEL}${nc}\n\n    Please enter your if you want to change it." "15" "60" "${LABEL}")
	if [ ! $LABEL ]; then
		if [[ $ORG_USIZE -le 629145600 || `grep -E "efi|EFI"<<< ${BK_FILE##*/}` ]]; then # if size less or equal 600MB assumed is EFI
			LABEL="EFI"
		else
			LABEL="root";
		fi
	fi
	showYN "The restore will be done with the following parameters:\n  Device to wich to restore: ${bold}${DEVICE}${nc}\n  With the FSformat: ${bold}$FORM${nc}\n  With the Label: ${bold}$LABEL${nc}\n  and UUID: ${bold}$UUID${nc}\n\n     ${bold}Do you want to proceed?${nc}" 15 60
	if [[ $? -ne 0 ]]; then
		return 1
	fi
	RESULT=$({ fsarchiver restfs ${BK_FILE} id=0,dest=/dev/${DEVICE},label=$LABEL,mkfs=${FORM},uuid=$UUID; } 2>&1 | tee -a $BACKUP_LOG )
	if [[ $RESULT == *"provide the password"* ]]; then
		askPass "\nThe file is secured by password.\nPlease provide it." 10 50
		if [[ $? -ne 0 ]]; then return 1; fi
		MSG=$({ fsarchiver restfs -c "${FSPASS}" ${BK_FILE} id=0,dest=/dev/${DEVICE},label=$LABEL,mkfs=${FORM},uuid=$UUID; } 2>&1 )
		local fsarchiver_exit_code=$?
		if [[ $fsarchiver_exit_code -ne 0 ]]; then showMsg "\nWrong password, exit now" 6 30; return 1; fi
	else
		MSG=$({ fsarchiver restfs ${BK_FILE} id=0,dest=/dev/${DEVICE},label=$LABEL,mkfs=${FORM},uuid=$UUID; } 2>&1 )
		if [[ $fsarchiver_exit_code -ne 0 ]]; then showMsg "\nSomething went wrong, exit now" 6 30; return 1; fi
	fi
		echo "$MSG" 2>&1 | tee -a $BACKUP_LOG
		showMsg "$MSG" 30 70
	# Store PID of fsarchiver process for signal handler
	CURRENT_FSARCHIVER_PID=$!
	
	# Wait for fsarchiver process
	wait $CURRENT_FSARCHIVER_PID
	#local fsarchiver_exit_code=$?
	#if [ ERROR_MSG ]; then echo 1; else echo 0; fi
	exit
	# Reset fsarchiver PID (finished)
	CURRENT_FSARCHIVER_PID=""
	
	# Check if script was interrupted
	if [[ "$SCRIPT_INTERRUPTED" == true ]]; then
		echo -e "${YELLOW}Restore was interrupted while processing $device${NC}"
		return 1
	fi
	
	# Check fsarchiver exit code
	if [[ $fsarchiver_exit_code -ne 0 ]]; then
		echo -e "${RED}fsarchiver exited with code: $fsarchiver_exit_code${NC}"
		ERROR=1
		ERROR_MSG+="fsarchiver exit code $fsarchiver_exit_code for device $device\n"
		showError "$ERROR_MSG" 20 80
	else
		showMsg "Restore completed successfully on: {BACKUP_DATE}\nRuntime: {RUNTIME_MIN} minutes and {RUNTIME_SEC} seconds." "15" "60" 
	fi
}

# Check for temporary fsarchiver mount points and automatic cleanup
echo -e "${BLUE}Checking temporary fsarchiver mount points...${NC}"
if ! cleanup_fsarchiver_mounts true; then
    echo -e "${YELLOW}Warning: Some fsarchiver mount points could not be automatically removed.${NC}"
    echo -e "${YELLOW}This may cause problems. Please check manually with:${NC}"
    echo -e "${YELLOW}findmnt | grep /tmp/fsa${NC}"
    echo ""
    
    # Optional: Ask user if they want to continue anyway
    # echo -e "${YELLOW}Do you want to continue anyway? (y/N): ${NC}"
    # read -r response
    # if [[ ! "$response" =~ ^[Yy]$ ]]; then
    #     echo -e "${RED}Backup aborted.${NC}"
    #     exit 1
    # fi
fi

#####################################################################
#  FSARCHIVER MENU
#####################################################################
while true;
do
#unset $(env | cut -d= -f1)
#TITLE, PROMPT, HEIGHT, WIDTH, DEV_HEIGHT, ARRAY
MENU=("1." "Backup EFI & System partitions" \
"2." "Backup EFI partition" \
"3." "Backup System partition" \
"4." "Check EFI & System backups" \
"5." "Restore EFI or System partitions" \
"6." "Exit")
showMenu "MAIN MENU" "FSarchiver-Backup" "\nPlease select from Menu" "15" "50" "5" "${MENU[@]}"
case "$CHOICE" in
"1.")
	echo "Backup EFI & System partitions"
	DO_CHOICE="Backup"
	MainBackup "EFISYS"
;;
"2.")
	echo "Backup EFI & System partitions"
	DO_CHOICE="Backup"
	MainBackup "EFI"
;;
"3.")
	echo "Backup EFI & System partitions"
	DO_CHOICE="Backup"
	MainBackup "SYS"
;;
"4.")
	echo "Check EFI & System backups"
	DO_CHOICE="CheckBackup"
	CheckBackup
;;
"5.")
	echo "Restore EFI or System partitions"
	DO_CHOICE="Restore"
	MainRestore
;;
"6.")
	echo "6"
	cleanup_on_interrupt
	exit 1
;;
*)
	cleanup_on_interrupt
	exit 1
esac
done
#####################################################################
