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
        # Convert to Markdown using Python marker library
        $pythonScript = @"
import sys
import os
from marker.converters.pdf import PdfConverter
from marker.models import create_model_dict

if __name__ == "__main__":
    try:
        # Load the PDF file
        pdf_file = '$($PdfFile.Replace("\", "\\"))'
        md_output = '$($MdOutputPath.Replace("\", "\\"))'
    
        # Initialize the converter
        converter = PdfConverter(
            artifact_dict=create_model_dict(),
        )
    
        # Convert the PDF
        print(f"Processing {pdf_file}...")

        rendered = converter(pdf_file)
        
        # Save as Markdown
        print(f"Saving Markdown to {md_output}...")
        with open(md_output, 'w', encoding='utf-8') as f:
            f.write(rendered.markdown)
    
        # Verify the output files were created
        if os.path.exists(md_output):
            md_size = os.path.getsize(md_output)
            print(f"Conversion completed successfully.")
            print(f"Created Markdown file: {md_output} ({md_size} bytes)")
            sys.exit(0)
        else:
            missing = []
            if not os.path.exists(md_output):
                missing.append("Markdown file")
            print(f"Error: {', '.join(missing)} not created.")
            sys.exit(1)

    except Exception as e:
            print(f"Error during conversion: {str(e)}")
            sys.exit(1)
"@

        # Save the Python script to a temporary file
        $scriptPath = [System.IO.Path]::GetTempFileName() + ".py"
        $pythonScript | Out-File -FilePath $scriptPath -Encoding UTF8
        Write-Host $scriptPath        
        # Execute the Python script
        $result = & python $scriptPath 2>&1
        $exitCode = $LASTEXITCODE
        
        # Remove temporary script file
        $null = Remove-Item -Path $scriptPath -Force
        
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
        # Convert to Markdown using pytesseract
        $pythonScript = @"
import sys
import os
import pytesseract
from pdf2image import convert_from_path
from PIL import Image
import tempfile
import shutil

if __name__ == "__main__":
    try:
        # Load the PDF file
        pdf_file = '$($PdfFile.Replace("\", "\\"))'
        md_output = '$($MdOutputPath.Replace("\", "\\"))'
        temp_dir = tempfile.mkdtemp()
        
        try:
            print(f"Processing {pdf_file}...")
            
            # Convert PDF to images
            print("Converting PDF to images...")
            pages = convert_from_path(pdf_file, dpi=200, thread_count=4, poppler_path=None)
            
            # Process each page
            full_text = []
            for i, page in enumerate(pages):
                print(f"Processing page {i+1}/{len(pages)}...")
                # Save page as temporary image
                img_path = os.path.join(temp_dir, f"page_{i+1}.png")
                page.save(img_path, "PNG")
                
                # Extract text using tesseract
                text = pytesseract.image_to_string(Image.open(img_path))
                full_text.append(text)
            
            # Combine text and save as Markdown
            print(f"Saving Markdown to {md_output}...")
            with open(md_output, 'w', encoding='utf-8') as f:
                # Add page breaks and headers
                for i, text in enumerate(full_text):
                    if i > 0:
                        f.write("\\n\\n---\\n\\n")  # Page break in Markdown
                    
                    f.write(f"# Page {i+1}\\n\\n")
                    f.write(text)
            
            # Verify the output file was created
            if os.path.exists(md_output):
                md_size = os.path.getsize(md_output)
                print(f"Conversion completed successfully.")
                print(f"Created Markdown file: {md_output} ({md_size} bytes)")
                sys.exit(0)
            else:
                print(f"Error: Markdown file not created.")
                sys.exit(1)
                
        finally:
            # Clean up temporary directory
            shutil.rmtree(temp_dir)

    except Exception as e:
        print(f"Error during conversion: {str(e)}")
        sys.exit(1)
"@

        # Save the Python script to a temporary file
        $scriptPath = [System.IO.Path]::GetTempFileName() + ".py"
        $pythonScript | Out-File -FilePath $scriptPath -Encoding UTF8

        # Execute the Python script
        $result = & python $scriptPath 2>&1
        $exitCode = $LASTEXITCODE
        
        # Remove temporary script file
        $null = Remove-Item -Path $scriptPath -Force
        
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
        # Convert to Markdown using OCRmyPDF
        $pythonScript = @"
import sys
import os
import tempfile
import ocrmypdf
import fitz  # PyMuPDF

