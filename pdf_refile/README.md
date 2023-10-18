# `pdf_refile.sh` - Organize and Refile Your PDFs

`pdf_refile.sh` is a Bash script designed to streamline the organization of scanned PDF files into a structured and searchable datetree directory. It enhances the accessibility and retrieval of your PDF files, ensuring a tidy and organized file system.

## Overview

Upon execution, the script:

1. Scours a specified directory for PDF files.
2. Utilizes `ocrmypdf` to render the PDFs searchable if they aren't already.
3. Attempts to extract a relevant date stamp from the OCR text contents of each PDF file, which could be crucial for organizing scanned receipts, invoices, or other date-relevant documents.
4. If a date stamp is unobtainable or is over a year from the current date, it prompts the user for a manual date input, suggesting the file's creation date as a default option.

Users have the option to bypass the date parsing process by naming the PDF files in the following format: `YYYYMMDD-some-contextual-name.pdf`. In doing so, the prefixed date will be used as the date stamp.

The script then relocates the OCR-enhanced PDF files into a datetree folder structure following the pattern: `.../YYYY/MM/DD/the-original-file-name.pdf`, ensuring a well-organized, date-based file system. Please be aware, upon successful transfer, *the original PDF files are deleted* from the source directory. This step is irreversible and hence, precaution is advised.

A backup feature for the original scanned PDF files might be incorporated in future updates, contingent on time and necessity.

## File

- `pdf_refile.sh`

## Dependencies

The script has been tested on macOS. While it may work on other operating systems, compatibility is not guaranteed. Ensure the following utilities are installed on your system:

- bash
- pdftotext
- ocrmypdf
- awk
- sed

## Usage

To execute OCR on all PDF files in a specified directory:

1. Place the script in the directory containing the PDF files to be organized.
2. Run the script using the command: `./pdf_refile.sh -d destination_folder`

Additional command line options are available for more refined control:

```bash
Usage: ./pdf_refile.sh [-s scan_dir] [-d dest_dir] [-l log_level] [-t test_date] [-n]

Options:
  -s scan_dir    Directory to scan for PDF files (default: current directory)
  -d dest_dir    Destination directory for organized PDF files (default: current directory)
  -h             Display this help message and exit

Log level options: (default: info)
  -l info        Informational messages
  -l warning     Warning messages
  -l error       Error messages
  -l debug       Debug messages

  -n             Dry-run mode. Do not move files, just print datestamp.
  -t date-str    Don't run, just try parsing date-string into a datestamp.
```

This script simplifies the file management of scanned PDFs, providing a systematic approach to organizing your documents in a chronological and accessible manner.
