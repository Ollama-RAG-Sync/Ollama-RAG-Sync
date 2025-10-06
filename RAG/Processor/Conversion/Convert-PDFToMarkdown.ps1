# PDF to Markdown Processor Script
# This script converts a single PDF file to Markdown format
# using multiple OCR tool options: marker, tesseract, ocrmypdf, or pymupdf

#Requires -Version 7.0

param (
    [Parameter(Mandatory=$true)]
    [string]$PdfFilePath,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputFilePath,

    [Parameter(Mandatory=$true)]
    [string]$LogFilePath,

    [Parameter(Mandatory=$false)]
    [ValidateSet("marker", "tesseract", "ocrmypdf", "pymupdf")]
    [string]$OcrTool = "pymupdf"
)

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console
    if ($Level -eq "ERROR") {
        Write-Host $logMessage
    }
    elseif ($Level -eq "WARNING") {
        Write-Host $logMessag
    }
    elseif ($Verbose -or $Level -eq "INFO") {
        Write-Host $logMessage
    }
}

# Function to install the required OCR library based on the selected tool
function Install-OcrLibrary {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Tool
    )
    
    switch ($Tool) {
        "marker" {
            return Install-MarkerLibrary
        }
        "tesseract" {
            return Install-TesseractLibrary
        }
        "ocrmypdf" {
            return Install-OcrMyPdfLibrary
        }
        "pymupdf" {
            return Install-PyMuPdfLibrary
        }
        default {
            Write-Log -Level "ERROR" -Message "Unsupported OCR tool: $Tool"
            return $false
        }
    }
}

# Function to install the marker library
function Install-MarkerLibrary {
    try {
        # Check if Python is installed
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Write-Log -Level "ERROR" -Message "Python is not installed. Please install Python before proceeding."
            return $false
        }
        
        # Check if marker is already installed
        $markerInstalled = $false
        $pipListOutput = & python -m pip list 2>&1
        if ($pipListOutput -match "marker") {
            Write-Log -Message "marker library is already installed."
            $markerInstalled = $true
        }
        
        # Install marker using pip if not already installed
        if (-not $markerInstalled) {
            Write-Log -Message "Installing marker library..."
            & python -m pip install marker
            
            if ($LASTEXITCODE -ne 0) {
                Write-Log -Level "ERROR" -Message "Failed to install marker library. Please install it manually using: python -m pip install marker"
                return $false
            }
            
            Write-Log -Message "marker library installed successfully."
        }
        
        return $true
    }
    catch {
        Write-Log -Level "ERROR" -Message "Error installing marker library: $_"
        return $false
    }
}

# Function to install the Tesseract OCR library
function Install-TesseractLibrary {
    try {
        # Check if Python is installed
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Write-Log -Level "ERROR" -Message "Python is not installed. Please install Python before proceeding."
            return $false
        }
        
        # Check if tesseract-ocr is installed
        $tesseractInstalled = $false
        try {
            $tesseractCheck = & tesseract --version 2>&1
            if ($tesseractCheck -match "tesseract") {
                Write-Log -Message "Tesseract OCR is already installed."
                $tesseractInstalled = $true
            }
        }
        catch {
            $tesseractInstalled = $false
        }
        
        if (-not $tesseractInstalled) {
            Write-Log -Level "WARNING" -Message "Tesseract OCR needs to be installed separately. Please download and install from: https://github.com/UB-Mannheim/tesseract/wiki"
            Write-Log -Message "Attempting to continue with Python libraries installation..."
        }
        
        # Check if pytesseract and related libraries are installed
        $pytesseractInstalled = $false
        $pipListOutput = & python -m pip list 2>&1
        if ($pipListOutput -match "pytesseract" -and $pipListOutput -match "Pillow" -and $pipListOutput -match "pdf2image") {
            Write-Log -Message "Required Python libraries for Tesseract are already installed."
            $pytesseractInstalled = $true
        }
        
        # Install required Python libraries if not already installed
        if (-not $pytesseractInstalled) {
            Write-Log -Message "Installing required Python libraries for Tesseract OCR..."
            & python -m pip install pytesseract Pillow pdf2image markdown
            
            if ($LASTEXITCODE -ne 0) {
                Write-Log -Level "ERROR" -Message "Failed to install required Python libraries for Tesseract OCR."
                return $false
            }
            
            Write-Log -Message "Required Python libraries for Tesseract OCR installed successfully."
        }
        
        # Check for poppler for pdf2image
        $popplerInstalled = $false
        try {
            $popplerCheck = & pdftoppm -v 2>&1
            if ($popplerCheck -match "pdftoppm") {
                Write-Log -Message "Poppler is already installed."
                $popplerInstalled = $true
            }
        }
        catch {
            $popplerInstalled = $false
        }
        
        if (-not $popplerInstalled) {
            Write-Log -Level "WARNING" -Message "Poppler is not installed. This is required for pdf2image to convert PDFs. Please download and install from: https://github.com/oschwartz10612/poppler-windows/releases/"
            Write-Log -Level "WARNING" -Message "After installing, ensure the bin directory is added to your PATH environment variable."
        }
        
        return $true
    }
    catch {
        Write-Log -Level "ERROR" -Message "Error installing Tesseract OCR libraries: $_"
        return $false
    }
}

