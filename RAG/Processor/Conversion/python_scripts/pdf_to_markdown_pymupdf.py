#!/usr/bin/env python3
"""
PDF to Markdown converter using PyMuPDF.
This script converts a PDF file to Markdown format using PyMuPDF (fitz).
"""

import sys
import os
import argparse
import fitz  # PyMuPDF


def convert_pdf_to_markdown(pdf_file: str, md_output: str) -> bool:
    """
    Convert a PDF file to Markdown format using PyMuPDF.
    
    Args:
        pdf_file: Path to the input PDF file
        md_output: Path to the output Markdown file
        
    Returns:
        bool: True if conversion was successful, False otherwise
    """
    try:
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
                structured_text += block[4] + "\n\n"
            
            full_text.append(structured_text if structured_text.strip() else text)
        
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


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description="Convert PDF to Markdown using PyMuPDF"
    )
    parser.add_argument(
        "pdf_file",
        help="Path to the input PDF file"
    )
    parser.add_argument(
        "md_output",
        help="Path to the output Markdown file"
    )
    
    args = parser.parse_args()
    
    # Validate input file exists
    if not os.path.exists(args.pdf_file):
        print(f"Error: PDF file not found: {args.pdf_file}", file=sys.stderr)
        sys.exit(1)
    
    # Perform conversion
    success = convert_pdf_to_markdown(args.pdf_file, args.md_output)
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
