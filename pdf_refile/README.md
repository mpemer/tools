# pdf_refile.sh
Bash script that organizes scanned PDF files,
into searchable PDF files in datetree folder structure

## Files
pdf_refile.sh

## Dependencies
Tested on macOS - no guarantees that the script will work anywhere else.
You would need to make sure to have the following installed on your system.

bash pdftotext ocrmypdf awk sed

## Instructions
Runs OCR on all PDF files in its directory,
(or skips OCR if PDF is already searchable),
Then attempts to extrace a contextual date stamp for the PDF file,
If file name begins with YYYYMMDD-somename.pdf, then this will be used,
If file name matches Scanned_YYYYMMDD-somename.pdf, then this will be used,
else, try to read date from file contents,
lastly, ask user for date stamp, suggesting file creation date as default.
Move searchable PDF into datetree folder ./YYYY/MM/DD/.

To use, place script into folder with pdf files to be organized.
and run it like so: ./pdf_refile.sh -d destination_folder


## Usaage
Usage: ./pdf_refile.sh [-s scan_dir] [-d dest_dir] [-l log_level] [-t test_date] [-n]
Organizes scanned PDF files into a searchable datetree folder structure.
Processed files are placed into a datetree folder structure under dest_dir.
The date to be used is read from the processed PDF file.
If a date cannot be read from the file, user is asked to provide one.

Options:
  -s scan_dir   Directory to scan for PDF files (default: current directory)
  -d dest_dir   Destination directory for organized PDF files (default: current directory)
  -h            Display this help message and exit

Log level options: (default: info)
  -l info     Informational messages
  -l warning  Warning messages
  -l error    Error messages
  -l debug    Debug messages

  -n            Dry-run mode. Do not move files, just print datestamp.
  -t date-str   Don't run, just try parsing date-string into a datestamp.
  