if __name__ == "__main__":
    try:
        # Load the PDF file
        pdf_file = '$($PdfFile.Replace("\", "\\"))'
        md_output = '$($MdOutputPath.Replace("\", "\\"))'
        
        # Create a temporary file for the OCR'd PDF
        fd, temp_pdf = tempfile.mkstemp(suffix='.pdf')
        os.close(fd)
        
        try:
            print(f"Processing {pdf_file} with OCRmyPDF...")
            
            # Run OCR on the PDF
            ocrmypdf.ocr(pdf_file, temp_pdf, force_ocr=True)
            
            # Extract text from the OCR'd PDF using PyMuPDF
            print("Extracting text from OCR'd PDF...")
            doc = fitz.open(temp_pdf)
            full_text = []
            
            for page_num in range(len(doc)):
                page = doc.load_page(page_num)
                text = page.get_text()
                full_text.append(text)
            
            doc.close()
            
            # Save as Markdown
            print(f"Saving Markdown to {md_output}...")
            with open(md_output, 'w', encoding='utf-8') as f:
                # Add page breaks and headers
                for i, text in enumerate(full_text):
                    if i > 0:
                        f.write("\\n\\n---\\n\\n")  # Page break in Markdown
                    
                    f.write(f"# Page {i+1}\\n\\n")
                    f.write(text)
            
            # Verify the output file was created
            if os.path.exists(md_output):
                md_size = os.path.getsize(md_output)
                print(f"Conversion completed successfully.")
                print(f"Created Markdown file: {md_output} ({md_size} bytes)")
                sys.exit(0)
            else:
                print(f"Error: Markdown file not created.")
                sys.exit(1)
        
        finally:
            # Clean up temporary file
            if os.path.exists(temp_pdf):
                os.unlink(temp_pdf)

    except Exception as e:
        print(f"Error during conversion: {str(e)}")
        sys.exit(1)
"@

        # Save the Python script to a temporary file
        $scriptPath = [System.IO.Path]::GetTempFileName() + ".py"
        $pythonScript | Out-File -FilePath $scriptPath -Encoding UTF8
        
        # Execute the Python script
        $result = & python $scriptPath 2>&1
        $exitCode = $LASTEXITCODE
        
        # Remove temporary script file
        $null = Remove-Item -Path $scriptPath -Force
        
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
        # Convert to Markdown using PyMuPDF
        $pythonScript = @"
import sys
import os
import fitz  # PyMuPDF

if __name__ == "__main__":
    try:
        # Load the PDF file
        pdf_file = '$($PdfFile.Replace("\", "\\"))'
        md_output = '$($MdOutputPath.Replace("\", "\\"))'
        
        print(f"Processing {pdf_file} with PyMuPDF...")
        
        # Extract text from the PDF
        doc = fitz.open(pdf_file)
        full_text = []
        
        for page_num in range(len(doc)):
            page = doc.load_page(page_num)
            
            # Get text
            text = page.get_text()
            
            # Process blocks for better structure
            blocks = page.get_text("blocks")
            structured_text = ""
            
            # Sort blocks by y-coordinate to maintain reading order
            blocks.sort(key=lambda b: b[1])  # Sort by y1 (top)
            
            for block in blocks:
                # block[4] is the text content
                structured_text += block[4] + "\\n\\n"
            
            full_text.append(structured_text if structured_text.strip() else text)
        
        doc.close()
        
        # Save as Markdown
        print(f"Saving Markdown to {md_output}...")
        with open(md_output, 'w', encoding='utf-8') as f:
            # Add page breaks and headers
            for i, text in enumerate(full_text):
                if i > 0:
                    f.write("\\n\\n---\\n\\n")  # Page break in Markdown
                
                f.write(f"# Page {i+1}\\n\\n")
                f.write(text)
        
        # Verify the output file was created
        if os.path.exists(md_output):
            md_size = os.path.getsize(md_output)
            print(f"Conversion completed successfully.")
            print(f"Created Markdown file: {md_output} ({md_size} bytes)")
            sys.exit(0)
        else:
            print(f"Error: Markdown file not created.")
            sys.exit(1)

    except Exception as e:
        print(f"Error during conversion: {str(e)}")
        sys.exit(1)
"@

        # Save the Python script to a temporary file
        $scriptPath = [System.IO.Path]::GetTempFileName() + ".py"
        $pythonScript | Out-File -FilePath $scriptPath -Encoding UTF8
        
        # Execute the Python script
        $result = & python $scriptPath 2>&1
        $exitCode = $LASTEXITCODE
        Write-Host $result
        
        # Remove temporary script file
        $null = Remove-Item -Path $scriptPath -Force
        
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
