# Vectors-Core.Tests.ps1
# Unit tests for Vectors-Core module

BeforeAll {
    # Import the module to test
    $modulePath = Join-Path $PSScriptRoot "..\..\..\Vectors\Modules\Vectors-Core.psm1"
    Import-Module $modulePath -Force
    
    # Import test helpers
    $testHelpersPath = Join-Path $PSScriptRoot "..\..\..\Tests\TestHelpers.psm1"
    Import-Module $testHelpersPath -Force
}

Describe "Vectors-Core Module" -Tag "Unit" {
    
    Context "Initialize-VectorsConfig" {
        
        It "Should initialize with default configuration" {
            $config = Initialize-VectorsConfig
            
            $config | Should -Not -BeNullOrEmpty
            $config.OllamaUrl | Should -Be "http://localhost:11434"
            $config.EmbeddingModel | Should -Be "mxbai-embed-large:latest"
            $config.ChunkSize | Should -Be 20
            $config.ChunkOverlap | Should -Be 2
        }
        
        It "Should override configuration with custom values" {
            $customConfig = @{
                OllamaUrl = "http://localhost:9999"
                ChunkSize = 50
                ChunkOverlap = 5
            }
            
            $config = Initialize-VectorsConfig -ConfigOverrides $customConfig
            
            $config.OllamaUrl | Should -Be "http://localhost:9999"
            $config.ChunkSize | Should -Be 50
            $config.ChunkOverlap | Should -Be 5
            # Default values should remain
            $config.EmbeddingModel | Should -Be "mxbai-embed-large:latest"
        }
    }
    
    Context "Get-VectorsConfig" {
        
        It "Should return current configuration" {
            $config = Get-VectorsConfig
            
            $config | Should -Not -BeNullOrEmpty
            $config.Keys | Should -Contain "OllamaUrl"
            $config.Keys | Should -Contain "EmbeddingModel"
            $config.Keys | Should -Contain "ChunkSize"
        }
    }
    
    Context "Write-VectorsLog" {
        
        It "Should log Info level messages" {
            { Write-VectorsLog -Message "Test info message" -Level "Info" } | Should -Not -Throw
        }
        
        It "Should log Warning level messages" {
            { Write-VectorsLog -Message "Test warning message" -Level "Warning" } | Should -Not -Throw
        }
        
        It "Should log Error level messages" {
            { Write-VectorsLog -Message "Test error message" -Level "Error" } | Should -Not -Throw
        }
        
        It "Should handle hashtable messages" {
            $hashMessage = @{
                Action = "Processing"
                File = "test.txt"
                Status = "Success"
            }
            { Write-VectorsLog -Message $hashMessage -Level "Info" } | Should -Not -Throw
        }
    }
    
    Context "Get-FileContent" {
        
        BeforeEach {
            $script:testDir = New-TestDirectory -FileCount 2 -FileTypes @('.txt', '.md')
        }
        
        AfterEach {
            Remove-TestDirectory -TestDirectory $script:testDir
        }
        
        It "Should read content from a valid text file" {
            $content = Get-FileContent -FilePath $script:testDir.Files[0]
            
            $content | Should -Not -BeNullOrEmpty
            $content | Should -BeOfType [string]
        }
        
        It "Should read content from a valid markdown file" {
            $content = Get-FileContent -FilePath $script:testDir.Files[1]
            
            $content | Should -Not -BeNullOrEmpty
            $content | Should -BeOfType [string]
        }
        
        It "Should return null for non-existent file" {
            $content = Get-FileContent -FilePath "C:\NonExistent\File.txt"
            
            $content | Should -BeNullOrEmpty
        }
        
        It "Should return null for unsupported file extension" {
            $tempFile = Join-Path $script:testDir.Path "test.exe"
            Set-Content -Path $tempFile -Value "Binary content"
            
            $content = Get-FileContent -FilePath $tempFile
            
            $content | Should -BeNullOrEmpty
        }
        
        It "Should handle empty files" {
            $emptyFile = Join-Path $script:testDir.Path "empty.txt"
            Set-Content -Path $emptyFile -Value ""
            
            $content = Get-FileContent -FilePath $emptyFile
            
            $content | Should -BeNullOrEmpty
        }
    }
    
    Context "Test-VectorsRequirements" {
        
        It "Should check PowerShell version" {
            # This test will run but result depends on environment
            { Test-VectorsRequirements } | Should -Not -Throw
        }
        
        # Note: This test requires Ollama to be running
        # It's marked as integration test behavior
        It "Should check Ollama availability (if running)" -Skip {
            $result = Test-VectorsRequirements
            # Result depends on environment, just ensure it doesn't throw
        }
    }
}

Describe "Vectors-Core Integration" -Tag "Integration" {
    
    BeforeAll {
        $script:testConfig = New-TestConfig
        Initialize-VectorsConfig -ConfigOverrides @{
            OllamaUrl = $script:testConfig.OllamaUrl
            EmbeddingModel = $script:testConfig.EmbeddingModel
        }
    }
    
    Context "Configuration Persistence" {
        
        It "Should maintain configuration across multiple calls" {
            $config1 = Get-VectorsConfig
            $config2 = Get-VectorsConfig
            
            $config1.OllamaUrl | Should -Be $config2.OllamaUrl
            $config1.ChunkSize | Should -Be $config2.ChunkSize
        }
        
        It "Should allow configuration updates" {
            $newConfig = @{ ChunkSize = 30 }
            Initialize-VectorsConfig -ConfigOverrides $newConfig
            
            $config = Get-VectorsConfig
            $config.ChunkSize | Should -Be 30
        }
    }
    
    Context "File Processing Pipeline" {
        
        BeforeEach {
            $script:testDir = New-TestDirectory -FileCount 3 -FileTypes @('.txt', '.md', '.json')
        }
        
        AfterEach {
            Remove-TestDirectory -TestDirectory $script:testDir
        }
        
        It "Should process multiple files in sequence" {
            $contents = @()
            
            foreach ($file in $script:testDir.Files) {
                $content = Get-FileContent -FilePath $file
                if ($content) {
                    $contents += $content
                }
            }
            
            $contents.Count | Should -Be 3
            foreach ($content in $contents) {
                $content | Should -Not -BeNullOrEmpty
            }
        }
    }
}
