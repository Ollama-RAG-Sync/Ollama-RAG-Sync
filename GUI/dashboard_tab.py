"""
Dashboard Tab - System overview and statistics
"""

from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QGridLayout,
    QLabel, QFrame, QPushButton, QGroupBox, QScrollArea, QTextEdit
)
from PyQt6.QtCore import Qt, pyqtSignal, QTimer
from PyQt6.QtGui import QFont
import time


class StatCard(QFrame):
    """Card widget for displaying statistics"""
    
    def __init__(self, title: str, value: str = "0", icon: str = "📊", parent=None):
        super().__init__(parent)
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setStyleSheet("""
            QFrame {
                background-color: white;
                border: 1px solid #e0e0e0;
                border-radius: 8px;
                padding: 15px;
            }
        """)
        
        layout = QVBoxLayout(self)
        
        # Icon and title
        header_layout = QHBoxLayout()
        icon_label = QLabel(icon)
        icon_font = QFont()
        icon_font.setPointSize(24)
        icon_label.setFont(icon_font)
        header_layout.addWidget(icon_label)
        
        title_label = QLabel(title)
        title_font = QFont()
        title_font.setBold(True)
        title_font.setPointSize(11)
        title_label.setFont(title_font)
        header_layout.addWidget(title_label)
        header_layout.addStretch()
        
        layout.addLayout(header_layout)
        
        # Value
        self.value_label = QLabel(value)
        value_font = QFont()
        value_font.setPointSize(28)
        value_font.setBold(True)
        self.value_label.setFont(value_font)
        self.value_label.setStyleSheet("color: #2196F3;")
        layout.addWidget(self.value_label)
        
        layout.addStretch()
    
    def set_value(self, value: str):
        """Update the displayed value"""
        self.value_label.setText(str(value))


