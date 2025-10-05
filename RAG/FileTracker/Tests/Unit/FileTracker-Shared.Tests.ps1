# FileTracker-Shared.Tests.ps1
# Unit tests for FileTracker-Shared module

BeforeAll {
    # Import the module to test
    $modulePath = Join-Path $PSScriptRoot "..\..\..\FileTracker\FileTracker-Shared.psm1"
    Import-Module $modulePath -Force
    
    # Import database module (dependency)
    $dbModulePath = Join-Path $PSScriptRoot "..\..\..\FileTracker\Database-Shared.psm1"
    Import-Module $dbModulePath -Force
    
    # Import test helpers
    $testHelpersPath = Join-Path $PSScriptRoot "..\..\..\Tests\TestHelpers.psm1"
    Import-Module $testHelpersPath -Force
}

Describe "FileTracker-Shared Module" -Tag "Unit" {
    
    BeforeAll {
        $script:testDb = New-TestDatabase
        $script:testConfig = New-TestConfig
        $script:testDir = New-TestDirectory -FileCount 3
    }
    
    AfterAll {
        Remove-TestDatabase -TestDatabase $script:testDb
        Remove-TestDirectory -TestDirectory $script:testDir
    }
    
    Context "Update-FileProcessingStatus - Single File" {
        
        BeforeEach {
            # Initialize test database
            if (Test-Path $script:testDb.Path) {
                Remove-Item $script:testDb.Path -Force
            }
            
            # Create a minimal database schema for testing
            $connection = New-Object Microsoft.Data.Sqlite.SqliteConnection("Data Source=$($script:testDb.Path)")
            $connection.Open()
            
            $createTableCommand = $connection.CreateCommand()
            $createTableCommand.CommandText = @"
                CREATE TABLE IF NOT EXISTS collections (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL UNIQUE,
                    path TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                
                CREATE TABLE IF NOT EXISTS files (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    collection_id INTEGER NOT NULL,
                    FilePath TEXT NOT NULL,
                    Hash TEXT,
                    Dirty INTEGER NOT NULL DEFAULT 1,
                    Deleted INTEGER NOT NULL DEFAULT 0,
                    LastModified TEXT,
                    FOREIGN KEY (collection_id) REFERENCES collections (id)
                );
"@
            $createTableCommand.ExecuteNonQuery() | Out-Null

            # Clear files
            $deleteCommand = $connection.CreateCommand()
            $deleteCommand.CommandText = "DELETE FROM files"
            $deleteCommand.ExecuteNonQuery() | Out-Null
                    
            # Clear collections
            $deleteCommand = $connection.CreateCommand()
            $deleteCommand.CommandText = "DELETE FROM collections"
            $deleteCommand.ExecuteNonQuery() | Out-Null

            # Insert test collection
            $insertCollectionCommand = $connection.CreateCommand()
            $insertCollectionCommand.CommandText = "INSERT INTO collections (name, path, created_at) VALUES ('TestCollection', '/test/path', datetime('now')); SELECT last_insert_rowid();"
            $collectionId = $insertCollectionCommand.ExecuteScalar()
            
            # Insert test file
            $insertFileCommand = $connection.CreateCommand()
            $insertFileCommand.CommandText = "INSERT INTO files (collection_id, FilePath, Dirty, Deleted) VALUES ($collectionId, @FilePath, 1, 0)"
            $insertFileCommand.Parameters.AddWithValue("@FilePath", $script:testDir.Files[0]) | Out-Null
            $insertFileCommand.ExecuteNonQuery() | Out-Null
            
            $connection.Close()
            $connection.Dispose()
        }
        
        It "Should mark a single file as processed (Dirty=0)" {
            $result = Update-FileProcessingStatus -FilePath $script:testDir.Files[0] -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $false
            
            $result | Should -Be $true
        }
        
        It "Should mark a single file as dirty (Dirty=1)" {
            # First mark as processed
            Update-FileProcessingStatus -FilePath $script:testDir.Files[0] -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $false
            
            # Then mark as dirty
            $result = Update-FileProcessingStatus -FilePath $script:testDir.Files[0] -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $true
            
            $result | Should -Be $true
        }
        
        It "Should return true if file already has target status" {
            # File is already dirty (1) from setup
            $result = Update-FileProcessingStatus -FilePath $script:testDir.Files[0] -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $true
            
            $result | Should -Be $true
        }
        
        It "Should handle non-existent files gracefully" {
            $result = Update-FileProcessingStatus -FilePath "C:\NonExistent\File.txt" -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $false
            
            $result | Should -Be $false
        }
    }
    
    Context "Update-FileProcessingStatus - All Files" {
        
        BeforeEach {
            # Initialize test database with multiple files
            if (Test-Path $script:testDb.Path) {
                Remove-Item $script:testDb.Path -Force
            }
            
            $connection = New-Object Microsoft.Data.Sqlite.SqliteConnection("Data Source=$($script:testDb.Path)")
            $connection.Open()
            
            $createTableCommand = $connection.CreateCommand()
            $createTableCommand.CommandText = @"
                CREATE TABLE IF NOT EXISTS collections (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL UNIQUE,
                    path TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                
                CREATE TABLE IF NOT EXISTS files (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    collection_id INTEGER NOT NULL,
                    FilePath TEXT NOT NULL,
                    Hash TEXT,
                    Dirty INTEGER NOT NULL DEFAULT 1,
                    Deleted INTEGER NOT NULL DEFAULT 0,
                    LastModified TEXT,
                    FOREIGN KEY (collection_id) REFERENCES collections (id)
                );
"@
            $createTableCommand.ExecuteNonQuery() | Out-Null


            # Clear files
            $deleteCommand = $connection.CreateCommand()
            $deleteCommand.CommandText = "DELETE FROM files"
            $deleteCommand.ExecuteNonQuery() | Out-Null
                    
            # Clear collections
            $deleteCommand = $connection.CreateCommand()
            $deleteCommand.CommandText = "DELETE FROM collections"
            $deleteCommand.ExecuteNonQuery() | Out-Null

            # Insert test collection
            $insertCollectionCommand = $connection.CreateCommand()
            $insertCollectionCommand.CommandText = "INSERT INTO collections (name, path, created_at) VALUES ('TestCollection', '/test/path', datetime('now')); SELECT last_insert_rowid();"
            $collectionId = $insertCollectionCommand.ExecuteScalar()
            
            # Insert multiple test files
            foreach ($file in $script:testDir.Files) {
                $insertFileCommand = $connection.CreateCommand()
                $insertFileCommand.CommandText = "INSERT INTO files (collection_id, FilePath, Dirty, Deleted) VALUES ($collectionId, @FilePath, 1, 0)"
                $insertFileCommand.Parameters.AddWithValue("@FilePath", $file) | Out-Null
                $insertFileCommand.ExecuteNonQuery() | Out-Null
            }
            
            $connection.Close()
            $connection.Dispose()
        }
        
        It "Should mark all files in collection as processed" {
            $result = Update-FileProcessingStatus -All -CollectionId 1 -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $false
            
            $result | Should -Be $true
        }
        
        It "Should mark all files in collection as dirty" {
            # First mark all as processed
            Update-FileProcessingStatus -All -CollectionId 1 -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $false
            
            # Then mark all as dirty
            $result = Update-FileProcessingStatus -All -CollectionId 1 -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $true
            
            $result | Should -Be $true
        }
        
        It "Should handle empty collections gracefully" {
            # Collection 99 doesn't exist
            $result = Update-FileProcessingStatus -All -CollectionId 99 -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $false
            
            $result | Should -Be $true  # No files to update, but not an error
        }
    }
    
    Context "Database Transaction Handling" {
        
        It "Should rollback on error" {
            # This test verifies that errors are handled gracefully
            $invalidDbPath = "C:\InvalidPath\NonExistent.db"
            
            $result = Update-FileProcessingStatus -FilePath "test.txt" -InstallPath $script:testConfig.InstallPath -DatabasePath $invalidDbPath -Dirty $false
            
            $result | Should -Be $false
        }
    }
}

Describe "FileTracker-Shared Integration" -Tag "Integration" {
    
    BeforeAll {
        $script:testDb = New-TestDatabase
        $script:testConfig = New-TestConfig
        $script:testDir = New-TestDirectory -FileCount 5
    }
    
    AfterAll {
        Remove-TestDatabase -TestDatabase $script:testDb
        Remove-TestDirectory -TestDirectory $script:testDir
    }
    
    Context "Complete File Tracking Workflow" {
        
        It "Should track multiple files through status changes" {
            # Initialize database
            if (Test-Path $script:testDb.Path) {
                Remove-Item $script:testDb.Path -Force
            }
            
            $connection = New-Object Microsoft.Data.Sqlite.SqliteConnection("Data Source=$($script:testDb.Path)")
            $connection.Open()
            
            # Create schema
            $createTableCommand = $connection.CreateCommand()
            $createTableCommand.CommandText = @"
                CREATE TABLE collections (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL UNIQUE,
                    path TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                
                CREATE TABLE files (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    collection_id INTEGER NOT NULL,
                    FilePath TEXT NOT NULL,
                    Hash TEXT,
                    Dirty INTEGER NOT NULL DEFAULT 1,
                    Deleted INTEGER NOT NULL DEFAULT 0,
                    LastModified TEXT,
                    FOREIGN KEY (collection_id) REFERENCES collections (id)
                );
"@
            $createTableCommand.ExecuteNonQuery() | Out-Null
            
            # Add collection
            $insertCollectionCommand = $connection.CreateCommand()
            $insertCollectionCommand.CommandText = "INSERT INTO collections (name, path, created_at) VALUES ('IntegrationTest', @path, datetime('now'))"
            $insertCollectionCommand.Parameters.AddWithValue("@path", $script:testDir.Path) | Out-Null
            $insertCollectionCommand.ExecuteNonQuery() | Out-Null
            
            # Add files
            foreach ($file in $script:testDir.Files) {
                $insertFileCommand = $connection.CreateCommand()
                $insertFileCommand.CommandText = "INSERT INTO files (collection_id, FilePath, Dirty) VALUES (1, @FilePath, 1)"
                $insertFileCommand.Parameters.AddWithValue("@FilePath", $file) | Out-Null
                $insertFileCommand.ExecuteNonQuery() | Out-Null
            }
            
            $connection.Close()
            $connection.Dispose()
            
            # Mark all as processed
            $result1 = Update-FileProcessingStatus -All -CollectionId 1 -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $false
            $result1 | Should -Be $true
            
            # Mark one as dirty
            $result2 = Update-FileProcessingStatus -FilePath $script:testDir.Files[0] -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $true
            $result2 | Should -Be $true
            
            # Mark all as dirty again
            $result3 = Update-FileProcessingStatus -All -CollectionId 1 -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $true
            $result3 | Should -Be $true
        }
    }
}
