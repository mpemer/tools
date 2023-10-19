#!/usr/bin/env bash

# pdf_refile.sh
#
# Script that organizes scanned PDF files,
# into searchable PDF files in datetree folder structure
#
# Copyright (C) 2023 Marcus Pemer
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# Author: Marcus Pemer <marcus@pemer.com>
#
# Files: pdf_refile.sh
# Dependencies: bash pdftotext ocrmypdf awk sed
#
# Instructions:
# Runs OCR on all PDF files in its directory,
# (or skips OCR if PDF is already searchable),
# Then attempts to extrace a contextual date stamp for the PDF file,
# If file name begins with YYYYMMDD-somename.pdf, then this will be used,
# If file name matches Scanned_YYYYMMDD-somename.pdf, then this will be used,
# else, try to read date from file contents,
# lastly, ask user for date stamp, suggesting file creation date as default.
# Move searchable PDF into datetree folder ./YYYY/MM/DD/.
#
# To use, place script into folder with pdf files to be organized.
# and run it like so: ./pdf_refile.sh
#

# Detect the operating system
os=$(uname)

# Set to 1 to enable print statements, 0 to disable
DEBUG=0
INFO=1
WARNING=1
ERROR=1
DRY_RUN=0

# Debug print function
debug_print() {
    if [[ $DEBUG -eq 1 ]]; then
        echo "[DEBUG] $1"
    fi
}

# Info print function
info_print() {
    if [[ $INFO -eq 1 ]]; then
        echo "[INFO] $1"
    fi
}

# Warning print function
warning_print() {
    if [[ $WARNING -eq 1 ]]; then
        echo "[WARNING] $1" >&2
    fi
}

# Error print function
error_print() {
    if [[ $ERROR -eq 1 ]]; then
        echo "[ERROR] $1" >&2
    fi
}

# Handle fatal error conditions (message and exit code)
exit_with_error() {
    local msg="$1"
    local exit_code=${2:-1}  # default exit code is 1
    error_print "$msg"
    exit $exit_code
}

# Check if required utilities exist
check_dependencies() {
    for util in ocrmypdf pdftotext awk sed date find; do
        command -v $util >/dev/null 2>&1 || { exit_with_error "The ${util} utility is required but it's not installed. Aborting." 1; }
    done
}

# Check directories
check_dirs() {
    for dir in "$@"; do
        if [[ ! -d "$dir" ]]; then
            error_print "Directory $dir does not exist."
            exit 1
        fi
    done
}

# Function to cleanup temporary directory
cleanup() {
    rm -rf "$tmp" || error_print "Failed to remove $tmp"
    return 0
}

