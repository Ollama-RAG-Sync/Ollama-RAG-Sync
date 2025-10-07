"""
Watcher Tab - Manage file watchers for collections
"""

from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QPushButton, QTableWidget,
    QTableWidgetItem, QHeaderView, QLabel, QMessageBox, QDialog,
    QFormLayout, QCheckBox, QSpinBox, QTextEdit, QDialogButtonBox,
    QGroupBox
)
from PyQt6.QtCore import Qt, pyqtSignal, QTimer
from PyQt6.QtGui import QFont, QColor


class WatcherConfigDialog(QDialog):
    """Dialog for configuring a file watcher"""
    
    def __init__(self, parent=None, collection=None):
        super().__init__(parent)
        self.collection = collection
        self.init_ui()
    
    def init_ui(self):
        """Initialize the UI"""
        self.setWindowTitle(f"Configure Watcher: {self.collection.get('name', 'Unknown')}")
        self.setModal(True)
        self.setMinimumWidth(500)
        
        layout = QVBoxLayout(self)
        
        # Collection info
        info_group = QGroupBox("Collection Information")
        info_layout = QFormLayout(info_group)
        info_layout.addRow("Name:", QLabel(self.collection.get('name', '')))
        info_layout.addRow("Folder:", QLabel(self.collection.get('source_folder', '')))
        layout.addWidget(info_group)
        
        # Watch options
        options_group = QGroupBox("Watch Options")
        options_layout = QVBoxLayout(options_group)
        
        self.watch_created_cb = QCheckBox("Watch for created files")
        self.watch_created_cb.setChecked(True)
        options_layout.addWidget(self.watch_created_cb)
        
        self.watch_modified_cb = QCheckBox("Watch for modified files")
        self.watch_modified_cb.setChecked(True)
        options_layout.addWidget(self.watch_modified_cb)
        
        self.watch_deleted_cb = QCheckBox("Watch for deleted files")
        self.watch_deleted_cb.setChecked(True)
        options_layout.addWidget(self.watch_deleted_cb)
        
        self.watch_renamed_cb = QCheckBox("Watch for renamed files")
        self.watch_renamed_cb.setChecked(True)
        options_layout.addWidget(self.watch_renamed_cb)
        
        self.include_subdirs_cb = QCheckBox("Include subdirectories")
        self.include_subdirs_cb.setChecked(True)
        options_layout.addWidget(self.include_subdirs_cb)
        
        layout.addWidget(options_group)
        
        # Processing settings
        processing_group = QGroupBox("Processing Settings")
        processing_layout = QFormLayout(processing_group)
        
        self.interval_spin = QSpinBox()
        self.interval_spin.setRange(5, 300)
        self.interval_spin.setValue(15)
        self.interval_spin.setSuffix(" seconds")
        self.interval_spin.setToolTip("How often to check for changes and process files")
        processing_layout.addRow("Check Interval:", self.interval_spin)
        
        layout.addWidget(processing_group)
        
        # Exclude folders
        exclude_group = QGroupBox("Exclude Folders (Optional)")
        exclude_layout = QVBoxLayout(exclude_group)
        
        exclude_label = QLabel("Folder names to exclude (one per line):")
        exclude_layout.addWidget(exclude_label)
        
        self.exclude_folders_text = QTextEdit()
        self.exclude_folders_text.setPlaceholderText("node_modules\nvendor\n.git")
        self.exclude_folders_text.setMaximumHeight(100)
        exclude_layout.addWidget(self.exclude_folders_text)
        
        layout.addWidget(exclude_group)
        
        # Buttons
        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)
    
    def get_config(self):
        """Get watcher configuration"""
        exclude_text = self.exclude_folders_text.toPlainText().strip()
        exclude_folders = [line.strip() for line in exclude_text.split('\n') if line.strip()]
        
        return {
            'watch_created': self.watch_created_cb.isChecked(),
            'watch_modified': self.watch_modified_cb.isChecked(),
            'watch_deleted': self.watch_deleted_cb.isChecked(),
            'watch_renamed': self.watch_renamed_cb.isChecked(),
            'include_subdirectories': self.include_subdirs_cb.isChecked(),
            'process_interval': self.interval_spin.value(),
            'omit_folders': exclude_folders
        }


