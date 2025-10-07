"""
Search Tab - Search for documents and chunks using semantic similarity
"""

from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QPushButton, QTableWidget,
    QTableWidgetItem, QHeaderView, QPlainTextEdit, QLabel, QSpinBox,
    QDoubleSpinBox, QGroupBox, QRadioButton, QComboBox, QCheckBox,
    QMessageBox, QSplitter
)
from PyQt6.QtCore import Qt, pyqtSignal, QTimer
from PyQt6.QtGui import QFont, QKeySequence, QShortcut


class SearchTab(QWidget):
    """Search tab for semantic document/chunk search"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.search_results = []
        self.init_ui()
    
    def init_ui(self):
        """Initialize the UI"""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)
        
        # Header
        title = QLabel("Semantic Search")
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setBold(True)
        title.setFont(title_font)
        layout.addWidget(title)
        
        # Create splitter for search params and results
        splitter = QSplitter(Qt.Orientation.Vertical)
        
        # Search parameters widget
        search_params_widget = QWidget()
        search_params_layout = QVBoxLayout(search_params_widget)
        
        # Query input
        query_group = QGroupBox("Search Query")
        query_layout = QVBoxLayout(query_group)
        
        self.query_input = QPlainTextEdit()
        self.query_input.setPlaceholderText("Enter your search query here...\n\nExample: machine learning algorithms for classification")
        self.query_input.setMaximumHeight(100)
        self.query_input.setTabChangesFocus(True)  # Allow tab to move to next field
        query_layout.addWidget(self.query_input)
        
        search_params_layout.addWidget(query_group)
        
        # Search options
        options_group = QGroupBox("Search Options")
        options_layout = QHBoxLayout(options_group)
        
        # Search type
        type_layout = QVBoxLayout()
        type_layout.addWidget(QLabel("Search Type:"))
        self.search_type_documents = QRadioButton("Documents")
        self.search_type_documents.setChecked(True)
        self.search_type_chunks = QRadioButton("Chunks")
        type_layout.addWidget(self.search_type_documents)
        type_layout.addWidget(self.search_type_chunks)
        type_layout.addStretch()
        options_layout.addLayout(type_layout)
        
        # Parameters
        params_layout = QVBoxLayout()
        
        # Max results
        max_results_layout = QHBoxLayout()
        max_results_layout.addWidget(QLabel("Max Results:"))
        self.max_results_spin = QSpinBox()
        self.max_results_spin.setRange(1, 100)
        self.max_results_spin.setValue(10)
        max_results_layout.addWidget(self.max_results_spin)
        max_results_layout.addStretch()
        params_layout.addLayout(max_results_layout)
        
        # Threshold
        threshold_layout = QHBoxLayout()
        threshold_layout.addWidget(QLabel("Min Similarity:"))
        self.threshold_spin = QDoubleSpinBox()
        self.threshold_spin.setRange(0.0, 1.0)
        self.threshold_spin.setSingleStep(0.05)
        self.threshold_spin.setValue(0.5)
        self.threshold_spin.setToolTip("Minimum similarity score (0.0 - 1.0)")
        threshold_layout.addWidget(self.threshold_spin)
        threshold_layout.addStretch()
        params_layout.addLayout(threshold_layout)
        
        # Return content checkbox
        self.return_content_checkbox = QCheckBox("Include content in results")
        params_layout.addWidget(self.return_content_checkbox)
        
        params_layout.addStretch()
        options_layout.addLayout(params_layout)
        
        # Collection filter
        coll_layout = QVBoxLayout()
        coll_layout.addWidget(QLabel("Collection:"))
        self.collection_combo = QComboBox()
        self.collection_combo.addItem("default", "default")
        coll_layout.addWidget(self.collection_combo)
        coll_layout.addStretch()
        options_layout.addLayout(coll_layout)
        
        options_layout.addStretch()
        
        search_params_layout.addWidget(options_group)
        
        # Search button
        search_btn_layout = QHBoxLayout()
        self.search_btn = QPushButton("🔍 Search")
        self.search_btn.clicked.connect(self.perform_search)
        self.search_btn.setMinimumHeight(40)
        self.search_btn.setStyleSheet("QPushButton { font-size: 14px; font-weight: bold; }")
        search_btn_layout.addStretch()
        search_btn_layout.addWidget(self.search_btn)
        search_btn_layout.addStretch()
        search_params_layout.addLayout(search_btn_layout)
        
        splitter.addWidget(search_params_widget)
        
        # Results table
        results_widget = QWidget()
        results_layout = QVBoxLayout(results_widget)
        
        results_header_layout = QHBoxLayout()
        self.results_label = QLabel("Results (0)")
        results_font = QFont()
        results_font.setBold(True)
        self.results_label.setFont(results_font)
        results_header_layout.addWidget(self.results_label)
        results_header_layout.addStretch()
        
        export_btn = QPushButton("📥 Export Results")
        export_btn.clicked.connect(self.export_results)
        results_header_layout.addWidget(export_btn)
        
        results_layout.addLayout(results_header_layout)
        
        self.results_table = QTableWidget()
        self.results_table.setColumnCount(5)
        self.results_table.setHorizontalHeaderLabels([
            "Rank", "Score", "File Path", "Collection", "Preview"
        ])
        
        # Set column widths
        header = self.results_table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(4, QHeaderView.ResizeMode.Stretch)
        
        self.results_table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.results_table.cellDoubleClicked.connect(self.show_result_details)
        
        results_layout.addWidget(self.results_table)
        
        splitter.addWidget(results_widget)
        
        # Set initial splitter sizes
        splitter.setSizes([300, 500])
        
        layout.addWidget(splitter)
        
        # Add keyboard shortcuts
        # Ctrl+Enter to search
        search_shortcut = QShortcut(QKeySequence("Ctrl+Return"), self)
        search_shortcut.activated.connect(self.perform_search)
        
        # Load collections
        self.load_collections()
    
    def load_collections(self):
        """Load available collections"""
        if not self.main_window or not self.main_window.api_client:
            return
        
        from worker import APIWorker
        worker = APIWorker(
            "Loading collections",
            self.main_window.api_client.get_vector_collections
        )
        worker.finished.connect(self._on_collections_loaded)
        worker.error.connect(lambda e: None)  # Silent fail - just use default
        self.main_window.worker_manager.start_worker("load_search_collections", worker)
    
    def _on_collections_loaded(self, collections):
        """Handle collections loaded"""
        self.collection_combo.clear()
        self.collection_combo.addItem("default", "default")
        
        for coll in collections:
            if coll != "default":
                self.collection_combo.addItem(coll, coll)
    
    def perform_search(self):
        """Perform the search"""
        query = self.query_input.toPlainText().strip()
        
        if not query:
            QMessageBox.warning(self, "No Query", "Please enter a search query")
            return
        
        if not self.main_window or not self.main_window.api_client:
            QMessageBox.critical(self, "Error", "API client not available")
            return
        
        # Disable search button to prevent multiple simultaneous searches
        self.search_btn.setEnabled(False)
        self.search_btn.setText("⏳ Searching...")
        
        api = self.main_window.api_client
        
        # Get parameters
        max_results = self.max_results_spin.value()
        threshold = self.threshold_spin.value()
        collection = self.collection_combo.currentData()
        return_content = self.return_content_checkbox.isChecked()
        
        self.main_window.status_updated.emit("Searching...")
        
        from worker import APIWorker
        
        if self.search_type_documents.isChecked():
            # Search documents
            worker = APIWorker(
                "Searching documents",
                api.search_documents,
                query=query,
                max_results=max_results,
                threshold=threshold,
                return_content=return_content,
                collection_name=collection
            )
        else:
            # Search chunks
            worker = APIWorker(
                "Searching chunks",
                api.search_chunks,
                query=query,
                max_results=max_results,
                threshold=threshold,
                collection_name=collection
            )
        
        worker.finished.connect(self._on_search_complete)
        worker.error.connect(self._on_search_error)
        self.main_window.worker_manager.start_worker("search", worker)
    
    def _on_search_complete(self, results):
        """Handle search results"""
        self.search_results = results
        self.display_results(results)
        self.main_window.status_updated.emit(f"Found {len(results)} results")
        
        # Re-enable search button
        self.search_btn.setEnabled(True)
        self.search_btn.setText("🔍 Search")
    
    def _on_search_error(self, error_msg):
        """Handle search error"""
        QMessageBox.critical(self, "Search Error", f"Search failed:\n{error_msg}")
        self.main_window.status_updated.emit("Search failed")
        
        # Re-enable search button
        self.search_btn.setEnabled(True)
        self.search_btn.setText("🔍 Search")
    
    def display_results(self, results):
        """Display search results in the table"""
        # Disable updates during batch operations to prevent UI lag
        self.results_table.setUpdatesEnabled(False)
        try:
            self.results_table.setRowCount(0)
            self.results_label.setText(f"Results ({len(results)})")
            
            # Set row count once instead of inserting rows one by one
            self.results_table.setRowCount(len(results))
            
            for idx, result in enumerate(results, 1):
                row = idx - 1
                
                # Rank
                rank_item = QTableWidgetItem(str(idx))
                rank_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                self.results_table.setItem(row, 0, rank_item)
                
                # Score
                score = result.get('score', result.get('distance', 0))
                if isinstance(score, (int, float)):
                    score_text = f"{score:.4f}"
                else:
                    score_text = str(score)
                
                score_item = QTableWidgetItem(score_text)
                score_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                self.results_table.setItem(row, 1, score_item)
                
                # File Path
                file_path = result.get('file_path', result.get('source', 'N/A'))
                path_item = QTableWidgetItem(file_path)
                path_item.setToolTip(file_path)
                self.results_table.setItem(row, 2, path_item)
                
                # Collection
                collection = result.get('collection', result.get('metadata', {}).get('collection', 'N/A'))
                self.results_table.setItem(row, 3, QTableWidgetItem(str(collection)))
                
                # Preview
                content = result.get('content', result.get('text', ''))
                if content:
                    preview = content[:200] + "..." if len(content) > 200 else content
                    preview = preview.replace('\n', ' ')
                else:
                    preview = "No preview available"
                
                preview_item = QTableWidgetItem(preview)
                preview_item.setToolTip(content if content else "No content")
                self.results_table.setItem(row, 4, preview_item)
        finally:
            # Re-enable updates and trigger a single repaint
            self.results_table.setUpdatesEnabled(True)
    
    def show_result_details(self, row, column):
        """Show detailed view of a search result"""
        if row >= len(self.search_results):
            return
        
        result = self.search_results[row]
        
        # Create detail dialog
        from PyQt6.QtWidgets import QDialog, QTextBrowser
        
        dialog = QDialog(self)
        dialog.setWindowTitle("Search Result Details")
        dialog.setMinimumSize(700, 500)
        
        layout = QVBoxLayout(dialog)
        
        # Result info
        info_text = f"""
