#Requires -Version 7.0

<#
.SYNOPSIS
    A simple GUI for interacting with the chat API endpoint.
.DESCRIPTION
    This script provides a graphical user interface to send prompts to the /api/chat endpoint
    and display responses. It maintains conversation context between messages.
.NOTES
    Requires PowerShell 7.0 or later and Windows Forms.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Configuration
$apiBaseUrl = "http://localhost:8081"
$model = "llama3"
$embeddingModel = "mxbai-embed-large:latest"
$maxContextDocs = 5
$threshold = 0.75
$contextOnlyMode = $false
$availableModels = @()

# Initialize messages array with a system message
$global:messages = @(
    @{
        "role" = "system"
        "content" = "You are a helpful assistant."
    }
)
$global:contextId = $null

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Chat API Client"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(500, 400)

# Create chat history textbox (read-only)
$chatHistoryBox = New-Object System.Windows.Forms.RichTextBox
$chatHistoryBox.Location = New-Object System.Drawing.Point(10, 10)
$chatHistoryBox.Size = New-Object System.Drawing.Size(760, 400)
$chatHistoryBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$chatHistoryBox.ReadOnly = $true
$chatHistoryBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$chatHistoryBox.BackColor = [System.Drawing.Color]::White
$chatHistoryBox.ScrollBars = "Vertical"
$form.Controls.Add($chatHistoryBox)

# Create prompt input textbox
$promptBox = New-Object System.Windows.Forms.TextBox
$promptBox.Location = New-Object System.Drawing.Point(10, 420)
$promptBox.Size = New-Object System.Drawing.Size(660, 100)
$promptBox.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$promptBox.Multiline = $true
$promptBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$promptBox.ScrollBars = "Vertical"
$form.Controls.Add($promptBox)

# Create send button
$sendButton = New-Object System.Windows.Forms.Button
$sendButton.Location = New-Object System.Drawing.Point(680, 420)
$sendButton.Size = New-Object System.Drawing.Size(90, 30)
$sendButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$sendButton.Text = "Send"
$form.Controls.Add($sendButton)

# Add a status strip at the bottom
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "Ready"
$statusStrip.Items.Add($statusLabel)
$form.Controls.Add($statusStrip)

# Add models button
$modelsButton = New-Object System.Windows.Forms.Button
$modelsButton.Location = New-Object System.Drawing.Point(680, 460)
$modelsButton.Size = New-Object System.Drawing.Size(90, 30)
$modelsButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$modelsButton.Text = "Models"
$form.Controls.Add($modelsButton)

# Add settings button
$settingsButton = New-Object System.Windows.Forms.Button
$settingsButton.Location = New-Object System.Drawing.Point(680, 500)
$settingsButton.Size = New-Object System.Drawing.Size(90, 30)
$settingsButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$settingsButton.Text = "Settings"
$form.Controls.Add($settingsButton)

# Add clear chat button
$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Location = New-Object System.Drawing.Point(680, 540)
$clearButton.Size = New-Object System.Drawing.Size(90, 30)
$clearButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$clearButton.Text = "Clear Chat"
$form.Controls.Add($clearButton)

# Function to append colored text to the chat history
function Add-ColoredText {
    param (
        [string]$text,
        [System.Drawing.Color]$color,
        [bool]$newLine = $true
    )
    
    $chatHistoryBox.SelectionStart = $chatHistoryBox.TextLength
    $chatHistoryBox.SelectionLength = 0
    $chatHistoryBox.SelectionColor = $color
    $chatHistoryBox.AppendText($text)
    if ($newLine) {
        $chatHistoryBox.AppendText("`r`n")
    }
    $chatHistoryBox.SelectionColor = $chatHistoryBox.ForeColor
    
    # Scroll to the end
    $chatHistoryBox.ScrollToCaret()
}

