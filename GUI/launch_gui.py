"""
Launch script for Ollama-RAG-Sync GUI
Run this to start the graphical user interface
"""

import sys
import os

# Add GUI directory to path
gui_dir = os.path.dirname(os.path.abspath(__file__))
if gui_dir not in sys.path:
    sys.path.insert(0, gui_dir)

def main():
    """Main entry point"""
    print("=" * 70)
    print("Ollama-RAG-Sync Control Center")
    print("=" * 70)
    print()
    
    # Check dependencies
    try:
        from PyQt6.QtWidgets import QApplication
        import requests
    except ImportError as e:
        print("ERROR: Missing required dependencies!")
        print(f"  {e}")
        print()
        print("Please install the requirements:")
        print("  pip install -r requirements.txt")
        print()
        input("Press Enter to exit...")
        sys.exit(1)
    
    # Import and run main window
    try:
        from main_window import main as run_gui
        print("Starting GUI...")
        print()
        print("NOTE: Make sure the following services are running:")
        print("  - FileTracker API (port 10003)")
        print("  - Vectors API (port 10001)")
        print()
        
        run_gui()
    except Exception as e:
        print(f"ERROR: Failed to start GUI: {e}")
        import traceback
        traceback.print_exc()
        input("Press Enter to exit...")
        sys.exit(1)

if __name__ == "__main__":
    main()
