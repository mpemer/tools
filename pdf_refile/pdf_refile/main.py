# pdf_refile.main
#
# Script that organizes scanned PDF files,
# into searchable PDF files in datetree folder structure
#
# Copyright (C) 2023-2024 Marcus Pemer
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
# Files: pdf_refile/main.py
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
# and run it like so: python <path/to/pdf_refile/main.py>
#
import os
import sys
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path
import re
import argparse
import signal

# Logging levels
DEBUG = 0
INFO = 1
WARNING = 1
ERROR = 1
DRY_RUN = 0

def debug_print(msg):
    if DEBUG:
        print(f"[DEBUG] {msg}")

def info_print(msg):
    if INFO:
        print(f"[INFO] {msg}")

def warning_print(msg):
    if WARNING:
        print(f"[WARNING] {msg}", file=sys.stderr)

def error_print(msg):
    if ERROR:
        print(f"[ERROR] {msg}", file=sys.stderr)

def exit_with_error(msg, exit_code=1):
    error_print(msg)
    sys.exit(exit_code)

def check_dependencies():
    for util in ['ocrmypdf', 'pdftotext']:
        if not shutil.which(util):
            exit_with_error(f"The {util} utility is required but it's not installed. Aborting.", 1)

def parse_date(line):
    line = line.strip()
    date_formats = [
        "%Y/%m/%d", "%Y-%m-%d", "%Y.%m.%d",
        "%d/%m/%Y", "%d-%m-%Y", "%d.%m.%Y",
        "%B %d, %Y", "%b %d, %Y"
    ]
    for date_format in date_formats:
        try:
            return datetime.strptime(line, date_format).strftime("%Y%m%d")
        except ValueError:
            continue
    return None

def extract_date_from_filename(filename):
    # Match YYYYMMDD at the start of the filename
    match = re.match(r'^([0-9]{8})[_-].*\.pdf$', filename)
    if match:
        return match.group(1)

    # Match the format "Receipt - CVS - May 17, 2024.pdf"
    match = re.match(r'.*\s-\s.*\s-\s([A-Za-z]+\s[0-9]{1,2},\s[0-9]{4})\.pdf$', filename)
    if match:
        return parse_date(match.group(1))

    return None

def process_files(scan_dir, dest_dir, recursive):
    tmp_dir = tempfile.mkdtemp()

    try:
        if recursive:
            files = Path(scan_dir).rglob("*.pdf")
        else:
            files = Path(scan_dir).glob("*.pdf")

        for file_path in files:
            file_path_str = str(file_path)
            info_print(f"Processing {file_path_str}...")

            ocr_file = os.path.join(tmp_dir, os.path.basename(file_path_str))
            subprocess.run(['ocrmypdf', '--skip-text', '--output-type', 'pdf', '--quiet', file_path_str, ocr_file], check=True)

            date_stamp = extract_date_from_filename(os.path.basename(file_path_str))
            if date_stamp:
                debug_print(f"Date stamp extracted from file name: {date_stamp}")
            else:
                result = subprocess.run(['pdftotext', ocr_file, '-'], capture_output=True, text=True)
                for line in result.stdout.splitlines():
                    date_stamp = parse_date(line)
                    if date_stamp:
                        debug_print(f"Date stamp extracted from OCR text: {date_stamp}")
                        break

            if not date_stamp:
                stat = os.stat(file_path_str)
                suggested_date = datetime.fromtimestamp(stat.st_ctime).strftime("%Y%m%d")
                while True:
                    user_input = input(f"Please validate/enter the date for {file_path_str} (YYYYMMDD) [Enter to accept '{suggested_date}', 'o' to open]: ")
                    if user_input.lower() == 'o':
                        if sys.platform == "darwin":
                            open_command = ["open", file_path_str]
                        elif sys.platform.startswith("linux"):
                            open_command = ["xdg-open", file_path_str]
                        elif sys.platform == "win32":
                            open_command = ["start", "", file_path_str]
                        else:
                            print("Unsupported platform for opening files")
                            continue
                        subprocess.run(open_command)
                    else:
                        date_stamp = user_input or suggested_date
                        break

            year, month, day = date_stamp[:4], date_stamp[4:6], date_stamp[6:8]
            dest_folder = os.path.join(dest_dir, year, month, day)
            dest_file = os.path.join(dest_folder, os.path.basename(file_path_str))

            os.makedirs(dest_folder, exist_ok=True)
            counter = 1
            while os.path.exists(dest_file):
                dest_file = os.path.join(dest_folder, f"{os.path.splitext(os.path.basename(file_path_str))[0]}_{counter}.pdf")
                counter += 1

            info_print(f"Moving processed file to {dest_file}")
            if not DRY_RUN:
                shutil.move(ocr_file, dest_file)
                os.remove(file_path_str)
    finally:
        shutil.rmtree(tmp_dir)

def handle_exit(signum, frame):
    print("Exiting.")
    sys.exit(0)

def main():
    parser = argparse.ArgumentParser(description="Organizes scanned PDF files into a searchable datetree folder structure.")
    parser.add_argument("-s", "--scan_dir", default=None, help="Directory to scan for PDF files (default: current directory)")
    parser.add_argument("-d", "--dest_dir", default=os.getcwd(), help="Destination directory for organized PDF files (default: current directory)")
    parser.add_argument("-l", "--log_level", choices=['info', 'warning', 'error', 'debug'], default='info', help="Log level (default: info)")
    parser.add_argument("-n", "--dry_run", action="store_true", help="Dry-run mode. Do not move files, just print datestamp.")
    args = parser.parse_args()

    global INFO, WARNING, ERROR, DEBUG, DRY_RUN
    if args.log_level == 'info':
        DEBUG = 0
        INFO = 1
        WARNING = 1
        ERROR = 1
    elif args.log_level == 'warning':
        DEBUG = 0
        INFO = 0
        WARNING = 1
        ERROR = 1
    elif args.log_level == 'error':
        DEBUG = 0
        INFO = 0
        WARNING = 0
        ERROR = 1
    elif args.log_level == 'debug':
        DEBUG = 1
        INFO = 1
        WARNING = 1
        ERROR = 1

    DRY_RUN = args.dry_run

    # Set up signal handling for graceful exit
    signal.signal(signal.SIGINT, handle_exit)
    signal.signal(signal.SIGTERM, handle_exit)

    scan_dir = args.scan_dir if args.scan_dir else os.getcwd()
    recursive = args.scan_dir is not None

    check_dependencies()
    process_files(scan_dir, args.dest_dir, recursive)

if __name__ == "__main__":
    main()