# Function to send the prompt to the API
function Send-Prompt {
    param (
        [string]$userPrompt
    )
    
    if ([string]::IsNullOrWhiteSpace($userPrompt)) {
        return
    }
    
    # Show user's message in the chat history
    Add-ColoredText "You: " ([System.Drawing.Color]::Blue) $false
    Add-ColoredText $userPrompt ([System.Drawing.Color]::Black)
    Add-ColoredText "" ([System.Drawing.Color]::Black)  # Empty line for spacing
    
    # Add the user message to the messages array
    $global:messages += @{
        "role" = "user"
        "content" = $userPrompt
    }
    
    # Disable UI controls during API call
    $promptBox.Enabled = $false
    $sendButton.Enabled = $false
    $statusLabel.Text = "Thinking..."
    
    # Prepare the request body
    $requestBody = @{
        "messages" = $global:messages
        "model" = $model
        "max_context_docs" = $maxContextDocs
        "threshold" = $threshold
        "enhance_context" = $true
        "context_only" = $contextOnlyMode
    }
    
    # Add context ID if we have one (for continuing the conversation)
    if ($global:contextId) {
        $requestBody["context"] = $global:contextId
    }
    
    # Convert to JSON
    $jsonBody = $requestBody | ConvertTo-Json -Depth 10
    
    try {
        # Send the request to the API
        $response = Invoke-RestMethod -Uri "$apiBaseUrl/api/chat" -Method Post -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
        
        # Show assistant's response in the chat history
        Add-ColoredText "Assistant: " ([System.Drawing.Color]::Green) $false
        Add-ColoredText $response.message.content ([System.Drawing.Color]::Black)
        
        # Show context information if any
        if ($response.context_count -gt 0) {
            Add-ColoredText "" ([System.Drawing.Color]::Black)  # Empty line for spacing
            Add-ColoredText "Context Sources:" ([System.Drawing.Color]::DarkGray)
            foreach ($ctx in $response.context_info) {
                # Extract filename and line range information
                $filename = Split-Path -Leaf $ctx.source
                $lineRange = if ($ctx.line_range) { $ctx.line_range } else { "N/A" }
                
                # Format the context information
                Add-ColoredText "- File: " ([System.Drawing.Color]::DarkGray) $false
                Add-ColoredText "$filename" ([System.Drawing.Color]::Blue) $false
                Add-ColoredText " | Lines: " ([System.Drawing.Color]::DarkGray) $false
                Add-ColoredText "$lineRange" ([System.Drawing.Color]::Purple) $false
                Add-ColoredText " | Similarity: $([math]::Round($ctx.similarity, 2))" ([System.Drawing.Color]::DarkGray)
                
                # Add more details if available
                if ($ctx.metadata -and $ctx.metadata.ContainsKey('chunk_id')) {
                    Add-ColoredText "  Chunk ID: $($ctx.metadata.chunk_id)" ([System.Drawing.Color]::DarkGray)
                }
            }
        }
        
        Add-ColoredText "" ([System.Drawing.Color]::Black)  # Empty line for spacing
        
        # Add the assistant message to the messages array
        $global:messages += @{
            "role" = "assistant"
            "content" = $response.message.content
        }
        
        # Save the context ID if provided
        if ($response.context) {
            $global:contextId = $response.context
        }
        
        $statusLabel.Text = "Ready"
    }
    catch {
        $errorMessage = "Error: $_"
        Add-ColoredText $errorMessage ([System.Drawing.Color]::Red)
        $statusLabel.Text = "Error occurred"
    }
    finally {
        # Re-enable UI controls
        $promptBox.Enabled = $true
        $sendButton.Enabled = $true
        $promptBox.Clear()
        $promptBox.Focus()
    }
}

# Function to fetch available models from the API
function Get-AvailableModels {
    try {
        $response = Invoke-RestMethod -Uri "$apiBaseUrl/api/models?include_details=true" -Method Get -ErrorAction Stop
        $script:availableModels = $response.models
        return $response.models
    }
    catch {
        Add-ColoredText "Error fetching models: $_" ([System.Drawing.Color]::Red)
        return @()
    }
}