# Function to install OCRmyPDF library
function Install-OcrMyPdfLibrary {
    try {
        # Check if Python is installed
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Write-Log -Level "ERROR" -Message "Python is not installed. Please install Python before proceeding."
            return $false
        }
        
        # Check if tesseract-ocr is installed (required by OCRmyPDF)
        $tesseractInstalled = $false
        try {
            $tesseractCheck = & tesseract --version 2>&1
            if ($tesseractCheck -match "tesseract") {
                Write-Log -Message "Tesseract OCR is already installed."
                $tesseractInstalled = $true
            }
        }
        catch {
            $tesseractInstalled = $false
        }
        
        if (-not $tesseractInstalled) {
            Write-Log -Level "WARNING" -Message "Tesseract OCR needs to be installed separately. Please download and install from: https://github.com/UB-Mannheim/tesseract/wiki"
            Write-Log -Message "Attempting to continue with OCRmyPDF installation..."
        }
        
        # Check if OCRmyPDF is installed
        $ocrmypdfInstalled = $false
        $pipListOutput = & python -m pip list 2>&1
        if ($pipListOutput -match "ocrmypdf") {
            Write-Log -Message "OCRmyPDF is already installed."
            $ocrmypdfInstalled = $true
        }
        
        # Install OCRmyPDF if not already installed
        if (-not $ocrmypdfInstalled) {
            Write-Log -Message "Installing OCRmyPDF..."
            & python -m pip install ocrmypdf markdown
            
            if ($LASTEXITCODE -ne 0) {
                Write-Log -Level "ERROR" -Message "Failed to install OCRmyPDF. Please install it manually using: python -m pip install ocrmypdf"
                return $false
            }
            
            Write-Log -Message "OCRmyPDF installed successfully."
            
            # Check for Ghostscript (required by OCRmyPDF)
            $gsInstalled = $false
            try {
                $gsCheck = & gswin64c -v 2>&1
                if ($gsCheck -match "Ghostscript") {
                    Write-Log -Message "Ghostscript is already installed."
                    $gsInstalled = $true
                }
            }
            catch {
                $gsInstalled = $false
            }
            
            if (-not $gsInstalled) {
                Write-Log -Level "WARNING" -Message "Ghostscript is not installed. This is required by OCRmyPDF. Please download and install from: https://ghostscript.com/releases/gsdnld.html"
            }
        }
        
        return $true
    }
    catch {
        Write-Log -Level "ERROR" -Message "Error installing OCRmyPDF: $_"
        return $false
    }
}

# Function to install PyMuPDF library
function Install-PyMuPdfLibrary {
    try {
        # Check if Python is installed
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Write-Log -Level "ERROR" -Message "Python is not installed. Please install Python before proceeding."
            return $false
        }
        
        # Check if PyMuPDF is already installed
        $pymupdfInstalled = $false
        $pipListOutput = & python -m pip list 2>&1
        if ($pipListOutput -match "PyMuPDF") {
            Write-Log -Message "PyMuPDF is already installed."
            $pymupdfInstalled = $true
        }
        
        # Install PyMuPDF using pip if not already installed
        if (-not $pymupdfInstalled) {
            Write-Log -Message "Installing PyMuPDF..."
            & python -m pip install PyMuPDF markdown
            
            if ($LASTEXITCODE -ne 0) {
                Write-Log -Level "ERROR" -Message "Failed to install PyMuPDF. Please install it manually using: python -m pip install PyMuPDF"
                return $false
            }
            
            Write-Log -Message "PyMuPDF installed successfully."
        }
        
        return $true
    }
    catch {
        Write-Log -Level "ERROR" -Message "Error installing PyMuPDF: $_"
        return $false
    }
}

