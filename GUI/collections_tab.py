"""
Collections Tab - Manage document collections
"""

from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QPushButton, QTableWidget,
    QTableWidgetItem, QHeaderView, QDialog, QFormLayout, QLineEdit,
    QTextEdit, QDialogButtonBox, QMessageBox, QFileDialog, QLabel,
    QMenu
)
from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtGui import QFont, QAction


class CollectionDialog(QDialog):
    """Dialog for creating/editing collections"""
    
    def __init__(self, parent=None, collection_data=None):
        super().__init__(parent)
        self.collection_data = collection_data
        self.is_edit = collection_data is not None
        self.init_ui()
        
        if self.is_edit:
            self.load_collection_data()
    
    def init_ui(self):
        """Initialize the UI"""
        self.setWindowTitle("Edit Collection" if self.is_edit else "Create Collection")
        self.setModal(True)
        self.setMinimumWidth(500)
        
        layout = QVBoxLayout(self)
        
        # Form
        form = QFormLayout()
        
        self.name_input = QLineEdit()
        self.name_input.setPlaceholderText("e.g., TechDocs")
        form.addRow("Name:", self.name_input)
        
        # Source folder with browse button
        folder_layout = QHBoxLayout()
        self.folder_input = QLineEdit()
        self.folder_input.setPlaceholderText("C:\\Documents\\Tech")
        folder_layout.addWidget(self.folder_input)
        
        browse_btn = QPushButton("Browse...")
        browse_btn.clicked.connect(self.browse_folder)
        folder_layout.addWidget(browse_btn)
        
        form.addRow("Source Folder:", folder_layout)
        
        self.description_input = QTextEdit()
        self.description_input.setPlaceholderText("Optional description")
        self.description_input.setMaximumHeight(80)
        form.addRow("Description:", self.description_input)
        
        self.extensions_input = QLineEdit()
        self.extensions_input.setPlaceholderText(".txt,.md,.pdf")
        self.extensions_input.setToolTip("Comma-separated file extensions to include")
        form.addRow("Include Extensions:", self.extensions_input)
        
        self.exclude_folders_input = QLineEdit()
        self.exclude_folders_input.setPlaceholderText("node_modules,vendor")
        self.exclude_folders_input.setToolTip("Comma-separated folder names to exclude")
        form.addRow("Exclude Folders:", self.exclude_folders_input)
        
        layout.addLayout(form)
        
        # Buttons
        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)
    
    def browse_folder(self):
        """Browse for a folder"""
        folder = QFileDialog.getExistingDirectory(
            self,
            "Select Source Folder",
            self.folder_input.text()
        )
        if folder:
            self.folder_input.setText(folder)
    
    def load_collection_data(self):
        """Load existing collection data into form"""
        if not self.collection_data:
            return
        
        self.name_input.setText(self.collection_data.get('name', ''))
        self.folder_input.setText(self.collection_data.get('source_folder', ''))
        self.description_input.setPlainText(self.collection_data.get('description', ''))
        self.extensions_input.setText(self.collection_data.get('include_extensions', ''))
        self.exclude_folders_input.setText(self.collection_data.get('exclude_folders', ''))
    
    def get_data(self):
        """Get form data"""
        return {
            'name': self.name_input.text().strip(),
            'sourceFolder': self.folder_input.text().strip(),
            'description': self.description_input.toPlainText().strip(),
            'includeExtensions': self.extensions_input.text().strip(),
            'excludeFolders': self.exclude_folders_input.text().strip()
        }