# Function to show available models dialog
function Show-ModelsDialog {
    # Fetch latest models
    $statusLabel.Text = "Fetching models..."
    $models = Get-AvailableModels
    $statusLabel.Text = "Ready"
    
    if ($models.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No models found or couldn't connect to the API.", "Models", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    
    # Create dialog
    $modelsForm = New-Object System.Windows.Forms.Form
    $modelsForm.Text = "Available Models"
    $modelsForm.Size = New-Object System.Drawing.Size(500, 400)
    $modelsForm.StartPosition = "CenterParent"
    
    # Create list view to display models
    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(10, 10)
    $listView.Size = New-Object System.Drawing.Size(460, 300)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.FullRowSelect = $true
    $listView.GridLines = $true
    
    # Add columns
    $listView.Columns.Add("Name", 200) | Out-Null
    $listView.Columns.Add("Size", 80) | Out-Null
    $listView.Columns.Add("Modified", 160) | Out-Null
    
    # Add models to list
    foreach ($model in $models) {
        $item = New-Object System.Windows.Forms.ListViewItem($model.name)
        # Format size as MB
        $sizeInMB = [math]::Round($model.size / 1024 / 1024, 2)
        $item.SubItems.Add("$sizeInMB MB")
        
        # Format date if available
        if ($model.modified_at) {
            try {
                $date = [datetime]::Parse($model.modified_at)
                $formattedDate = $date.ToString("yyyy-MM-dd HH:mm:ss")
                $item.SubItems.Add($formattedDate)
            }
            catch {
                $item.SubItems.Add($model.modified_at.ToString("yyyy-MM-dd HH:mm:ss"))
            }
        }
        else {
            $item.SubItems.Add("")
        }
        
        $listView.Items.Add($item) | Out-Null
    }
    
    $modelsForm.Controls.Add($listView)
    
    # Use selected model button
    $useButton = New-Object System.Windows.Forms.Button
    $useButton.Location = New-Object System.Drawing.Point(10, 320)
    $useButton.Size = New-Object System.Drawing.Size(120, 30)
    $useButton.Text = "Use as Chat Model"
    $useButton.Add_Click({
        if ($listView.SelectedItems.Count -gt 0) {
            $script:model = $listView.SelectedItems[0].Text
            $statusLabel.Text = "Model set to: $model"
            $modelsForm.Close()
        }
    })
    $modelsForm.Controls.Add($useButton)
    
    
    # Close button
    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Location = New-Object System.Drawing.Point(140, 320)
    $closeButton.Size = New-Object System.Drawing.Size(80, 30)
    $closeButton.Text = "Close"
    $closeButton.Add_Click({
        $modelsForm.Close()
    })
    $modelsForm.Controls.Add($closeButton)
    
    # Show dialog
    $modelsForm.ShowDialog() | Out-Null
}

# Function to create settings dialog
function Show-SettingsDialog {
    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text = "Settings"
    $settingsForm.Size = New-Object System.Drawing.Size(400, 360)
    $settingsForm.StartPosition = "CenterParent"
    $settingsForm.FormBorderStyle = "FixedDialog"
    $settingsForm.MaximizeBox = $false
    $settingsForm.MinimizeBox = $false
    
    $y = 20
    
    # API URL
    $urlLabel = New-Object System.Windows.Forms.Label
    $urlLabel.Location = New-Object System.Drawing.Point(20, $y)
    $urlLabel.Size = New-Object System.Drawing.Size(150, 20)
    $urlLabel.Text = "API URL:"
    $settingsForm.Controls.Add($urlLabel)
    
    $urlTextBox = New-Object System.Windows.Forms.TextBox
    $urlTextBox.Location = New-Object System.Drawing.Point(180, $y)
    $urlTextBox.Size = New-Object System.Drawing.Size(180, 20)
    $urlTextBox.Text = $apiBaseUrl
    $settingsForm.Controls.Add($urlTextBox)
    $y += 40
    
    # Model
    $modelLabel = New-Object System.Windows.Forms.Label
    $modelLabel.Location = New-Object System.Drawing.Point(20, $y)
    $modelLabel.Size = New-Object System.Drawing.Size(150, 20)
    $modelLabel.Text = "Model:"
    $settingsForm.Controls.Add($modelLabel)
    
    $modelTextBox = New-Object System.Windows.Forms.TextBox
    $modelTextBox.Location = New-Object System.Drawing.Point(180, $y)
    $modelTextBox.Size = New-Object System.Drawing.Size(180, 20)
    $modelTextBox.Text = $model
    $settingsForm.Controls.Add($modelTextBox)
    $y += 40
    
    # Context Docs
    $docsLabel = New-Object System.Windows.Forms.Label
    $docsLabel.Location = New-Object System.Drawing.Point(20, $y)
    $docsLabel.Size = New-Object System.Drawing.Size(150, 20)
    $docsLabel.Text = "Max Context Docs:"
    $settingsForm.Controls.Add($docsLabel)
    
    $docsNumeric = New-Object System.Windows.Forms.NumericUpDown
    $docsNumeric.Location = New-Object System.Drawing.Point(180, $y)
    $docsNumeric.Size = New-Object System.Drawing.Size(180, 20)
    $docsNumeric.Minimum = 1
    $docsNumeric.Maximum = 20
    $docsNumeric.Value = $maxContextDocs
    $settingsForm.Controls.Add($docsNumeric)
    $y += 40
    
    # Threshold
    $thresholdLabel = New-Object System.Windows.Forms.Label
    $thresholdLabel.Location = New-Object System.Drawing.Point(20, $y)
    $thresholdLabel.Size = New-Object System.Drawing.Size(150, 20)
    $thresholdLabel.Text = "Relevance Threshold:"
    $settingsForm.Controls.Add($thresholdLabel)
    
    $thresholdNumeric = New-Object System.Windows.Forms.NumericUpDown
    $thresholdNumeric.Location = New-Object System.Drawing.Point(180, $y)
    $thresholdNumeric.Size = New-Object System.Drawing.Size(180, 20)
    $thresholdNumeric.Minimum = 0
    $thresholdNumeric.Maximum = 1
    $thresholdNumeric.DecimalPlaces = 2
    $thresholdNumeric.Increment = 0.05
    $thresholdNumeric.Value = $threshold
    $settingsForm.Controls.Add($thresholdNumeric)
    $y += 40
    
    # Context-only Mode
    $contextOnlyLabel = New-Object System.Windows.Forms.Label
    $contextOnlyLabel.Location = New-Object System.Drawing.Point(20, $y)
    $contextOnlyLabel.Size = New-Object System.Drawing.Size(150, 20)
    $contextOnlyLabel.Text = "Context-only Mode:"
    $settingsForm.Controls.Add($contextOnlyLabel)
    
    $contextOnlyCheckbox = New-Object System.Windows.Forms.CheckBox
    $contextOnlyCheckbox.Location = New-Object System.Drawing.Point(180, $y)
    $contextOnlyCheckbox.Size = New-Object System.Drawing.Size(180, 20)
    $contextOnlyCheckbox.Text = "Use only context knowledge"
    $contextOnlyCheckbox.Checked = $contextOnlyMode
    $settingsForm.Controls.Add($contextOnlyCheckbox)
    $y += 40
    
    # System Prompt
    $promptLabel = New-Object System.Windows.Forms.Label
    $promptLabel.Location = New-Object System.Drawing.Point(20, $y)
    $promptLabel.Size = New-Object System.Drawing.Size(150, 20)
    $promptLabel.Text = "System Prompt:"
    $settingsForm.Controls.Add($promptLabel)
    
    $promptTextBox = New-Object System.Windows.Forms.TextBox
    $promptTextBox.Location = New-Object System.Drawing.Point(180, $y)
    $promptTextBox.Size = New-Object System.Drawing.Size(180, 60)
    $promptTextBox.Multiline = $true
    $promptTextBox.Text = $global:messages[0].content
    $settingsForm.Controls.Add($promptTextBox)
    $y += 80
    
    # Save/Cancel Buttons
    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Location = New-Object System.Drawing.Point(100, $y)
    $saveButton.Size = New-Object System.Drawing.Size(80, 30)
    $saveButton.Text = "Save"
    $saveButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $settingsForm.Controls.Add($saveButton)
    
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(200, $y)
    $cancelButton.Size = New-Object System.Drawing.Size(80, 30)
    $cancelButton.Text = "Cancel"
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $settingsForm.Controls.Add($cancelButton)
    
    # Set accept button
    $settingsForm.AcceptButton = $saveButton
    $settingsForm.CancelButton = $cancelButton
    
    # Show dialog and process result
    $result = $settingsForm.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:apiBaseUrl = $urlTextBox.Text
        $script:model = $modelTextBox.Text
        $script:maxContextDocs = $docsNumeric.Value
        $script:threshold = $thresholdNumeric.Value
        $script:contextOnlyMode = $contextOnlyCheckbox.Checked
        
        # Update system message
        $global:messages[0].content = $promptTextBox.Text
        
        # Reset context ID if settings changed
        $global:contextId = $null
        
        $statusLabel.Text = "Settings updated"
    }
}

