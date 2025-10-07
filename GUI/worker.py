"""
Background Worker for API calls
Prevents GUI freezing by executing API calls in separate threads
"""

from PyQt6.QtCore import QThread, pyqtSignal
from typing import Callable, Any, Dict, Optional


class APIWorker(QThread):
    """
    Worker thread for executing API calls in the background
    
    Signals:
        started: Emitted when the worker starts
        finished: Emitted when the worker completes successfully
        error: Emitted when an error occurs
        progress: Emitted to report progress (optional)
    """
    
    # Signals
    started = pyqtSignal(str)  # operation name
    finished = pyqtSignal(object)  # result
    error = pyqtSignal(str)  # error message
    progress = pyqtSignal(int, str)  # percentage, status message
    
    def __init__(self, operation_name: str, func: Callable, *args, **kwargs):
        """
        Initialize the worker
        
        Args:
            operation_name: Human-readable name of the operation (e.g., "Loading collections")
            func: Function to execute
            *args: Positional arguments to pass to the function
            **kwargs: Keyword arguments to pass to the function
        """
        super().__init__()
        self.operation_name = operation_name
        self.func = func
        self.args = args
        self.kwargs = kwargs
        self._is_cancelled = False
        
        # Ensure thread is properly cleaned up
        self.setTerminationEnabled(True)
    
    def run(self):
        """Execute the function in the background thread"""
        try:
            if self._is_cancelled:
                return
                
            self.started.emit(self.operation_name)
            result = self.func(*self.args, **self.kwargs)
            
            if not self._is_cancelled:
                self.finished.emit(result)
        except Exception as e:
            if not self._is_cancelled:
                self.error.emit(str(e))
        finally:
            # Ensure thread exits cleanly
            self.quit()
    
    def cancel(self):
        """Cancel the operation gracefully"""
        self._is_cancelled = True
        
        # Request thread to stop and wait for it
        if self.isRunning():
            self.requestInterruption()
            self.quit()
            # Wait up to 3 seconds for graceful exit
            if not self.wait(3000):
                # Force terminate if it doesn't exit gracefully
                self.terminate()
                self.wait()
    
    def __del__(self):
        """Destructor - ensure thread is stopped before deletion"""
        try:
            if self.isRunning():
                self._is_cancelled = True
                self.requestInterruption()
                self.quit()
                # Wait briefly for graceful exit
                if not self.wait(1000):
                    self.terminate()
                    self.wait()
        except RuntimeError:
            # Thread may already be deleted, ignore
            pass


class WorkerManager:
    """
    Manages multiple background workers
    Keeps track of active workers and provides cleanup
    """
    
    def __init__(self):
        self.workers: Dict[str, APIWorker] = {}
    
    def start_worker(self, worker_id: str, worker: APIWorker):
        """
        Start a new worker
        
        Args:
            worker_id: Unique identifier for the worker
            worker: APIWorker instance to start
        """
        # Cancel and clean up existing worker with same ID if running
        if worker_id in self.workers:
            old_worker = self.workers[worker_id]
            old_worker.cancel()
            # Disconnect signals to prevent callbacks
            try:
                old_worker.finished.disconnect()
                old_worker.error.disconnect()
                old_worker.started.disconnect()
            except (TypeError, RuntimeError):
                # Signals may not be connected
                pass
        
        self.workers[worker_id] = worker
        
        # Connect cleanup handlers with lambda to capture worker_id
        worker.finished.connect(lambda: self._cleanup_worker(worker_id))
        worker.error.connect(lambda _: self._cleanup_worker(worker_id))
        
        # Start the worker
        worker.start()
    
    def _cleanup_worker(self, worker_id: str):
        """Remove finished worker from tracking"""
        if worker_id in self.workers:
            worker = self.workers[worker_id]
            # Ensure thread has finished before removing
            if worker.isRunning():
                worker.wait(1000)
            del self.workers[worker_id]
    
    def cancel_worker(self, worker_id: str):
        """Cancel a specific worker"""
        if worker_id in self.workers:
            worker = self.workers[worker_id]
            worker.cancel()
            try:
                worker.finished.disconnect()
                worker.error.disconnect()
                worker.started.disconnect()
            except (TypeError, RuntimeError):
                pass
            del self.workers[worker_id]
    
    def cancel_all(self):
        """Cancel all running workers"""
        # Create a copy of worker IDs to avoid modifying dict during iteration
        worker_ids = list(self.workers.keys())
        for worker_id in worker_ids:
            self.cancel_worker(worker_id)
        self.workers.clear()
    
    def is_busy(self) -> bool:
        """Check if any workers are running"""
        return len(self.workers) > 0
    
    def __del__(self):
        """Destructor - ensure all workers are stopped"""
        try:
            self.cancel_all()
        except (RuntimeError, TypeError):
            # May fail during application shutdown
            pass


class StatusBarManager:
    """
    Manages status bar updates from background workers
    Thread-safe status bar management
    """
    
    def __init__(self, status_bar):
        """
        Initialize the status bar manager
        
        Args:
            status_bar: QStatusBar instance
        """
        self.status_bar = status_bar
        self.current_operations = set()
    
    def operation_started(self, operation_name: str):
        """Called when an operation starts"""
        try:
            self.current_operations.add(operation_name)
            self._update_status()
        except (RuntimeError, AttributeError):
            # Status bar may be deleted or not available
            pass
    
    def operation_finished(self, operation_name: str):
        """Called when an operation finishes"""
        try:
            if operation_name in self.current_operations:
                self.current_operations.remove(operation_name)
            self._update_status()
        except (RuntimeError, AttributeError):
            # Status bar may be deleted or not available
            pass
    
    def operation_error(self, operation_name: str, error_msg: str):
        """Called when an operation fails"""
        try:
            if operation_name in self.current_operations:
                self.current_operations.remove(operation_name)
            if self.status_bar:
                self.status_bar.showMessage(f"❌ {operation_name} failed: {error_msg}", 5000)
        except (RuntimeError, AttributeError):
            # Status bar may be deleted or not available
            pass
    
    def _update_status(self):
        """Update the status bar with current operations"""
        try:
            if not self.status_bar:
                return
                
            if self.current_operations:
                operations = ", ".join(self.current_operations)
                self.status_bar.showMessage(f"⏳ {operations}...")
            else:
                self.status_bar.showMessage("✅ Ready", 2000)
        except (RuntimeError, AttributeError):
            # Status bar may be deleted or not available
            pass
    
    def show_message(self, message: str, timeout: int = 0):
        """
        Show a custom message in the status bar
        
        Args:
            message: Message to display
            timeout: Time to display in milliseconds (0 = permanent)
        """
        try:
            if self.status_bar:
                self.status_bar.showMessage(message, timeout)
        except (RuntimeError, AttributeError):
            # Status bar may be deleted or not available
            pass