class CollectionsTab(QWidget):
    """Collections management tab"""
    
    collection_selected = pyqtSignal(int)  # Emits collection ID
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.current_collections = []
        self.init_ui()
    
    def init_ui(self):
        """Initialize the UI"""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)
        
        # Header
        header_layout = QHBoxLayout()
        
        title = QLabel("Collections Management")
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setBold(True)
        title.setFont(title_font)
        header_layout.addWidget(title)
        
        header_layout.addStretch()
        
        # Action buttons
        create_btn = QPushButton("➕ Create Collection")
        create_btn.clicked.connect(self.create_collection)
        header_layout.addWidget(create_btn)
        
        refresh_btn = QPushButton("🔄 Refresh")
        refresh_btn.clicked.connect(self.refresh)
        header_layout.addWidget(refresh_btn)
        
        layout.addLayout(header_layout)
        
        # Table
        self.table = QTableWidget()
        self.table.setColumnCount(7)
        self.table.setHorizontalHeaderLabels([
            "ID", "Name", "Source Folder", "Extensions", "Files", "Created", "Actions"
        ])
        
        # Set column widths
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(5, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(6, QHeaderView.ResizeMode.ResizeToContents)
        
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.table.customContextMenuRequested.connect(self.show_context_menu)
        self.table.cellDoubleClicked.connect(self.on_row_double_clicked)
        
        layout.addWidget(self.table)
        
        # Load data
        self.refresh()
    
    def refresh(self):
        """Refresh collections list"""
        if not self.main_window or not self.main_window.api_client:
            return
        
        from worker import APIWorker
        worker = APIWorker(
            "Loading collections",
            self.main_window.api_client.get_collections
        )
        worker.started.connect(lambda name: self.main_window.status_updated.emit(name))
        worker.finished.connect(self._on_collections_loaded)
        worker.error.connect(self._on_load_error)
        self.main_window.worker_manager.start_worker("collections_refresh", worker)
    
    def _on_collections_loaded(self, collections):
        """Handle collections loaded"""
        self.current_collections = collections
        self.populate_table(collections)
        self.main_window.status_updated.emit(f"Loaded {len(collections)} collections")
    
    def _on_load_error(self, error_msg):
        """Handle load error"""
        QMessageBox.critical(self, "Error", f"Failed to load collections:\n{error_msg}")
        self.main_window.status_updated.emit("Failed to load collections")
    
    def populate_table(self, collections):
        """Populate the table with collections"""
        # Disable updates during batch operations to prevent UI lag
        self.table.setUpdatesEnabled(False)
        try:
            self.table.setRowCount(0)
            self.table.setRowCount(len(collections))  # Pre-allocate all rows
            
            for row, collection in enumerate(collections):
                # ID
                id_item = QTableWidgetItem(str(collection.get('id', '')))
                id_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                self.table.setItem(row, 0, id_item)
                
                # Name
                self.table.setItem(row, 1, QTableWidgetItem(collection.get('name', '')))
                
                # Source Folder
                self.table.setItem(row, 2, QTableWidgetItem(collection.get('source_folder', '')))
                
                # Extensions
                self.table.setItem(row, 3, QTableWidgetItem(collection.get('include_extensions', '')))
                
                # Files count (will need to fetch)
                files_item = QTableWidgetItem("...")
                files_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                self.table.setItem(row, 4, files_item)
                
                # Created
                created = collection.get('created_at', '')
                if created:
                    created = created.split('T')[0]  # Just the date
                self.table.setItem(row, 5, QTableWidgetItem(created))
                
                # Actions
                actions_widget = self.create_actions_widget(collection.get('id'))
                self.table.setCellWidget(row, 6, actions_widget)
        finally:
            # Re-enable updates and trigger a single repaint
            self.table.setUpdatesEnabled(True)
        
        # Fetch file counts asynchronously (simplified - just show button for now)
    
    def create_actions_widget(self, collection_id):
        """Create actions widget for a collection row"""
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(2, 2, 2, 2)
        layout.setSpacing(2)
        
        # View files button
        view_btn = QPushButton("📄")
        view_btn.setToolTip("View Files")
        view_btn.setMaximumWidth(30)
        view_btn.clicked.connect(lambda: self.view_files(collection_id))
        layout.addWidget(view_btn)
        
        # Edit button
        edit_btn = QPushButton("✏️")
        edit_btn.setToolTip("Edit")
        edit_btn.setMaximumWidth(30)
        edit_btn.clicked.connect(lambda: self.edit_collection(collection_id))
        layout.addWidget(edit_btn)
        
        # Delete button
        delete_btn = QPushButton("🗑️")
        delete_btn.setToolTip("Delete")
        delete_btn.setMaximumWidth(30)
        delete_btn.setStyleSheet("QPushButton { background-color: #f44336; }")
        delete_btn.clicked.connect(lambda: self.delete_collection(collection_id))
        layout.addWidget(delete_btn)
        
        return widget
    
    def create_collection(self):
        """Create a new collection"""
        dialog = CollectionDialog(self)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            data = dialog.get_data()
            
            if not data['name'] or not data['sourceFolder']:
                QMessageBox.warning(self, "Validation Error", "Name and Source Folder are required")
                return
            
            from worker import APIWorker
            worker = APIWorker(
                "Creating collection",
                self.main_window.api_client.create_collection,
                name=data['name'],
                source_folder=data['sourceFolder'],
                description=data['description'],
                include_extensions=data['includeExtensions'],
                exclude_folders=data['excludeFolders']
            )
            worker.started.connect(lambda name: self.main_window.status_updated.emit(name))
            worker.finished.connect(lambda result: self._on_create_success())
            worker.error.connect(lambda error: self._on_create_error(error))
            self.main_window.worker_manager.start_worker("create_collection", worker)
    
    def _on_create_success(self):
        """Handle successful collection creation"""
        QMessageBox.information(self, "Success", "Collection created successfully")
        self.refresh()
    
    def _on_create_error(self, error_msg):
        """Handle collection creation error"""
        QMessageBox.critical(self, "Error", f"Failed to create collection:\n{error_msg}")
    
    def edit_collection(self, collection_id):
        """Edit an existing collection"""
        # First, get the collection data
        from worker import APIWorker
        worker = APIWorker(
            "Loading collection",
            self.main_window.api_client.get_collection,
            collection_id
        )
        worker.finished.connect(lambda collection: self._show_edit_dialog(collection_id, collection))
        worker.error.connect(lambda error: QMessageBox.critical(self, "Error", f"Failed to load collection:\n{error}"))
        self.main_window.worker_manager.start_worker("load_collection", worker)
    
    def _show_edit_dialog(self, collection_id, collection):
        """Show edit dialog with loaded collection data"""
        dialog = CollectionDialog(self, collection)
        
        if dialog.exec() == QDialog.DialogCode.Accepted:
            data = dialog.get_data()
            
            from worker import APIWorker
            worker = APIWorker(
                "Updating collection",
                self.main_window.api_client.update_collection,
                collection_id,
                name=data['name'],
                sourceFolder=data['sourceFolder'],
                description=data['description'],
                includeExtensions=data['includeExtensions'],
                excludeFolders=data['excludeFolders']
            )
            worker.started.connect(lambda name: self.main_window.status_updated.emit(name))
            worker.finished.connect(lambda result: self._on_update_success())
            worker.error.connect(lambda error: self._on_update_error(error))
            self.main_window.worker_manager.start_worker("update_collection", worker)
    
    def _on_update_success(self):
        """Handle successful collection update"""
        QMessageBox.information(self, "Success", "Collection updated successfully")
        self.refresh()
    
    def _on_update_error(self, error_msg):
        """Handle collection update error"""
        QMessageBox.critical(self, "Error", f"Failed to update collection:\n{error_msg}")
    
    def delete_collection(self, collection_id):
        """Delete a collection"""
        reply = QMessageBox.question(
            self,
            "Confirm Delete",
            "Are you sure you want to delete this collection?<br>"
            "<b>Warning:</b> This will remove the collection from FileTracker.",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No
        )
        
        if reply == QMessageBox.StandardButton.Yes:
            from worker import APIWorker
            worker = APIWorker(
                "Deleting collection",
                self.main_window.api_client.delete_collection,
                collection_id
            )
            worker.started.connect(lambda name: self.main_window.status_updated.emit(name))
            worker.finished.connect(lambda result: self._on_delete_success())
            worker.error.connect(lambda error: self._on_delete_error(error))
            self.main_window.worker_manager.start_worker("delete_collection", worker)
    
    def _on_delete_success(self):
        """Handle successful collection deletion"""
        QMessageBox.information(self, "Success", "Collection deleted successfully")
        self.refresh()
    
    def _on_delete_error(self, error_msg):
        """Handle collection deletion error"""
        QMessageBox.critical(self, "Error", f"Failed to delete collection:\n{error_msg}")
    
    def view_files(self, collection_id):
        """View files in a collection"""
        # Switch to files tab and filter by collection
        self.collection_selected.emit(collection_id)
        self.main_window.tabs.setCurrentIndex(2)  # Files tab
        self.main_window.files_tab.set_collection_filter(collection_id)
    
    def on_row_double_clicked(self, row, column):
        """Handle row double-click"""
        collection_id = int(self.table.item(row, 0).text())
        self.view_files(collection_id)
    
    def show_context_menu(self, position):
        """Show context menu for table"""
        row = self.table.rowAt(position.y())
        if row < 0:
            return
        
        collection_id = int(self.table.item(row, 0).text())
        
        menu = QMenu(self)
        
        view_action = QAction("📄 View Files", self)
        view_action.triggered.connect(lambda: self.view_files(collection_id))
        menu.addAction(view_action)
        
        edit_action = QAction("✏️ Edit", self)
        edit_action.triggered.connect(lambda: self.edit_collection(collection_id))
        menu.addAction(edit_action)
        
        menu.addSeparator()
        
        delete_action = QAction("🗑️ Delete", self)
        delete_action.triggered.connect(lambda: self.delete_collection(collection_id))
        menu.addAction(delete_action)
        
        menu.exec(self.table.viewport().mapToGlobal(position))