class DashboardTab(QWidget):
    """Dashboard tab showing system overview"""
    
    refresh_requested = pyqtSignal()
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.last_refresh_time = 0  # Track last refresh
        self.cache_duration = 30  # Cache for 30 seconds
        self.is_loading = False  # Prevent concurrent loads
        self.init_ui()
    
    def init_ui(self):
        """Initialize the UI"""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(20)
        
        # Title
        title = QLabel("System Dashboard")
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setBold(True)
        title.setFont(title_font)
        layout.addWidget(title)
        
        # Statistics cards
        stats_layout = QGridLayout()
        stats_layout.setSpacing(15)
        
        self.collections_card = StatCard("Collections", "0", "📁")
        self.files_card = StatCard("Total Files", "0", "📄")
        self.dirty_card = StatCard("Unprocessed", "0", "⚠️")
        self.processed_card = StatCard("Processed", "0", "✅")
        self.watchers_card = StatCard("Active Watchers", "0", "👁")
        self.jobs_card = StatCard("Running Jobs", "0", "⚙️")
        
        stats_layout.addWidget(self.collections_card, 0, 0)
        stats_layout.addWidget(self.files_card, 0, 1)
        stats_layout.addWidget(self.dirty_card, 0, 2)
        stats_layout.addWidget(self.processed_card, 1, 0)
        stats_layout.addWidget(self.watchers_card, 1, 1)
        stats_layout.addWidget(self.jobs_card, 1, 2)
        
        layout.addLayout(stats_layout)
        
        # API Status Section
        api_group = QGroupBox("API Status")
        api_group.setStyleSheet("""
            QGroupBox {
                font-weight: bold;
                border: 2px solid #e0e0e0;
                border-radius: 8px;
                margin-top: 10px;
                padding-top: 10px;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 10px;
                padding: 0 5px;
            }
        """)
        api_layout = QVBoxLayout(api_group)
        
        self.filetracker_info = QLabel("FileTracker API: Checking...")
        self.vectors_info = QLabel("Vectors API: Checking...")
        
        api_layout.addWidget(self.filetracker_info)
        api_layout.addWidget(self.vectors_info)
        
        layout.addWidget(api_group)
        
        # System Info Section
        system_group = QGroupBox("System Information")
        system_group.setStyleSheet(api_group.styleSheet())
        system_layout = QVBoxLayout(system_group)
        
        self.system_info_text = QTextEdit()
        self.system_info_text.setReadOnly(True)
        self.system_info_text.setMaximumHeight(150)
        self.system_info_text.setStyleSheet("""
            QTextEdit {
                background-color: #f9f9f9;
                font-family: 'Consolas', 'Courier New', monospace;
            }
        """)
        system_layout.addWidget(self.system_info_text)
        
        layout.addWidget(system_group)
        
        # Action buttons
        actions_layout = QHBoxLayout()
        
        self.refresh_btn = QPushButton("🔄 Refresh Dashboard")
        self.refresh_btn.clicked.connect(self.refresh)
        actions_layout.addWidget(self.refresh_btn)
        
        force_refresh_btn = QPushButton("↻ Force Refresh")
        force_refresh_btn.setToolTip("Bypass cache and refresh immediately")
        force_refresh_btn.clicked.connect(self.force_refresh)
        actions_layout.addWidget(force_refresh_btn)
        
        actions_layout.addStretch()
        
        layout.addLayout(actions_layout)
        layout.addStretch()
        
        # Initial load
        self.refresh()
    
    def force_refresh(self):
        """Force refresh bypassing cache"""
        self.last_refresh_time = 0  # Reset cache
        self.refresh()
    
    def refresh(self):
        """Refresh dashboard data with caching"""
        if not self.main_window or not self.main_window.api_client:
            return
        
        # Check if we're already loading
        if self.is_loading:
            self.main_window.status_updated.emit("Dashboard refresh already in progress...")
            return
        
        # Check cache - don't refresh if data is fresh (< 30 seconds old)
        current_time = time.time()
        if current_time - self.last_refresh_time < self.cache_duration:
            time_since_refresh = int(current_time - self.last_refresh_time)
            self.main_window.status_updated.emit(f"Using cached data ({time_since_refresh}s ago)")
            return
        
        self.is_loading = True
        api = self.main_window.api_client
        
        # Get FileTracker statistics in background
        from worker import APIWorker
        
        ft_stats_worker = APIWorker(
            "Loading FileTracker statistics",
            api.get_filetracker_statistics
        )
        ft_stats_worker.finished.connect(self._on_ft_stats_loaded)
        ft_stats_worker.error.connect(self._on_ft_stats_error)
        self.main_window.worker_manager.start_worker("ft_stats", ft_stats_worker)
        
        # Get processing jobs status in background
        jobs_worker = APIWorker(
            "Loading processing jobs",
            api.get_processing_status
        )
        jobs_worker.finished.connect(self._on_jobs_loaded)
        jobs_worker.error.connect(lambda e: None)  # Silent fail
        self.main_window.worker_manager.start_worker("jobs_status", jobs_worker)
        
        # Get Vectors status in background
        v_status_worker = APIWorker(
            "Loading Vectors status",
            api.get_vectors_status
        )
        v_status_worker.finished.connect(lambda status: self._on_vectors_status_loaded(status, api))
        v_status_worker.error.connect(self._on_vectors_error)
        self.main_window.worker_manager.start_worker("v_status", v_status_worker)
    
    def _on_ft_stats_loaded(self, ft_stats):
        """Handle FileTracker statistics loaded"""
        self.collections_card.set_value(ft_stats.get('collections_count', 0))
        self.files_card.set_value(ft_stats.get('total_files', 0))
        self.dirty_card.set_value(ft_stats.get('dirty_files', 0))
        self.processed_card.set_value(ft_stats.get('processed_files', 0))
        
        self.filetracker_info.setText(
            f"✅ FileTracker API: Online | Database: {ft_stats.get('database_path', 'N/A')}"
        )
        self.filetracker_info.setStyleSheet("color: green;")
        
        # Update cache timestamp and mark loading complete
        self.last_refresh_time = time.time()
        self.is_loading = False
        self.main_window.status_updated.emit("Dashboard refreshed")
    
    def _on_ft_stats_error(self, error_msg):
        """Handle FileTracker statistics error"""
        self.filetracker_info.setText(f"❌ FileTracker API: Offline - {error_msg}")
        self.filetracker_info.setStyleSheet("color: red;")
        
        # Mark loading complete even on error
        self.is_loading = False
        self.main_window.status_updated.emit("Failed to load statistics")
    
    def _on_jobs_loaded(self, jobs):
        """Handle processing jobs loaded"""
        active_jobs = [j for j in jobs if j.get('state') == 'Running']
        self.jobs_card.set_value(len(active_jobs))
        
        # Count watchers
        watchers = [j for j in jobs if j.get('name', '').startswith('Watch_Collection_')]
        self.watchers_card.set_value(len(watchers))
    
    def _on_vectors_status_loaded(self, v_status, api):
        """Handle Vectors status loaded"""
        # Get Vectors statistics too
        from worker import APIWorker
        v_stats_worker = APIWorker(
            "Loading Vectors statistics",
            api.get_vectors_statistics
        )
        v_stats_worker.finished.connect(lambda v_stats: self._display_vectors_info(v_status, v_stats))
        v_stats_worker.error.connect(lambda e: self._display_vectors_info(v_status, {}))
        self.main_window.worker_manager.start_worker("v_stats", v_stats_worker)
    
    def _display_vectors_info(self, v_status, v_stats):
        """Display Vectors information"""
        info_text = f"""Vectors API Status:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Status: {v_status.get('status', 'Unknown')}
ChromaDB Path: {v_status.get('chromaDbPath', 'N/A')}
Ollama URL: {v_status.get('ollamaUrl', 'N/A')}
Embedding Model: {v_status.get('embeddingModel', 'N/A')}
Default Collection: {v_status.get('defaultCollectionName', 'default')}
Chunk Size: {v_status.get('defaultChunkSize', 20)}
Chunk Overlap: {v_status.get('defaultChunkOverlap', 2)}
Max Workers: {v_status.get('defaultMaxWorkers', 5)}
"""
        
        self.vectors_info.setText("✅ Vectors API: Online")
        self.vectors_info.setStyleSheet("color: green;")
        self.system_info_text.setPlainText(info_text)
    
    def _on_vectors_error(self, error_msg):
        """Handle Vectors status error"""
        self.vectors_info.setText(f"❌ Vectors API: Offline - {error_msg}")
        self.vectors_info.setStyleSheet("color: red;")