parse_date() {
  local line=$1

  local trimmed_line=$(echo $line | sed -E 's/[[:space:]]*([-./])[[:space:]]*/\1/g')
  
  # Check if the string contains a date
  if ! echo "$trimmed_line" | grep -qE '[0-9]{2,4}[\/\.\-][0-9]{2}[\/\.\-][0-9]{2,4}'; then
    # No date found
    return 1
  fi

  # Extract the date using sed.
  local extracted_date=$(echo "$trimmed_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]{2,4}[\/\.\-][0-9]{2}[\/\.\-][0-9]{2,4}$/) print $i}' FS=" ")

  # Split the date into its components
  local delimiter=$(echo "$extracted_date" | sed -E 's/[0-9]+(.)[0-9]+.*/\1/')
  IFS="$delimiter" read -a date_parts <<< "$extracted_date"


  local year month day
  # Determine if it's a European or American date by checking the delimiter
  if [[ $delimiter == '/' ]]; then
      # American date
      month=${date_parts[0]}
      day=${date_parts[1]}
      year=${date_parts[2]}
  else
      # European date
      if [[ ${#date_parts[0]} -eq 4 ]]; then
          # YYYY MM DD format
          year=${date_parts[0]}
          month=${date_parts[1]}
          day=${date_parts[2]}
      else
          # DD MM YYYY format
          day=${date_parts[0]}
          month=${date_parts[1]}
          year=${date_parts[2]}
      fi
  fi
  
  # Prepend "20" or "19" to the year if it's only two digits
  if [[ ${#year} -eq 2 ]]; then
    if ((10#$year > 50)); then
      year="19$year"
    else
      year="20$year"
    fi
  fi

  # Sanity checks
  if ((10#$year < 1900 || 10#$year > 2050 || 10#$month < 1 || 10#$month > 12 || 10#$day < 1 || 10#$day > 31)); then
    # Invalid date
    return 1
  fi

  # Print the formatted date
  echo "$year$month$day"
  return 0
}


# Main processing function
process_files() {

    local scan_dir=$1
    local dest_dir=$2
    pushd "$scan_dir" > /dev/null

    # If date stamp is further than this many days away from today's date,
    # then user will be prompted to validate manually.
    max_days=365

    find . -maxdepth 2 -type f -name "*.pdf" | while IFS= read -r file_path; do
        # Strip './' from the beginning of the file path
        file=${file_path:2}
        filename="${file##*/}"

        info_print "Processing $file..."

        # Check if something weird has happened, and $file does not exist
        if [[ ! -f "$file" ]]; then
            error_print "File $file does not exist."
            continue  # Skip to the next file
        fi

        # Run ocrmypdf on the file with specified flags
        ocr_file="$tmp/$filename"
        debug_print "ocr_file=${ocr_file}"
        ocrmypdf -q --skip-text --output-type pdf "$file" "$ocr_file"
        if [[ $? -ne 0 ]]; then
            error_print "OCR processing failed for $file"
            continue  # Skip to the next file
        fi

        debug_print "Attempting to extract date stamp from the file name..."
        # Try to extract date stamp from the file name
        if [[ $filename =~ ^([0-9]{8})-.*\.pdf$ ]] || [[ $filename =~ ^Scanned_([0-9]{8})-.*\.pdf$ ]]; then
            date_stamp=${BASH_REMATCH[1]}
            debug_print "Date stamp extracted from the file name: $date_stamp"
        else
            debug_print "Attempting to extract date stamp from the OCR'd text..."
            # Try to extract date stamp from the OCR'd text
            date_stamp=""
            while IFS= read -r line; do
                if [[ ! $date_stamp ]]; then
                    debug_print "Trying to parse: $line"
                    date_stamp=$(parse_date "$line")
                    if [[ $? -ne 0 ]]; then
                        debug_print "No parseable date in $line"
                    fi
                    if [[ $date_stamp ]]; then
                        debug_print "Succeeded parsing $line"
                        debug_print "Date stamp extracted from OCR'd text: $date_stamp"
                        break  # Exit the loop once a date stamp is found
                    fi
                fi
            done < <(pdftotext "$ocr_file" -)
        fi

        suggested_date=""
        
        # If no date stamp found, ask the user to provide the date manually
        if [[ ! $date_stamp ]]; then
            # Get the creation date using stat

            if [[ $os == "Darwin" ]]; then
                # macOS
                suggested_date=$(stat -f "%SB" -t "%Y%m%d" "$file")
            elif [[ $os == "Linux" ]]; then
                # GNU/Linux
                suggested_date=$(stat --format=%W "$file" | xargs -I {} date -d @{} +'%Y%m%d')
            else
                exit_with_error "Unsupported operating system: $os" 1
            fi

            info_print "No date stamp could be extracted from $file."
            # Prompt the user to enter the date manually, suggesting the date obtained from stat
        else

            # There is a date stamp, so sanity check it
            
            # Convert the dates to seconds since the epoch
            date_format="%Y-%m-%d"
            current_seconds=$(date -j -f "$date_format" "$(date +%Y-%m-%d)" "+%s")
            formatted_date="${date_stamp:0:4}-${date_stamp:4:2}-${date_stamp:6:2}"
            target_seconds=$(date -j -f "$date_format" "$formatted_date" "+%s")
            # Compute the difference in days
            date_diff=$(( (current_seconds - target_seconds) / 86400 ))

            # Check if the date difference exceeds max_days
            if (( ${date_diff#-} > max_days )); then
                info_print "The parsed date stamp is more than $max_days days away from today's date."
                suggested_date="$date_stamp" # Pass suggested date so user gets prompted to validate below
            fi

        fi
        
        # Prompt for user validation, if needed
        if [[ -n $suggested_date ]]; then
            while : ; do  # Infinite loop
                read -p "Please validate/enter the date for this file (YYYYMMDD) [$suggested_date]: " user_date < /dev/tty
                # If the user just presses Enter, use the suggested_date, otherwise use what the user typed
                date_stamp=${user_date:-$suggested_date}
                if [[ $date_stamp =~ ^[0-9]{8}$ ]]; then
                    break  # Exit loop if date format is correct
                else
                    warning_print "Invalid date format. Please try again."
                fi
            done

            debug_print "Date stamp provided manually: $date_stamp"
        fi

        # Alternative:
        #    # If no date stamp found, skip the file and print a helpful message
        #    if [[ ! $date_stamp ]]; then
        #        echo "No date stamp could be extracted from $file. Skipping this file."
        #        continue  # Skip to the next iteration of the loop
        #    fi

        info_print "Date stamp: $date_stamp"

        year=${date_stamp:0:4}
        month=${date_stamp:4:2}
        day=${date_stamp:6:2}

        # Calculate destination folder and file path
        dest_folder="$dest_dir/$year/$month/$day"
        dest_file="$dest_folder/$filename"

        # Ensure destination folder exists
        if ! mkdir -p "$dest_folder"; then
            exit_with_error "Failed to create destination folder $dest_folder" 1
        fi

        # We will not clobber existing files.
        # Rather, if a conflict exists,
        # we will save with files ending in incremental counter.

        # Initialize a counter
        counter=1

        # Check if destination file already exists
        while [[ -e $dest_file ]]; do
            # Extract filename without extension
            fname="${filename%.*}"
            # Extract file extension
            extension="${filename##*.}"
            # Update destination file path with counter
            dest_file="$dest_folder/${fname}_$counter.$extension"
            # Increment counter for the next iteration (if necessary)
            ((counter++))
        done

        # Move the processed file to the destination folder
        info_print "Moving processed file to $dest_file"
        if [[ $DRY_RUN -eq 0 ]]; then
            mv "$ocr_file" "$dest_file"
            if [[ $? -ne 0 ]]; then
                error_print "Failed to move $ocr_file to $dest_file"
                continue  # Skip to the next file
            fi

            rm "$file"
            if [[ $? -ne 0 ]]; then
                error_print "Failed to remove $file"
            fi
        else
            info_print "Dry-run mode enabled. Not moving $ocr_file to $dest_file"
        fi

    done

    popd > /dev/null
}


# Set default values for scan_dir and dest_dir
# By default, assume script location is our base directory
scan_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
dest_dir="$scan_dir"

# Print usage
usage() {
    echo "Usage: $0 [-s scan_dir] [-d dest_dir] [-l log_level] [-t test_date] [-n]"
    echo "Organizes scanned PDF files into a searchable datetree folder structure."
    echo "Processed files are placed into a datetree folder structure under dest_dir."
    echo "The date to be used is read from the processed PDF file."
    echo "If a date cannot be read from the file, user is asked to provide one."
    echo
    echo "Options:"
    echo "  -s scan_dir   Directory to scan for PDF files (default: current directory)"
    echo "  -d dest_dir   Destination directory for organized PDF files (default: current directory)"
    echo "  -h            Display this help message and exit"
    echo
    echo "Log level options: (default: info)"
    echo "  -l info     Informational messages"
    echo "  -l warning  Warning messages"
    echo "  -l error    Error messages"
    echo "  -l debug    Debug messages"
    echo
    echo "  -n            Dry-run mode. Do not move files, just print datestamp."
    echo "  -t date-str   Don't run, just try parsing date-string into a datestamp."

}

# Parse command line options
while getopts ":s:d:l:t:nh" opt; do
    case $opt in
        s)
            scan_dir="$OPTARG"
            ;;
        d)
            dest_dir="$OPTARG"
            ;;
        l)
            case $OPTARG in
                info)
                    DEBUG=0
                    INFO=1
                    WARNING=1
                    ERROR=1
                    ;;
                warning)
                    DEBUG=0
                    INFO=0
                    WARNING=1
                    ERROR=1
                    ;;
                error)
                    DEBUG=0
                    INFO=0
                    WARNING=0
                    ERROR=1
                    ;;
                debug)
                    DEBUG=1
                    INFO=1
                    WARNING=1
                    ERROR=1
                    ;;
                *)
                    echo "Invalid log level: -$OPTARG" >&2
                    usage
                    exit 1
                    ;;
            esac
            ;;
        n)
            DRY_RUN=1
            ;;

        h)
            usage
            exit 0
            ;;
        t)
            parse_date "$OPTARG"
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            exit 1
            ;;
    esac
done

# Execution starts here
check_dependencies
check_dirs "$scan_dir" "$dest_dir"

# Create a temporary directory
tmp=$(mktemp -d)
# Trap to clean up temp directory on exit and on interrupt
trap cleanup EXIT
trap 'echo "Script interrupted."; cleanup; exit 1;' SIGINT SIGTERM

# Do the deed
process_files "$scan_dir" "$dest_dir"

