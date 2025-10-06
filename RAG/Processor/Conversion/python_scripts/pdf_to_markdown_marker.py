#!/usr/bin/env python3
"""
PDF to Markdown converter using Marker library.
This script converts a PDF file to Markdown format using the Marker library.
"""

import sys
import os
import argparse
from marker.converters.pdf import PdfConverter
from marker.models import create_model_dict
from marker.config.parser import ConfigParser


def convert_pdf_to_markdown(pdf_file: str, md_output: str) -> bool:
    """
    Convert a PDF file to Markdown format using Marker library.
    
    Args:
        pdf_file: Path to the input PDF file
        md_output: Path to the output Markdown file
        
    Returns:
        bool: True if conversion was successful, False otherwise
    """
    try:
        # Setup configuration
        config = {
            "disable_image_extraction": "true",
            "output_format": "markdown"
        }
        config_parser = ConfigParser(config)

        # Initialize the converter
        converter = PdfConverter(
            config=config_parser.generate_config_dict(),
            artifact_dict=create_model_dict(),
            processor_list=config_parser.get_processors(),
            renderer=config_parser.get_renderer()
        )
    
        # Convert the PDF
        print(f"Processing {pdf_file}...")
        rendered = converter(pdf_file)
        
        # Save as Markdown
        print(f"Saving Markdown to {md_output}...")
        with open(md_output, 'w', encoding='utf-8') as f:
            f.write(rendered.markdown)
    
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
        description="Convert PDF to Markdown using Marker library"
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
