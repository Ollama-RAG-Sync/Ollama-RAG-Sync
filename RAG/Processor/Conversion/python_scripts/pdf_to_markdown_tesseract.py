#!/usr/bin/env python3
"""
PDF to Markdown converter using Tesseract OCR.
This script converts a PDF file to Markdown format using Tesseract OCR.
"""

import sys
import os
import argparse
import tempfile
import shutil
import pytesseract
from pdf2image import convert_from_path
from PIL import Image


def convert_pdf_to_markdown(pdf_file: str, md_output: str, poppler_path: str = None) -> bool:
    """
    Convert a PDF file to Markdown format using Tesseract OCR.
    
    Args:
        pdf_file: Path to the input PDF file
        md_output: Path to the output Markdown file
        poppler_path: Optional path to poppler binaries
        
    Returns:
        bool: True if conversion was successful, False otherwise
    """
    temp_dir = tempfile.mkdtemp()
    
    try:
        print(f"Processing {pdf_file}...")
        
        # Convert PDF to images
        print("Converting PDF to images...")
        pages = convert_from_path(
            pdf_file, 
            dpi=200, 
            thread_count=4, 
            poppler_path=poppler_path
        )
        
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
        # Clean up temporary directory
        shutil.rmtree(temp_dir, ignore_errors=True)


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description="Convert PDF to Markdown using Tesseract OCR"
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
        "--poppler-path",
        help="Optional path to poppler binaries",
        default=None
    )
    
    args = parser.parse_args()
    
    # Validate input file exists
    if not os.path.exists(args.pdf_file):
        print(f"Error: PDF file not found: {args.pdf_file}", file=sys.stderr)
        sys.exit(1)
    
    # Perform conversion
    success = convert_pdf_to_markdown(args.pdf_file, args.md_output, args.poppler_path)
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