# Unified function to convert PDF to Markdown and TXT while preserving directory structure
function Convert-PdfToMarkdownAndTxt {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PdfFile,
        
        [Parameter(Mandatory=$true)]
        [string]$SourceDir,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputFile
    )
    
    try {
        # Get relative path from source directory
        $relativePath = (Get-Item $PdfFile).DirectoryName.Substring($SourceDir.Length)
        if ($relativePath.StartsWith('\')) {
            $relativePath = $relativePath.Substring(1)
        }
        
        # Choose conversion method based on selected OCR tool
        Write-Log -Message "Converting $PdfFile to Markdown using $OcrTool..."
        
        switch ($OcrTool) {
            "marker" {
                $success = Convert-PdfWithMarker -PdfFile $PdfFile -MdOutputPath $OutputFile
            }
            "tesseract" {
                $success = Convert-PdfWithTesseract -PdfFile $PdfFile -MdOutputPath $OutputFile
            }
            "ocrmypdf" {
                $success = Convert-PdfWithOcrMyPdf -PdfFile $PdfFile -MdOutputPath $OutputFile
            }
            "pymupdf" {
                $success = Convert-PdfWithPyMuPdf -PdfFile $PdfFile -MdOutputPath $OutputFile
            }
            default {
                Write-Log -Level "ERROR" -Message "Unsupported OCR tool: $OcrTool"
                return $false
            }
        }
        
        if (-not $success) {
            Write-Log -Level "ERROR" -Message "Conversion failed for $PdfFile with $OcrTool"
            return $false
        }
        
        # Verify the output files exist
        if (-not (Test-Path -Path $OutputFile)) {
            Write-Log -Level "ERROR" -Message "Output files were not created successfully for $PdfFile"
            return $false
        }
        
        Write-Log -Message "Conversion completed for $PdfFile using $OcrTool"
        return $true
    }
    catch {
        Write-Log -Level "ERROR" -Message "Error converting $PdfFile : $_"
        return $false
    }
}

# Convert PDF using Marker library
function Convert-PdfWithMarker {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PdfFile,
        
        [Parameter(Mandatory=$true)]
        [string]$MdOutputPath
    )
    
    try {
        # Get the path to the Python script
        $scriptDir = Split-Path -Parent $PSScriptRoot
        $pythonScriptPath = Join-Path $scriptDir "Conversion\python_scripts\pdf_to_markdown_marker.py"
        
        if (-not (Test-Path -Path $pythonScriptPath)) {
            Write-Log -Level "ERROR" -Message "Python script not found: $pythonScriptPath"
            return $false
        }
        
        # Execute the Python script
        $result = & python $pythonScriptPath $PdfFile $MdOutputPath 2>&1
        $exitCode = $LASTEXITCODE
        
        # Output the result from the Python script
        foreach ($line in $result) {
            Write-Log -Message $line
        }
        
        return ($exitCode -eq 0)
    }
    catch {
        Write-Log -Level "ERROR" -Message "Error using Marker OCR: $_"
        return $false
    }
}

# Convert PDF using Tesseract OCR
function Convert-PdfWithTesseract {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PdfFile,
        
        [Parameter(Mandatory=$true)]
        [string]$MdOutputPath
    )
    
    try {
        # Get the path to the Python script
        $scriptDir = Split-Path -Parent $PSScriptRoot
        $pythonScriptPath = Join-Path $scriptDir "Conversion\python_scripts\pdf_to_markdown_tesseract.py"
        
        if (-not (Test-Path -Path $pythonScriptPath)) {
            Write-Log -Level "ERROR" -Message "Python script not found: $pythonScriptPath"
            return $false
        }
        
        # Execute the Python script
        $result = & python $pythonScriptPath $PdfFile $MdOutputPath 2>&1
        $exitCode = $LASTEXITCODE
        
        # Output the result from the Python script
        foreach ($line in $result) {
            Write-Log -Message $line
        }
        
        return ($exitCode -eq 0)
    }
    catch {
        Write-Log -Level "ERROR" -Message "Error using Tesseract OCR: $_"
        return $false
    }
}