<h2>Search Result #{row + 1}</h2>
<p><b>File:</b> {result.get('file_path', result.get('source', 'N/A'))}</p>
<p><b>Collection:</b> {result.get('collection', 'N/A')}</p>
<p><b>Score:</b> {result.get('score', result.get('distance', 'N/A'))}</p>
        """
        
        info_browser = QTextBrowser()
        info_browser.setHtml(info_text)
        info_browser.setMaximumHeight(150)
        layout.addWidget(info_browser)
        
        # Content
        content_label = QLabel("<b>Content:</b>")
        layout.addWidget(content_label)
        
        content_browser = QTextBrowser()
        content = result.get('content', result.get('text', 'No content available'))
        content_browser.setPlainText(content)
        layout.addWidget(content_browser)
        
        # Close button
        close_btn = QPushButton("Close")
        close_btn.clicked.connect(dialog.close)
        layout.addWidget(close_btn)
        
        dialog.exec()
    
    def export_results(self):
        """Export search results to a file"""
        if not self.search_results:
            QMessageBox.warning(self, "No Results", "No results to export")
            return
        
        from PyQt6.QtWidgets import QFileDialog
        
        file_path, _ = QFileDialog.getSaveFileName(
            self,
            "Export Results",
            "search_results.json",
            "JSON Files (*.json);;Text Files (*.txt);;All Files (*.*)"
        )
        
        if file_path:
            # Export in background to avoid blocking UI
            from worker import APIWorker
            import json
            
            def export_worker():
                """Worker function to export results"""
                with open(file_path, 'w', encoding='utf-8') as f:
                    if file_path.endswith('.json'):
                        json.dump(self.search_results, f, indent=2, ensure_ascii=False)
                    else:
                        for idx, result in enumerate(self.search_results, 1):
                            f.write(f"Result #{idx}\n")
                            f.write(f"File: {result.get('file_path', result.get('source', 'N/A'))}\n")
                            f.write(f"Score: {result.get('score', result.get('distance', 'N/A'))}\n")
                            f.write(f"Content:\n{result.get('content', result.get('text', ''))}\n")
                            f.write("\n" + "="*80 + "\n\n")
                return file_path
            
            worker = APIWorker("Exporting results", export_worker)
            worker.finished.connect(lambda path: self._on_export_success(path))
            worker.error.connect(lambda error: self._on_export_error(error))
            self.main_window.worker_manager.start_worker("export_results", worker)
            self.main_window.status_updated.emit("Exporting results...")
    
    def _on_export_success(self, file_path):
        """Handle successful export"""
        QMessageBox.information(self, "Success", f"Results exported to:\n{file_path}")
        self.main_window.status_updated.emit("Export complete")
    
    def _on_export_error(self, error_msg):
        """Handle export error"""
        QMessageBox.critical(self, "Export Error", f"Failed to export results:\n{error_msg}")
        self.main_window.status_updated.emit("Export failed")
    
    def refresh(self):
        """Refresh (reload collections)"""
        self.load_collections()
