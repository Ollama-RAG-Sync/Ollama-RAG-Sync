# End-to-End.Tests.ps1
# Integration tests for complete RAG workflow

BeforeAll {

    Write-Host "Setting up test environment..." -ForegroundColor Green

    # Import test helpers
    $testHelpersPath = Join-Path $PSScriptRoot "..\TestHelpers.psm1"
    Import-Module $testHelpersPath -Force
    
    # Import database module (needed for Get-DatabaseConnection)
    $databaseModulePath = Join-Path $PSScriptRoot "..\..\FileTracker\Database-Shared.psm1"
    Import-Module $databaseModulePath -Force -Verbose
    
    # Import required modules
    $fileTrackerModulePath = Join-Path $PSScriptRoot "..\..\FileTracker\FileTracker-Shared.psm1"
    Import-Module $fileTrackerModulePath -Force
    
    $vectorsModulePath = Join-Path $PSScriptRoot "..\..\Vectors\Modules\Vectors-Core.psm1"
    Import-Module $vectorsModulePath -Force
    
    Write-Host "Test environment setup complete." -ForegroundColor Green
    
}


Describe "End-to-End RAG Workflow" -Tag "Integration", "E2E" {
    
    BeforeAll {
        # Setup test environment
        $script:testConfig = New-TestConfig  
        $script:testDir = New-TestDirectory -FileCount 3 -FileTypes @('.txt', '.md')
        $script:testDb = New-TestDatabase
        
        Write-Host "Test Configuration:" -ForegroundColor Cyan
        Write-Host "  Install Path: $($script:testConfig.InstallPath)"
        Write-Host "  Test Directory: $($script:testDir.Path)"
        Write-Host "  Test Database: $($script:testDb.Path)"
        Write-Host "  File Tracker Port: $($script:testConfig.FileTrackerPort)"
        Write-Host "  Vectors Port: $($script:testConfig.VectorsPort)"
        Write-Host "  Ollama URL: $($script:testConfig.OllamaUrl)"
    }
    
    AfterAll {
        # Cleanup
        Remove-TestDirectory -TestDirectory $script:testDir
        Remove-TestDatabase -TestDatabase $script:testDb
        
        if (Test-Path $script:testConfig.InstallPath) {
            Remove-Item -Path $script:testConfig.InstallPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Complete Document Processing Pipeline" {

        It "Should initialize database successfully" {
            # Get database connection (this will initialize SQLite environment)
            $connection = Get-DatabaseConnection -DatabasePath $script:testDb.Path -InstallPath $script:testConfig.InstallPath
            
            $createSchemaCommand = $connection.CreateCommand()
            $createSchemaCommand.CommandText = @"
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
            $result = $createSchemaCommand.ExecuteNonQuery()
            $connection.Close()
            $connection.Dispose()
            
            $result | Should -Not -BeNull
            Test-Path $script:testDb.Path | Should -Be $true
        }
        

        It "Should add collection to database" {
            $connection = Get-DatabaseConnection -DatabasePath $script:testDb.Path -InstallPath $script:testConfig.InstallPath
            
            $insertCommand = $connection.CreateCommand()
            $insertCommand.CommandText = "INSERT INTO collections (name, path, created_at) VALUES (@name, @path, datetime('now'))"
            $insertCommand.Parameters.AddWithValue("@name", "E2ETestCollection") | Out-Null
            $insertCommand.Parameters.AddWithValue("@path", $script:testDir.Path) | Out-Null
            $result = $insertCommand.ExecuteNonQuery()
            
            $connection.Close()
            $connection.Dispose()
            
            $result | Should -Be 1
        }
        
        It "Should add files to collection" {
            $connection = Get-DatabaseConnection -DatabasePath $script:testDb.Path -InstallPath $script:testConfig.InstallPath
            
            $filesAdded = 0
            foreach ($file in $script:testDir.Files) {
                $insertCommand = $connection.CreateCommand()
                $insertCommand.CommandText = "INSERT INTO files (collection_id, FilePath, Dirty, LastModified) VALUES (1, @path, 1, datetime('now'))"
                $insertCommand.Parameters.AddWithValue("@path", $file) | Out-Null
                $filesAdded += $insertCommand.ExecuteNonQuery()
            }
            
            $connection.Close()
            $connection.Dispose()
            
            $filesAdded | Should -Be $script:testDir.Files.Count
        }
        
        
        It "Should read file content" {
            foreach ($file in $script:testDir.Files) {
                $content = Get-FileContent -FilePath $file
                $content | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Should mark files as processed" {
            $result = Update-FileProcessingStatus -All -CollectionId 1 -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $false
            $result | Should -Be $true
        }
        It "Should retrieve processed files" {
            $connection = Get-DatabaseConnection -DatabasePath $script:testDb.Path -InstallPath $script:testConfig.InstallPath
            
            $queryCommand = $connection.CreateCommand()
            $queryCommand.CommandText = "SELECT COUNT(*) FROM files WHERE collection_id = 1 AND Dirty = 0"
            $count = $queryCommand.ExecuteScalar()
            
            $connection.Close()
            $connection.Dispose()
            
            [int]$count | Should -Be $script:testDir.Files.Count
        }

    }
    
    Context "File Change Detection" {
        BeforeAll {
            # Import database module (needed for Get-DatabaseConnection)
            $databaseModulePath = Join-Path $PSScriptRoot "..\..\FileTracker\Database-Shared.psm1"
            Import-Module $databaseModulePath -Force -Verbose
        }
    
        It "Should detect when file is modified" {
            # Modify a file
            $fileToModify = $script:testDir.Files[0]
            Add-Content -Path $fileToModify -Value "`nAdditional content added during test"
            
            # File system should reflect the change
            $newContent = Get-Content -Path $fileToModify -Raw
            $newContent | Should -Match "Additional content"
        }
        
        It "Should mark modified file as dirty" {
            $result = Update-FileProcessingStatus -FilePath $script:testDir.Files[0] -InstallPath $script:testConfig.InstallPath -DatabasePath $script:testDb.Path -Dirty $true
            
            $result | Should -Be $true
        }
        
        It "Should identify dirty files in collection" {
            $connection = Get-DatabaseConnection -DatabasePath $script:testDb.Path -InstallPath $script:testConfig.InstallPath
            
            $queryCommand = $connection.CreateCommand()
            $queryCommand.CommandText = "SELECT COUNT(*) FROM files WHERE collection_id = 1 AND Dirty = 1"
            $dirtyCount = $queryCommand.ExecuteScalar()
            
            $connection.Close()
            $connection.Dispose()
            
            [int]$dirtyCount | Should -BeGreaterThan 0
        }
    }
    
    Context "Configuration Management" {
        
        It "Should initialize vectors configuration" {
            $config = Initialize-VectorsConfig -ConfigOverrides @{
                OllamaUrl = $script:testConfig.OllamaUrl
                EmbeddingModel = $script:testConfig.EmbeddingModel
                ChunkSize = $script:testConfig.ChunkSize
                ChunkOverlap = $script:testConfig.ChunkOverlap
            }
            
            $config | Should -Not -BeNull
            $config.OllamaUrl | Should -Be $script:testConfig.OllamaUrl
            $config.ChunkSize | Should -Be $script:testConfig.ChunkSize
        }
        
        It "Should retrieve configuration" {
            $config = Get-VectorsConfig
            
            $config | Should -Not -BeNull
            $config.Keys | Should -Contain "OllamaUrl"
            $config.Keys | Should -Contain "EmbeddingModel"
        }
    }
}

Describe "Error Handling and Edge Cases" -Tag "Integration", "ErrorHandling" {
    
    Context "Database Errors" {
        
        It "Should handle missing database gracefully" {
            $result = Update-FileProcessingStatus -FilePath "test.txt" -InstallPath "C:\NonExistent" -DatabasePath "C:\NonExistent\db.db" -Dirty $false
            
            $result | Should -Be $false
        }
        
        It "Should handle invalid file paths" {
            $testDb = New-TestDatabase
            $result = Update-FileProcessingStatus -FilePath "C:\InvalidPath\File.txt" -InstallPath ([System.IO.Path]::GetTempPath()) -DatabasePath $testDb.Path -Dirty $false
            
            $result | Should -Be $false
            Remove-TestDatabase -TestDatabase $testDb
        }
    }
    
    Context "File Reading Errors" {
        
        It "Should handle unsupported file types" {
            $testDir = New-TestDirectory -FileCount 1 -FileTypes @('.txt')
            $unsupportedFile = Join-Path $testDir.Path "test.exe"
            Set-Content -Path $unsupportedFile -Value "Binary content"
            
            $content = Get-FileContent -FilePath $unsupportedFile
            
            $content | Should -BeNullOrEmpty
            Remove-TestDirectory -TestDirectory $testDir
        }
        
        It "Should handle empty files" {
            $testDir = New-TestDirectory -FileCount 1 -FileTypes @('.txt')
            $emptyFile = Join-Path $testDir.Path "empty.txt"
            Set-Content -Path $emptyFile -Value ""
            
            $content = Get-FileContent -FilePath $emptyFile
            
            $content | Should -BeNullOrEmpty
            Remove-TestDirectory -TestDirectory $testDir
        }
    }
}