# Convert PDF using OCRmyPDF
function Convert-PdfWithOcrMyPdf {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PdfFile,
        
        [Parameter(Mandatory=$true)]
        [string]$MdOutputPath
    )
    
    try {
        # Get the path to the Python script
        $scriptDir = Split-Path -Parent $PSScriptRoot
        $pythonScriptPath = Join-Path $scriptDir "Conversion\python_scripts\pdf_to_markdown_ocrmypdf.py"
        
        if (-not (Test-Path -Path $pythonScriptPath)) {
            Write-Log -Level "ERROR" -Message "Python script not found: $pythonScriptPath"
            return $false
        }
        
        # Execute the Python script
        $result = & python $pythonScriptPath $PdfFile $MdOutputPath 2>&1
        $exitCode = $LASTEXITCODE
        
        # Output the result from the Python script
        foreach ($line in $result) {
            Write-Log -Message $line
        }
        
        return ($exitCode -eq 0)
    }
    catch {
        Write-Log -Level "ERROR" -Message "Error using OCRmyPDF: $_"
        return $false
    }
}

# Convert PDF using PyMuPDF
function Convert-PdfWithPyMuPdf {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PdfFile,
        
        [Parameter(Mandatory=$true)]
        [string]$MdOutputPath
    )
    
    try {
        # Get the path to the Python script
        $scriptDir = Split-Path -Parent $PSScriptRoot
        $pythonScriptPath = Join-Path $scriptDir "Conversion\python_scripts\pdf_to_markdown_pymupdf.py"
        
        if (-not (Test-Path -Path $pythonScriptPath)) {
            Write-Log -Level "ERROR" -Message "Python script not found: $pythonScriptPath"
            return $false
        }
        
        # Execute the Python script
        $result = & python $pythonScriptPath $PdfFile $MdOutputPath 2>&1
        $exitCode = $LASTEXITCODE
        
        # Output the result from the Python script
        foreach ($line in $result) {
            Write-Log -Message $line
        }
        
        return ($exitCode -eq 0)
    }
    catch {
        Write-Log -Level "ERROR" -Message "Error using PyMuPDF: $_"
        return $false
    }
}

# Function to process a single PDF file
function Process-SinglePdf {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PdfFile,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputFile
    )
    
    # Ensure PDF file exists
    if (-not (Test-Path -Path $PdfFile)) {
        Write-Log -Level "ERROR" -Message "PDF file does not exist: $PdfFile"
        return $null
    }
    
    # Get PDF file information
    $pdfFileInfo = Get-Item -Path $PdfFile
    Write-Log -Message "Processing PDF file: $PdfFile"
    Write-Log -Message "Output file will be: $OutputFile"
    
    # Process the PDF file
    $fileDir = $pdfFileInfo.DirectoryName
    $success = Convert-PdfToMarkdownAndTxt -PdfFile $PdfFile -SourceDir $fileDir -OutputFile $OutputFile
    
    if ($success) {
        Write-Log -Message "PDF file processed successfully."
        return $OutputFile
    }
    
    return $null
}

# Main function
function Start-Processing {
    try {
        Write-Log -Message "Starting PDF processing script..."
        Write-Log -Message "PDF file: $PdfFilePath"
        Write-Log -Message "Output file: $OutputFilePath"
        Write-Log -Message "Log file: $LogFilePath"
        Write-Log -Message "Using OCR tool: $OcrTool"
        
        # Install the required OCR library
        $ocrInstalled = Install-OcrLibrary -Tool $OcrTool
        if (-not $ocrInstalled) {
            Write-Log -Level "ERROR" -Message "Required $OcrTool library could not be installed. Script cannot continue."
            return $null
        }
        
        # Process the single PDF file and return the output path
        $outputPath = Process-SinglePdf -PdfFile $PdfFilePath -OutputFile $OutputFilePath
        
        if ($outputPath) {
            Write-Log -Message "Processing complete. Output file: $outputPath" 
            return $outputPath
        } else {
            Write-Log -Level "ERROR" -Message "Failed to process PDF file."
            return $null
        }
    }
    catch {
        Write-Log -Level "ERROR" -Message "Error in main processing: $_"
        return $null
    }
}

Write-Host "Initializing PDF to Markdown conversion"
# Start processing and return the output path
$markdownPath = Start-Processing

# Return the markdown path
return $markdownPath
