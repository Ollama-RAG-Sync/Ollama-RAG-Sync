"""
Main Window for Ollama-RAG-Sync GUI
Comprehensive GUI application for managing RAG operations
"""

import sys
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QTabWidget, QLabel, QPushButton, QMessageBox, QStatusBar,
    QSplitter, QFrame
)
from PyQt6.QtCore import Qt, QTimer, pyqtSignal
from PyQt6.QtGui import QIcon, QFont

from api_client import APIClient, APIClientException
from collections_tab import CollectionsTab
from files_tab import FilesTab
from search_tab import SearchTab
from watcher_tab import WatcherTab
from dashboard_tab import DashboardTab
from worker import WorkerManager, StatusBarManager


class MainWindow(QMainWindow):
    """Main application window"""
    
    # Signals
    status_updated = pyqtSignal(str)
    
    def __init__(self):
        super().__init__()
        self.api_client = None
        self.worker_manager = WorkerManager()
        self.status_bar_manager = None  # Initialize after status bar is created
        self.init_ui()
        self.init_api_client()
        self.setup_auto_refresh()
        
    def init_ui(self):
        """Initialize the user interface"""
        self.setWindowTitle("Ollama-RAG-Sync Control Center")
        self.setGeometry(100, 100, 1400, 900)
        
        # Apply modern styling
        self.setStyleSheet("""
            QMainWindow {
                background-color: #f5f5f5;
            }
            QTabWidget::pane {
                border: 1px solid #cccccc;
                background-color: white;
                border-radius: 4px;
            }
            QTabBar::tab {
                background-color: #e0e0e0;
                padding: 10px 20px;
                margin-right: 2px;
                border-top-left-radius: 4px;
                border-top-right-radius: 4px;
            }
            QTabBar::tab:selected {
                background-color: white;
                border-bottom: 2px solid #2196F3;
            }
            QTabBar::tab:hover {
                background-color: #eeeeee;
            }
            QPushButton {
                background-color: #2196F3;
                color: white;
                border: none;
                padding: 8px 16px;
                border-radius: 4px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #1976D2;
            }
            QPushButton:pressed {
                background-color: #0D47A1;
            }
            QPushButton:disabled {
                background-color: #cccccc;
                color: #666666;
            }
            QLabel {
                color: #333333;
            }
            QLineEdit, QTextEdit, QSpinBox, QDoubleSpinBox {
                border: 1px solid #cccccc;
                border-radius: 4px;
                padding: 6px;
                background-color: white;
            }
            QLineEdit:focus, QTextEdit:focus {
                border: 2px solid #2196F3;
            }
            QTableWidget {
                border: 1px solid #cccccc;
                gridline-color: #e0e0e0;
                background-color: white;
            }
            QHeaderView::section {
                background-color: #f5f5f5;
                padding: 8px;
                border: none;
                border-bottom: 2px solid #2196F3;
                font-weight: bold;
            }
        """)
        
        # Create central widget
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        
        # Main layout
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(10, 10, 10, 10)
        
        # Header
        header = self.create_header()
        main_layout.addWidget(header)
        
        # Tab widget
        self.tabs = QTabWidget()
        self.tabs.setTabPosition(QTabWidget.TabPosition.North)
        
        # Create tabs (placeholders for now)
        self.dashboard_tab = DashboardTab(self)
        self.collections_tab = CollectionsTab(self)
        self.files_tab = FilesTab(self)
        self.search_tab = SearchTab(self)
        self.watcher_tab = WatcherTab(self)
        
        # Add tabs
        self.tabs.addTab(self.dashboard_tab, "📊 Dashboard")
        self.tabs.addTab(self.collections_tab, "📁 Collections")
        self.tabs.addTab(self.files_tab, "📄 Files")
        self.tabs.addTab(self.search_tab, "🔍 Search")
        self.tabs.addTab(self.watcher_tab, "👁 Watchers")
        
        main_layout.addWidget(self.tabs)
        
        # Status bar
        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)
        self.status_bar.showMessage("Ready")
        
        # Initialize status bar manager
        self.status_bar_manager = StatusBarManager(self.status_bar)
        
        # Connect signals
        self.status_updated.connect(self.update_status_bar)
        
    def create_header(self) -> QFrame:
        """Create the application header"""
        header = QFrame()
        header.setFrameShape(QFrame.Shape.StyledPanel)
        header.setStyleSheet("""
            QFrame {
                background-color: #2196F3;
                border-radius: 8px;
                padding: 10px;
            }
            QLabel {
                color: white;
            }
        """)
        
        layout = QHBoxLayout(header)
        
        # Title
        title = QLabel("Ollama-RAG-Sync Control Center")
        title_font = QFont()
        title_font.setPointSize(18)
        title_font.setBold(True)
        title.setFont(title_font)
        layout.addWidget(title)
        
        layout.addStretch()
        
        # API Status indicators
        self.filetracker_status_label = QLabel("FileTracker: ●")
        self.vectors_status_label = QLabel("Vectors: ●")
        
        status_font = QFont()
        status_font.setPointSize(11)
        self.filetracker_status_label.setFont(status_font)
        self.vectors_status_label.setFont(status_font)
        
        layout.addWidget(self.filetracker_status_label)
        layout.addWidget(self.vectors_status_label)
        
        # Refresh button
        refresh_btn = QPushButton("🔄 Refresh")
        refresh_btn.setStyleSheet("""
            QPushButton {
                background-color: white;
                color: #2196F3;
            }
            QPushButton:hover {
                background-color: #f0f0f0;
            }
        """)
        refresh_btn.clicked.connect(self.refresh_all)
        layout.addWidget(refresh_btn)
        
        return header
    
    def init_api_client(self):
        """Initialize the API client with default settings"""
        try:
            self.api_client = APIClient()
            self.update_api_status()
            self.status_updated.emit("Connected to APIs")
        except Exception as e:
            QMessageBox.critical(
                self,
                "API Connection Error",
                f"Failed to initialize API client:\n{str(e)}"
            )
    
    def setup_auto_refresh(self):
        """Setup automatic refresh timers"""
        # Refresh API status every 5 seconds
        self.status_timer = QTimer()
        self.status_timer.timeout.connect(self.update_api_status)
        self.status_timer.start(5000)
        
        # Refresh dashboard every 10 seconds
        self.dashboard_timer = QTimer()
        self.dashboard_timer.timeout.connect(self.refresh_dashboard)
        self.dashboard_timer.start(10000)
    
    def update_api_status(self):
        """Update API connection status indicators"""
        if not self.api_client:
            return
        
        # Check FileTracker in background
        from worker import APIWorker
        ft_worker = APIWorker(
            "Checking FileTracker API",
            self.api_client.check_filetracker_health
        )
        ft_worker.finished.connect(self._on_filetracker_status)
        ft_worker.error.connect(lambda e: self._on_filetracker_status(False))
        self.worker_manager.start_worker("ft_health_check", ft_worker)
        
        # Check Vectors in background
        v_worker = APIWorker(
            "Checking Vectors API",
            self.api_client.check_vectors_health
        )
        v_worker.finished.connect(self._on_vectors_status)
        v_worker.error.connect(lambda e: self._on_vectors_status(False))
        self.worker_manager.start_worker("v_health_check", v_worker)
    
    def _on_filetracker_status(self, ft_healthy):
        """Handle FileTracker status check result"""
        if ft_healthy:
            self.filetracker_status_label.setText("FileTracker: 🟢")
            self.filetracker_status_label.setToolTip("FileTracker API is online")
        else:
            self.filetracker_status_label.setText("FileTracker: 🔴")
            self.filetracker_status_label.setToolTip("FileTracker API is offline")
    
    def _on_vectors_status(self, v_healthy):
        """Handle Vectors status check result"""
        if v_healthy:
            self.vectors_status_label.setText("Vectors: 🟢")
            self.vectors_status_label.setToolTip("Vectors API is online")
        else:
            self.vectors_status_label.setText("Vectors: 🔴")
            self.vectors_status_label.setToolTip("Vectors API is offline")
    
    def refresh_all(self):
        """Refresh all tabs"""
        self.status_updated.emit("Refreshing...")
        try:
            # Refresh current tab
            current_tab = self.tabs.currentWidget()
            if hasattr(current_tab, 'refresh'):
                current_tab.refresh()
            
            # Update API status
            self.update_api_status()
            
            self.status_updated.emit("Refresh completed")
        except Exception as e:
            self.status_updated.emit(f"Refresh failed: {str(e)}")
            QMessageBox.warning(self, "Refresh Error", f"Failed to refresh:\n{str(e)}")
    
    def refresh_dashboard(self):
        """Refresh dashboard if it's the current tab"""
        if self.tabs.currentWidget() == self.dashboard_tab:
            try:
                self.dashboard_tab.refresh()
            except:
                pass
    
    def update_status_bar(self, message: str):
        """Update the status bar message"""
        self.status_bar.showMessage(message, 5000)
    
    def get_api_client(self) -> APIClient:
        """Get the API client instance"""
        return self.api_client
    
    def closeEvent(self, event):
        """Handle window close event"""
        reply = QMessageBox.question(
            self,
            "Exit Application",
            "Are you sure you want to exit?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No
        )
        
        if reply == QMessageBox.StandardButton.Yes:
            # Cancel all background workers
            self.worker_manager.cancel_all()
            
            # Stop timers
            self.status_timer.stop()
            self.dashboard_timer.stop()
            event.accept()
        else:
            event.ignore()


def main():
    """Main entry point"""
    app = QApplication(sys.argv)
    app.setApplicationName("Ollama-RAG-Sync")
    app.setOrganizationName("Ollama-RAG-Sync")
    
    window = MainWindow()
    window.show()
    
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