# Event handler for the Send button
$sendButton.Add_Click({
    Send-Prompt -userPrompt $promptBox.Text
})

# Event handler for pressing Enter in the text box (without Shift)
$promptBox.Add_KeyDown({
    param($sender, $e)
    
    if ($e.KeyCode -eq 'Enter' -and -not $e.Shift) {
        $e.SuppressKeyPress = $true  # Suppress adding a newline character
        Send-Prompt -userPrompt $promptBox.Text
    }
})

# Event handler for Models button
$modelsButton.Add_Click({
    Show-ModelsDialog
})

# Event handler for Settings button
$settingsButton.Add_Click({
    Show-SettingsDialog
})

# Event handler for Clear Chat button
$clearButton.Add_Click({
    $chatHistoryBox.Clear()
    
    # Reset messages to just the system message
    $systemPrompt = $global:messages[0].content
    $global:messages = @(
        @{
            "role" = "system"
            "content" = $systemPrompt
        }
    )
    
    # Reset context ID
    $global:contextId = $null
    
    $statusLabel.Text = "Chat cleared"
})

# Display initial instructions
Add-ColoredText "Chat API Client" ([System.Drawing.Color]::DarkBlue)
Add-ColoredText "Type your message in the text box below and press Enter or click Send to chat." ([System.Drawing.Color]::DarkGray)
Add-ColoredText "Use the Settings button to configure the API URL, model, and other parameters." ([System.Drawing.Color]::DarkGray)
Add-ColoredText "" ([System.Drawing.Color]::Black)  # Empty line for spacing

# Show the form
$form.Add_Shown({$promptBox.Focus()})
[void]$form.ShowDialog()