class WatcherTab(QWidget):
    """File watcher management tab"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.collections = []
        self.watcher_status = {}
        self.init_ui()
        self.setup_auto_refresh()
    
    def init_ui(self):
        """Initialize the UI"""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)
        
        # Header
        header_layout = QHBoxLayout()
        
        title = QLabel("File Watchers")
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setBold(True)
        title.setFont(title_font)
        header_layout.addWidget(title)
        
        header_layout.addStretch()
        
        # Action buttons
        refresh_btn = QPushButton("🔄 Refresh")
        refresh_btn.clicked.connect(self.refresh)
        header_layout.addWidget(refresh_btn)
        
        stop_all_btn = QPushButton("⏹ Stop All Watchers")
        stop_all_btn.setStyleSheet("QPushButton { background-color: #f44336; }")
        stop_all_btn.clicked.connect(self.stop_all_watchers)
        header_layout.addWidget(stop_all_btn)
        
        layout.addLayout(header_layout)
        
        # Info label
        info_label = QLabel(
            "File watchers monitor collections for changes and automatically trigger processing.\n"
            "Configure and start watchers for collections below."
        )
        info_label.setWordWrap(True)
        info_label.setStyleSheet("QLabel { color: #666; margin: 10px 0; }")
        layout.addWidget(info_label)
        
        # Table
        self.table = QTableWidget()
        self.table.setColumnCount(6)
        self.table.setHorizontalHeaderLabels([
            "Collection ID", "Name", "Source Folder", "Status", "Job ID", "Actions"
        ])
        
        # Set column widths
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(5, QHeaderView.ResizeMode.ResizeToContents)
        
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        
        layout.addWidget(self.table)
        
        # Status summary
        self.status_label = QLabel("Active Watchers: 0")
        status_font = QFont()
        status_font.setBold(True)
        self.status_label.setFont(status_font)
        layout.addWidget(self.status_label)
        
        # Load data
        self.refresh()
    
    def setup_auto_refresh(self):
        """Setup automatic refresh timer"""
        self.refresh_timer = QTimer()
        self.refresh_timer.timeout.connect(self.refresh_status)
        self.refresh_timer.start(5000)  # Refresh every 5 seconds
    
    def refresh(self):
        """Refresh collections and watcher status"""
        if not self.main_window or not self.main_window.api_client:
            return
        
        from worker import APIWorker
        
        # Get collections
        worker = APIWorker(
            "Loading collections",
            self.main_window.api_client.get_collections
        )
        worker.finished.connect(self._on_collections_loaded)
        worker.error.connect(lambda error: QMessageBox.critical(self, "Error", f"Failed to load data:\n{error}"))
        self.main_window.worker_manager.start_worker("watcher_refresh", worker)
    
    def _on_collections_loaded(self, collections):
        """Handle collections loaded"""
        self.collections = collections
        
        # Get watcher status
        self.refresh_status()
        
        self.populate_table()
        self.main_window.status_updated.emit(f"Loaded {len(self.collections)} collections")
    
    def refresh_status(self):
        """Refresh watcher status only"""
        if not self.main_window or not self.main_window.api_client:
            return
        
        from worker import APIWorker
        worker = APIWorker(
            "Checking watcher status",
            self.main_window.api_client.get_processing_status
        )
        worker.finished.connect(self._on_status_loaded)
        worker.error.connect(lambda e: None)  # Silent fail
        self.main_window.worker_manager.start_worker("watcher_status", worker)
    
    def _on_status_loaded(self, jobs):
        """Handle processing status loaded"""
        # Build status map
        self.watcher_status = {}
        for job in jobs:
            job_name = job.get('name', '')
            if job_name.startswith('Watch_Collection_'):
                # Extract collection ID
                try:
                    coll_id = int(job_name.replace('Watch_Collection_', ''))
                    self.watcher_status[coll_id] = {
                        'active': job.get('state') == 'Running',
                        'job_id': job.get('id'),
                        'state': job.get('state')
                    }
                except:
                    pass
        
        # Update status label
        active_count = sum(1 for status in self.watcher_status.values() if status.get('active'))
        self.status_label.setText(f"Active Watchers: {active_count}")
        
        # Update table if it's populated
        if self.table.rowCount() > 0:
            self.update_table_status()
    
    def populate_table(self):
        """Populate the table with collections"""
        # Disable updates during batch operations to prevent UI lag
        self.table.setUpdatesEnabled(False)
        try:
            self.table.setRowCount(0)
            self.table.setRowCount(len(self.collections))  # Pre-allocate all rows
            
            for row, collection in enumerate(self.collections):
                coll_id = collection.get('id')
                
                # Collection ID
                id_item = QTableWidgetItem(str(coll_id))
                id_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                self.table.setItem(row, 0, id_item)
                
                # Name
                self.table.setItem(row, 1, QTableWidgetItem(collection.get('name', '')))
                
                # Source Folder
                self.table.setItem(row, 2, QTableWidgetItem(collection.get('source_folder', '')))
                
                # Status
                status_item = self.create_status_item(coll_id)
                self.table.setItem(row, 3, status_item)
                
                # Job ID
                job_id = self.watcher_status.get(coll_id, {}).get('job_id', '')
                job_item = QTableWidgetItem(str(job_id) if job_id else '-')
                job_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                self.table.setItem(row, 4, job_item)
                
                # Actions
                actions_widget = self.create_actions_widget(collection)
                self.table.setCellWidget(row, 5, actions_widget)
        finally:
            # Re-enable updates and trigger a single repaint
            self.table.setUpdatesEnabled(True)
    
    def create_status_item(self, collection_id):
        """Create status item for a collection"""
        status = self.watcher_status.get(collection_id, {})
        is_active = status.get('active', False)
        
        if is_active:
            status_text = "🟢 Active"
            color = QColor(200, 255, 200)
        else:
            status_text = "⚪ Inactive"
            color = QColor(240, 240, 240)
        
        item = QTableWidgetItem(status_text)
        item.setBackground(color)
        item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
        return item
    
    def update_table_status(self):
        """Update status column in table"""
        for row in range(self.table.rowCount()):
            coll_id_text = self.table.item(row, 0).text()
            if coll_id_text:
                coll_id = int(coll_id_text)
                status_item = self.create_status_item(coll_id)
                self.table.setItem(row, 3, status_item)
                
                # Update job ID
                job_id = self.watcher_status.get(coll_id, {}).get('job_id', '')
                job_item = QTableWidgetItem(str(job_id) if job_id else '-')
                job_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                self.table.setItem(row, 4, job_item)
    
    def create_actions_widget(self, collection):
        """Create actions widget for a collection row"""
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(2, 2, 2, 2)
        layout.setSpacing(2)
        
        coll_id = collection.get('id')
        is_active = self.watcher_status.get(coll_id, {}).get('active', False)
        
        if is_active:
            # Stop button
            stop_btn = QPushButton("⏹")
            stop_btn.setToolTip("Stop Watcher")
            stop_btn.setMaximumWidth(35)
            stop_btn.setStyleSheet("QPushButton { background-color: #f44336; }")
            stop_btn.clicked.connect(lambda: self.stop_watcher(coll_id))
            layout.addWidget(stop_btn)
        else:
            # Start button
            start_btn = QPushButton("▶")
            start_btn.setToolTip("Start Watcher")
            start_btn.setMaximumWidth(35)
            start_btn.setStyleSheet("QPushButton { background-color: #4CAF50; }")
            start_btn.clicked.connect(lambda: self.start_watcher(collection))
            layout.addWidget(start_btn)
            
            # Configure button
            config_btn = QPushButton("⚙")
            config_btn.setToolTip("Configure")
            config_btn.setMaximumWidth(35)
            config_btn.clicked.connect(lambda: self.configure_watcher(collection))
            layout.addWidget(config_btn)
        
        return widget
    
    def configure_watcher(self, collection):
        """Configure watcher for a collection"""
        dialog = WatcherConfigDialog(self, collection)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            # Store config for later use
            config = dialog.get_config()
            self.start_watcher(collection, config)
    
    def start_watcher(self, collection, config=None):
        """Start a file watcher for a collection"""
        coll_id = collection.get('id')
        
        # If no config provided, show config dialog
        if config is None:
            dialog = WatcherConfigDialog(self, collection)
            if dialog.exec() != QDialog.DialogCode.Accepted:
                return
            config = dialog.get_config()
        
        from worker import APIWorker
        worker = APIWorker(
            "Starting watcher",
            self.main_window.api_client.start_collection_watcher,
            collection_id=coll_id,
            watch_created=config['watch_created'],
            watch_modified=config['watch_modified'],
            watch_deleted=config['watch_deleted'],
            watch_renamed=config['watch_renamed'],
            include_subdirectories=config['include_subdirectories'],
            process_interval=config['process_interval'],
            omit_folders=config['omit_folders']
        )
        worker.finished.connect(lambda result: self._on_watcher_started(collection, result))
        worker.error.connect(lambda error: QMessageBox.critical(self, "Error", f"Failed to start watcher:\n{error}"))
        self.main_window.worker_manager.start_worker("start_watcher", worker)
    
    def _on_watcher_started(self, collection, result):
        """Handle watcher started"""
        QMessageBox.information(
            self,
            "Success",
            f"Watcher started for collection '{collection.get('name')}'\n"
            f"Job ID: {result.get('job_id', 'N/A')}"
        )
        
        self.refresh_status()
        self.update_table_status()
    
    def stop_watcher(self, collection_id):
        """Stop a file watcher"""
        from worker import APIWorker
        worker = APIWorker(
            "Stopping watcher",
            self.main_window.api_client.stop_collection_watcher,
            collection_id
        )
        worker.finished.connect(lambda success: self._on_watcher_stopped(success))
        worker.error.connect(lambda error: QMessageBox.critical(self, "Error", f"Failed to stop watcher:\n{error}"))
        self.main_window.worker_manager.start_worker("stop_watcher", worker)
    
    def _on_watcher_stopped(self, success):
        """Handle watcher stopped"""
        if success:
            QMessageBox.information(self, "Success", "Watcher stopped successfully")
            self.refresh_status()
            self.update_table_status()
        else:
            QMessageBox.warning(self, "Warning", "Failed to stop watcher")
    
    def stop_all_watchers(self):
        """Stop all active watchers"""
        active_watchers = [coll_id for coll_id, status in self.watcher_status.items() 
                          if status.get('active')]
        
        if not active_watchers:
            QMessageBox.information(self, "Info", "No active watchers to stop")
            return
        
        reply = QMessageBox.question(
            self,
            "Confirm Stop All",
            f"Are you sure you want to stop all {len(active_watchers)} active watchers?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No
        )
        
        if reply == QMessageBox.StandardButton.Yes:
            # Stop all watchers in background
            from worker import APIWorker
            
            stopped_count = [0]  # Use list to allow modification in closure
            total = len(active_watchers)
            
            def on_watcher_stopped(success):
                if success:
                    stopped_count[0] += 1
                
                if stopped_count[0] + (total - len(active_watchers)) >= total:
                    # All done
                    QMessageBox.information(self, "Success", f"Stopped {stopped_count[0]} watchers")
                    self.refresh_status()
                    self.update_table_status()
            
            for coll_id in active_watchers:
                worker = APIWorker(
                    f"Stopping watcher {coll_id}",
                    self.main_window.api_client.stop_collection_watcher,
                    coll_id
                )
                worker.finished.connect(on_watcher_stopped)
                worker.error.connect(lambda e: on_watcher_stopped(False))
                self.main_window.worker_manager.start_worker(f"stop_watcher_{coll_id}", worker)
