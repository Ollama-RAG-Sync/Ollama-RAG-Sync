"""
Files Tab - View and manage files in collections
"""

from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QPushButton, QTableWidget,
    QTableWidgetItem, QHeaderView, QComboBox, QLabel, QMessageBox,
    QCheckBox, QLineEdit, QMenu
)
from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtGui import QFont, QAction, QColor


class FilesTab(QWidget):
    """Files management tab"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.current_collection_id = None
        self.current_files = []
        self.init_ui()
    
    def init_ui(self):
        """Initialize the UI"""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)
        
        # Header
        header_layout = QHBoxLayout()
        
        title = QLabel("Files Management")
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setBold(True)
        title.setFont(title_font)
        header_layout.addWidget(title)
        
        header_layout.addStretch()
        
        layout.addLayout(header_layout)
        
        # Filters
        filter_layout = QHBoxLayout()
        
        # Collection filter
        filter_layout.addWidget(QLabel("Collection:"))
        self.collection_combo = QComboBox()
        self.collection_combo.addItem("All Collections", None)
        self.collection_combo.currentIndexChanged.connect(self.on_collection_changed)
        filter_layout.addWidget(self.collection_combo)
        
        filter_layout.addSpacing(20)
        
        # Status filters
        self.show_dirty_checkbox = QCheckBox("Unprocessed")
        self.show_dirty_checkbox.setChecked(True)
        self.show_dirty_checkbox.stateChanged.connect(self.apply_filters)
        filter_layout.addWidget(self.show_dirty_checkbox)
        
        self.show_processed_checkbox = QCheckBox("Processed")
        self.show_processed_checkbox.setChecked(True)
        self.show_processed_checkbox.stateChanged.connect(self.apply_filters)
        filter_layout.addWidget(self.show_processed_checkbox)
        
        self.show_deleted_checkbox = QCheckBox("Deleted")
        self.show_deleted_checkbox.stateChanged.connect(self.apply_filters)
        filter_layout.addWidget(self.show_deleted_checkbox)
        
        filter_layout.addStretch()
        
        # Search
        filter_layout.addWidget(QLabel("Search:"))
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("Filter by path...")
        self.search_input.textChanged.connect(self.apply_filters)
        self.search_input.setMinimumWidth(200)
        filter_layout.addWidget(self.search_input)
        
        # Action buttons
        refresh_btn = QPushButton("🔄 Refresh")
        refresh_btn.clicked.connect(self.refresh)
        filter_layout.addWidget(refresh_btn)
        
        layout.addLayout(filter_layout)
        
        # Table
        self.table = QTableWidget()
        self.table.setColumnCount(7)
        self.table.setHorizontalHeaderLabels([
            "ID", "File Path", "Collection", "Status", "Hash", "Modified", "Actions"
        ])
        
        # Set column widths
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(5, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(6, QHeaderView.ResizeMode.ResizeToContents)
        
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.table.customContextMenuRequested.connect(self.show_context_menu)
        
        layout.addWidget(self.table)
        
        # Bulk actions
        bulk_layout = QHBoxLayout()
        bulk_layout.addWidget(QLabel("Bulk Actions:"))
        
        mark_processed_btn = QPushButton("Mark Selected as Processed")
        mark_processed_btn.clicked.connect(lambda: self.bulk_mark_status(False))
        bulk_layout.addWidget(mark_processed_btn)
        
        mark_dirty_btn = QPushButton("Mark Selected as Unprocessed")
        mark_dirty_btn.clicked.connect(lambda: self.bulk_mark_status(True))
        bulk_layout.addWidget(mark_dirty_btn)
        
        delete_selected_btn = QPushButton("Delete Selected")
        delete_selected_btn.setStyleSheet("QPushButton { background-color: #f44336; }")
        delete_selected_btn.clicked.connect(self.bulk_delete)
        bulk_layout.addWidget(delete_selected_btn)
        
        bulk_layout.addStretch()
        
        layout.addLayout(bulk_layout)
        
        # Load data
        self.load_collections()
        self.refresh()
    
    def load_collections(self):
        """Load collections for filter dropdown"""
        if not self.main_window or not self.main_window.api_client:
            return
        
        from worker import APIWorker
        worker = APIWorker(
            "Loading collections",
            self.main_window.api_client.get_collections
        )
        worker.finished.connect(self._on_collections_for_filter_loaded)
        worker.error.connect(lambda e: print(f"Failed to load collections: {e}"))
        self.main_window.worker_manager.start_worker("files_load_collections", worker)
    
    def _on_collections_for_filter_loaded(self, collections):
        """Handle collections loaded for filter"""
        # Clear and repopulate
        self.collection_combo.clear()
        self.collection_combo.addItem("All Collections", None)
        
        for coll in collections:
            self.collection_combo.addItem(
                f"{coll.get('name', '')} (ID: {coll.get('id', '')})",
                coll.get('id')
            )
    
    def set_collection_filter(self, collection_id):
        """Set the collection filter to a specific ID"""
        for i in range(self.collection_combo.count()):
            if self.collection_combo.itemData(i) == collection_id:
                self.collection_combo.setCurrentIndex(i)
                break
    
    def on_collection_changed(self):
        """Handle collection filter change"""
        self.current_collection_id = self.collection_combo.currentData()
        self.refresh()
    
    def refresh(self):
        """Refresh files list"""
        if not self.main_window or not self.main_window.api_client:
            return
        
        from worker import APIWorker
        
        if self.current_collection_id:
            # Get files for specific collection
            worker = APIWorker(
                "Loading files",
                self.main_window.api_client.get_collection_files,
                self.current_collection_id
            )
            worker.finished.connect(lambda files: self._on_files_loaded(files, self.current_collection_id))
            worker.error.connect(self._on_load_error)
            self.main_window.worker_manager.start_worker("files_refresh", worker)
        else:
            # Get all collections first, then get their files
            worker = APIWorker(
                "Loading collections",
                self.main_window.api_client.get_collections
            )
            worker.finished.connect(self._load_all_collections_files)
            worker.error.connect(self._on_load_error)
            self.main_window.worker_manager.start_worker("files_refresh", worker)
    
    def _load_all_collections_files(self, collections):
        """Load files for all collections"""
        # This is a bit more complex - we need to load files for each collection
        # For simplicity, we'll do it sequentially (could be optimized with parallel workers)
        all_files = []
        remaining = len(collections)
        
        def on_collection_files_loaded(coll_id, coll_name, files):
            nonlocal remaining, all_files
            for f in files:
                f['collection_id'] = coll_id
                f['collection_name'] = coll_name
            all_files.extend(files)
            remaining -= 1
            
            if remaining == 0:
                self.current_files = all_files
                self.apply_filters()
                self.main_window.status_updated.emit(f"Loaded {len(all_files)} files")
        
        for coll in collections:
            from worker import APIWorker
            worker = APIWorker(
                f"Loading files for {coll['name']}",
                self.main_window.api_client.get_collection_files,
                coll['id']
            )
            coll_id = coll['id']
            coll_name = coll['name']
            worker.finished.connect(lambda files, c_id=coll_id, c_name=coll_name: on_collection_files_loaded(c_id, c_name, files))
            worker.error.connect(lambda e: None)  # Silent fail for individual collections
            self.main_window.worker_manager.start_worker(f"files_coll_{coll['id']}", worker)
    
    def _on_files_loaded(self, files, collection_id):
        """Handle files loaded for a single collection"""
        # Add collection info
        for f in files:
            f['collection_id'] = collection_id
        
        self.current_files = files
        self.apply_filters()
        self.main_window.status_updated.emit(f"Loaded {len(files)} files")
    
    def _on_load_error(self, error_msg):
        """Handle load error"""
        QMessageBox.critical(self, "Error", f"Failed to load files:\n{error_msg}")
        self.main_window.status_updated.emit("Failed to load files")
    
    def apply_filters(self):
        """Apply filters to the files list"""
        if not self.current_files:
            self.table.setRowCount(0)
            return
        
        # Get filter values
        show_dirty = self.show_dirty_checkbox.isChecked()
        show_processed = self.show_processed_checkbox.isChecked()
        show_deleted = self.show_deleted_checkbox.isChecked()
        search_text = self.search_input.text().lower()
        
        # Filter files
        filtered_files = []
        for f in self.current_files:
            is_dirty = f.get('Dirty', False)
            is_deleted = f.get('Deleted', False)
            
            # Status filter
            if is_deleted and not show_deleted:
                continue
            if not is_deleted:
                if is_dirty and not show_dirty:
                    continue
                if not is_dirty and not show_processed:
                    continue
            
            # Search filter
            if search_text and search_text not in f.get('FilePath', '').lower():
                continue
            
            filtered_files.append(f)
        
        self.populate_table(filtered_files)
    
    def populate_table(self, files):
        """Populate the table with files"""
        # Disable updates during batch operations to prevent UI lag
        self.table.setUpdatesEnabled(False)
        try:
            self.table.setRowCount(0)
            self.table.setRowCount(len(files))  # Pre-allocate all rows
            
            for row, file_data in enumerate(files):
                # ID
                id_item = QTableWidgetItem(str(file_data.get('id', '')))
                id_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                self.table.setItem(row, 0, id_item)
                
                # File Path
                path_item = QTableWidgetItem(file_data.get('FilePath', ''))
                path_item.setToolTip(file_data.get('FilePath', ''))
                self.table.setItem(row, 1, path_item)
                
                # Collection
                coll_name = file_data.get('collection_name', str(file_data.get('collection_id', '')))
                self.table.setItem(row, 2, QTableWidgetItem(coll_name))
                
                # Status
                is_dirty = file_data.get('Dirty', False)
                is_deleted = file_data.get('Deleted', False)
                
                if is_deleted:
                    status = "🗑️ Deleted"
                    color = QColor(255, 200, 200)
                elif is_dirty:
                    status = "⚠️ Unprocessed"
                    color = QColor(255, 255, 200)
                else:
                    status = "✅ Processed"
                    color = QColor(200, 255, 200)
                
                status_item = QTableWidgetItem(status)
                status_item.setBackground(color)
                status_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                self.table.setItem(row, 3, status_item)
                
                # Hash (truncated)
                file_hash = file_data.get('FileHash', '')
                if file_hash and len(file_hash) > 12:
                    file_hash = file_hash[:12] + "..."
                hash_item = QTableWidgetItem(file_hash)
                hash_item.setToolTip(file_data.get('FileHash', ''))
                self.table.setItem(row, 4, hash_item)
                
                # Modified
                modified = file_data.get('LastModified', '')
                if modified:
                    modified = modified.split('T')[0]
                self.table.setItem(row, 5, QTableWidgetItem(modified))
                
                # Actions
                actions_widget = self.create_actions_widget(file_data)
                self.table.setCellWidget(row, 6, actions_widget)
        finally:
            # Re-enable updates and trigger a single repaint
            self.table.setUpdatesEnabled(True)
    
    def create_actions_widget(self, file_data):
        """Create actions widget for a file row"""
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(2, 2, 2, 2)
        layout.setSpacing(2)
        
        file_id = file_data.get('id')
        collection_id = file_data.get('collection_id')
        is_dirty = file_data.get('Dirty', False)
        
        # Mark processed/unprocessed button
        if is_dirty:
            mark_btn = QPushButton("✓")
            mark_btn.setToolTip("Mark as Processed")
            mark_btn.clicked.connect(lambda: self.mark_file_status(collection_id, file_id, False))
        else:
            mark_btn = QPushButton("↺")
            mark_btn.setToolTip("Mark as Unprocessed")
            mark_btn.clicked.connect(lambda: self.mark_file_status(collection_id, file_id, True))
        
        mark_btn.setMaximumWidth(30)
        layout.addWidget(mark_btn)
        
        # Delete button
        delete_btn = QPushButton("🗑️")
        delete_btn.setToolTip("Delete")
        delete_btn.setMaximumWidth(30)
        delete_btn.setStyleSheet("QPushButton { background-color: #f44336; }")
        delete_btn.clicked.connect(lambda: self.delete_file(collection_id, file_id))
        layout.addWidget(delete_btn)
        
        return widget
    
    def mark_file_status(self, collection_id, file_id, dirty):
        """Mark a file's processing status"""
        from worker import APIWorker
        worker = APIWorker(
            "Updating file status",
            self.main_window.api_client.update_file_status,
            collection_id, file_id, dirty
        )
        worker.finished.connect(lambda result: self._on_file_status_updated())
        worker.error.connect(lambda error: QMessageBox.critical(self, "Error", f"Failed to update file status:\n{error}"))
        self.main_window.worker_manager.start_worker("mark_file_status", worker)
    
    def _on_file_status_updated(self):
        """Handle file status updated"""
        self.main_window.status_updated.emit("File status updated")
        self.refresh()
    
    def delete_file(self, collection_id, file_id):
        """Delete a file"""
        reply = QMessageBox.question(
            self,
            "Confirm Delete",
            "Are you sure you want to delete this file?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No
        )
        
        if reply == QMessageBox.StandardButton.Yes:
            from worker import APIWorker
            worker = APIWorker(
                "Deleting file",
                self.main_window.api_client.delete_file_from_collection,
                collection_id, file_id
            )
            worker.finished.connect(lambda result: self._on_file_deleted())
            worker.error.connect(lambda error: QMessageBox.critical(self, "Error", f"Failed to delete file:\n{error}"))
            self.main_window.worker_manager.start_worker("delete_file", worker)
    
    def _on_file_deleted(self):
        """Handle file deleted"""
        self.main_window.status_updated.emit("File deleted")
        self.refresh()
    
    def bulk_mark_status(self, dirty):
        """Mark multiple files' status"""
        selected_rows = set(item.row() for item in self.table.selectedItems())
        if not selected_rows:
            QMessageBox.warning(self, "No Selection", "Please select files first")
            return
        
        # Collect file IDs and collection IDs
        files_to_update = []
        for row in selected_rows:
            try:
                file_id = int(self.table.item(row, 0).text())
                collection_id = self.current_collection_id
                
                if not collection_id:
                    # Need to get collection from data
                    # For simplicity, skip for now or enhance later
                    continue
                
                files_to_update.append((collection_id, file_id))
            except:
                pass
        
        if not files_to_update:
            QMessageBox.warning(self, "No Valid Selection", "No valid files selected")
            return
        
        # Update in background
        from worker import APIWorker
        
        success_count = [0]
        total = len(files_to_update)
        remaining = [total]
        
        def on_file_updated(result):
            success_count[0] += 1
            remaining[0] -= 1
            if remaining[0] == 0:
                QMessageBox.information(self, "Success", f"Updated {success_count[0]} files")
                self.refresh()
        
        def on_file_error(error):
            remaining[0] -= 1
            if remaining[0] == 0:
                QMessageBox.information(self, "Partial Success", f"Updated {success_count[0]}/{total} files")
                self.refresh()
        
        for collection_id, file_id in files_to_update:
            worker = APIWorker(
                f"Updating file {file_id}",
                self.main_window.api_client.update_file_status,
                collection_id, file_id, dirty
            )
            worker.finished.connect(on_file_updated)
            worker.error.connect(on_file_error)
            self.main_window.worker_manager.start_worker(f"bulk_update_{file_id}", worker)
    
    def bulk_delete(self):
        """Delete multiple files"""
        selected_rows = set(item.row() for item in self.table.selectedItems())
        if not selected_rows:
            QMessageBox.warning(self, "No Selection", "Please select files first")
            return
        
        reply = QMessageBox.question(
            self,
            "Confirm Bulk Delete",
            f"Are you sure you want to delete {len(selected_rows)} files?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No
        )
        
        if reply == QMessageBox.StandardButton.Yes:
            # Collect file IDs and collection IDs
            files_to_delete = []
            for row in selected_rows:
                try:
                    file_id = int(self.table.item(row, 0).text())
                    collection_id = self.current_collection_id
                    
                    if not collection_id:
                        continue
                    
                    files_to_delete.append((collection_id, file_id))
                except:
                    pass
            
            if not files_to_delete:
                QMessageBox.warning(self, "No Valid Selection", "No valid files selected")
                return
            
            # Delete in background
            from worker import APIWorker
            
            success_count = [0]
            total = len(files_to_delete)
            remaining = [total]
            
            def on_file_deleted(result):
                success_count[0] += 1
                remaining[0] -= 1
                if remaining[0] == 0:
                    QMessageBox.information(self, "Success", f"Deleted {success_count[0]} files")
                    self.refresh()
            
            def on_file_error(error):
                remaining[0] -= 1
                if remaining[0] == 0:
                    QMessageBox.information(self, "Partial Success", f"Deleted {success_count[0]}/{total} files")
                    self.refresh()
            
            for collection_id, file_id in files_to_delete:
                worker = APIWorker(
                    f"Deleting file {file_id}",
                    self.main_window.api_client.delete_file_from_collection,
                    collection_id, file_id
                )
                worker.finished.connect(on_file_deleted)
                worker.error.connect(on_file_error)
                self.main_window.worker_manager.start_worker(f"bulk_delete_{file_id}", worker)
    
    def show_context_menu(self, position):
        """Show context menu for table"""
        row = self.table.rowAt(position.y())
        if row < 0:
            return
        
        file_id = int(self.table.item(row, 0).text())
        
        menu = QMenu(self)
        
        mark_processed_action = QAction("✅ Mark as Processed", self)
        mark_processed_action.triggered.connect(
            lambda: self.mark_file_status(self.current_collection_id, file_id, False)
        )
        menu.addAction(mark_processed_action)
        
        mark_dirty_action = QAction("⚠️ Mark as Unprocessed", self)
        mark_dirty_action.triggered.connect(
            lambda: self.mark_file_status(self.current_collection_id, file_id, True)
        )
        menu.addAction(mark_dirty_action)
        
        menu.addSeparator()
        
        delete_action = QAction("🗑️ Delete", self)
        delete_action.triggered.connect(
            lambda: self.delete_file(self.current_collection_id, file_id)
        )
        menu.addAction(delete_action)
        
        menu.exec(self.table.viewport().mapToGlobal(position))
