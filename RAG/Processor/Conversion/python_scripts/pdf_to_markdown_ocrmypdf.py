#!/usr/bin/env python3
"""
PDF to Markdown converter using OCRmyPDF.
This script converts a PDF file to Markdown format using OCRmyPDF and PyMuPDF.
"""

import sys
import os
import argparse
import tempfile
import ocrmypdf
import fitz  # PyMuPDF


def convert_pdf_to_markdown(pdf_file: str, md_output: str, force_ocr: bool = True) -> bool:
    """
    Convert a PDF file to Markdown format using OCRmyPDF.
    
    Args:
        pdf_file: Path to the input PDF file
        md_output: Path to the output Markdown file
        force_ocr: Whether to force OCR even if the PDF already contains text
        
    Returns:
        bool: True if conversion was successful, False otherwise
    """
    # Create a temporary file for the OCR'd PDF
    fd, temp_pdf = tempfile.mkstemp(suffix='.pdf')
    os.close(fd)
    
    try:
        print(f"Processing {pdf_file} with OCRmyPDF...")
        
        # Run OCR on the PDF
        ocrmypdf.ocr(pdf_file, temp_pdf, force_ocr=force_ocr)
        
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
                    f.write("\n\n---\n\n")  # Page break in Markdown
                
                f.write(f"# Page {i+1}\n\n")
                f.write(text)
        
        # Verify the output file was created
        if os.path.exists(md_output):
            md_size = os.path.getsize(md_output)
            print(f"Conversion completed successfully.")
            print(f"Created Markdown file: {md_output} ({md_size} bytes)")
            return True
        else:
            print(f"Error: Markdown file not created.")
            return False
    
    except Exception as e:
        print(f"Error during conversion: {str(e)}", file=sys.stderr)
        return False
        
    finally:
        # Clean up temporary file
        if os.path.exists(temp_pdf):
            os.unlink(temp_pdf)


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description="Convert PDF to Markdown using OCRmyPDF"
    )
    parser.add_argument(
        "pdf_file",
        help="Path to the input PDF file"
    )
    parser.add_argument(
        "md_output",
        help="Path to the output Markdown file"
    )
    parser.add_argument(
        "--no-force-ocr",
        action="store_true",
        help="Do not force OCR if PDF already contains text"
    )
    
    args = parser.parse_args()
    
    # Validate input file exists
    if not os.path.exists(args.pdf_file):
        print(f"Error: PDF file not found: {args.pdf_file}", file=sys.stderr)
        sys.exit(1)
    
    # Perform conversion
    success = convert_pdf_to_markdown(
        args.pdf_file, 
        args.md_output, 
        force_ocr=not args.no_force_ocr
    )
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
