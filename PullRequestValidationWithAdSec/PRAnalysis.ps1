# Get input parameters
[bool]$enableDependencyAlertsAnalysis = Get-VstsInput -Name EnableDependencyAlertsAnalysis -AsBool
[bool]$enableCodeAlertsAnalysis = Get-VstsInput -Name EnableCodeAlertsAnalysis -AsBool

# Constants
$ADVANCED_SECURITY_URI = "https://advsec.dev.azure.com"
$OrganizationName = "SET_YOUR_ORGANIZATION_NAME"
$sourceBranchRef = "refs/pull/$($env:System_PullRequest_PullRequestId)/merge"
$targetBranchRef = $($env:System_PullRequest_TargetBranch)

# Function Add-AlertToMarkdown
function Add-AlertToMarkdown {
    param (
        [System.Object[]]$Alerts,
        [bool]$IsSourceBranch,
        [string]$Markdown
    )

    foreach ($alert in $Alerts) {
        $name = $alert.title
        $severity = $alert.severity
        $description = $alert.tools.rules.description

        $path = $alert.physicalLocations[0].filePath
        $slashCount = 0
        $modifiedPath = ""
        for ($i = 0; $i -lt $path.Length; $i++) {
            if ($path[$i] -eq '/') {
                $slashCount++
                $modifiedPath += $path[$i]
                if ($slashCount % 2 -eq 0) {
                    $modifiedPath += ' '
                }
            } else {
                $modifiedPath += $path[$i]
            }
        }
        $location = "[$modifiedPath]($($alert.physicalLocations[0].versionControl.itemUrl))"

        $branchRef = if ($IsSourceBranch) {
            "refs/pull/$($env:System_PullRequest_PullRequestId)/merge"
        } else {
            $env:System_PullRequest_TargetBranch
        }
        $link = "[View Details]($($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$env:SYSTEM_TEAMPROJECTID/_git/$($env:Build_Repository_Name)/alerts/$($alert.alertId)?branch=$branchRef)"

        # Add a row to the Markdown table
        $Markdown += "|$name|$severity|$description|$location|$link|\n"
    }

    return $Markdown
}

# Functions Get-Alerts
function Get-Alerts {
    param (
        [string]$BranchRef,
        [string]$AlertType
    )
    $url = "$($ADVANCED_SECURITY_URI)/$OrganizationName/$env:SYSTEM_TEAMPROJECTID/_apis/alert/repositories/$($env:Build_Repository_Name)/alerts?criteria.ref=$BranchRef&criteria.states=active&criteria.alertType=$AlertType&api-version=7.2-preview.1"
    Write-Host "Active $AlertType Alerts from Branch -> GET $url"
    $response = Invoke-RestMethod -Uri $url -Method GET -Headers @{Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN"} -ErrorAction SilentlyContinue
    return $response.value
}

# Get all threads in the pull request
try {
    $getThreadsUrl = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$env:SYSTEM_TEAMPROJECTID/_apis/git/repositories/$($env:Build_Repository_Name)/pullRequests/$($env:System_PullRequest_PullRequestId)/threads?api-version=7.2-preview.1"
    Write-Host "GET all threads from $getThreadsUrl"  
    $threadsResponse = Invoke-RestMethod -Uri $getThreadsUrl -Method GET -Headers @{Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN"} 
    $threads = $threadsResponse.value     
    Write-Host "Response: " ($threadsResponse.value | ConvertTo-Json -Depth 5)
}
catch {
    Write-Error "Error getting threads: $_"
}

# Search for threads with comments containing the content 'Dependency & Code Scan Analysis' and close the threads
$StatusCode = "closed" #Closed
foreach ($thread in $threads) {
    foreach ($comment in $thread.comments) {
        if ($comment.content -like '*Dependency & Code Scan Analysis*') {
            if ($thread.status -ne $StatusCode) {
              $closeThreadUrl = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$env:SYSTEM_TEAMPROJECTID/_apis/git/repositories/$($env:Build_Repository_Name)/pullRequests/$($env:System_PullRequest_PullRequestId)/threads/$($thread.id)?api-version=7.2-preview.1"
              $closeThreadBody = @{
                status = $StatusCode
              } | ConvertTo-Json

              try {
                Write-Host "Closed thread with id $($thread.id)"
                Invoke-RestMethod -Uri $closeThreadUrl -Method PATCH -Headers @{Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN"} -Body $closeThreadBody -ContentType application/json                 
              }
              catch {
                Write-Error "Error closing thread: $_"
              }
            }            
        }
    }
}

# Set Base Status Code of Thread as "Resolved"
$StatusCode = 2 #Resolved
# Build Up a Markdown Message to 
$Markdown = @"

## **Dependency & Code Scan Analysis**

---

### **Dependency Analysis**

"@

# Check For Dependency Vulnerabilities
if ($enableDependencyAlertsAnalysis -eq $true) {
  try {
      # Get active Dependency Alerts in the Source Branch
      $activeDependencyAlerts = Get-Alerts -BranchRef $sourceBranchRef -AlertType "dependency"

      # Get active Dependency Alerts in the Target Branch
      $activeTargetBranchDependencyAlerts = Get-Alerts -BranchRef $targetBranchRef -AlertType "dependency"

      # New Alerts: Compare and Get Dependency Alerts that exist in the Source Branch but not in the Target Branch
      $newlyActivatedDependencyAlerts = $activeDependencyAlerts | Where-Object { 
          $alert = $_; -not ($activeTargetBranchDependencyAlerts | Where-Object { $_.alertId -eq $alert.alertId }) 
      }    
      Write-Host "Newly Activated Dependency Alerts:" ($newlyActivatedDependencyAlerts | ConvertTo-Json -Depth 5)

      if ($newlyActivatedDependencyAlerts.count -ne 0) {
        $StatusCode = 1 #Active
        $Markdown += @"
#### :x: Dependency Alerts

| **Title** | **Severity** | **Description/Recommendation** | **Vulnerability Location - $env:System_PullRequest_SourceBranch** | **Details** |
|---------|---------|---------|---------|---------| 

"@
      } else {      
        $Markdown += @"
#### :white_check_mark: Dependency Alerts

No New Depedency Alerts Found. **Dependencies are Secure :rocket:**

"@
      }
      # Add a row to the Markdown table
      $Markdown = Add-AlertToMarkdown -Alerts $newlyActivatedDependencyAlerts -IsSourceBranch $true -Markdown $Markdown

      # Fixed Alerts: Compare and Get Dependency Alerts that exist in Target Branch but not in Source Branch
      $fixedDependencyAlerts = $activeTargetBranchDependencyAlerts | Where-Object { 
        $alert = $_; -not ($activeDependencyAlerts | Where-Object { $_.alertId -eq $alert.alertId }) 
      } 
      Write-Host "Fixed Dependency Alerts:" ($fixedDependencyAlerts | ConvertTo-Json -Depth 5)
      if ($fixedDependencyAlerts.count -ne 0) {
        $Markdown += @"
#### :beginner: Fixed Dependency Alerts

| **Title** | **Severity** | **Description/Recommendation** | **Vulnerability Location - $env:System_PullRequest_TargetBranch** | **Details** |
|---------|---------|---------|---------|---------| 

"@
        # Add a row to the Markdown table
        $Markdown = Add-AlertToMarkdown -Alerts $fixedDependencyAlerts -IsSourceBranch $false -Markdown $Markdown
      }
  }
  catch {
    Write-Error $_.Exception.Message
  }
} else {
  $Markdown += @"
#### :warning: Dependency Alerts

The Analysis for Dependency Alerts has been **disabled** in the Pipeline Task.

"@
}


$Markdown += @"

---

### **Code Analysis**

"@

# Check For Code Vulnerabilities
if ($enableCodeAlertsAnalysis -eq $true) {
  try {
      # Get active Code Alerts in the Source Branch
      $activeCodeAlerts = Get-Alerts -BranchRef $sourceBranchRef -AlertType "code"

      # Get active Code Alerts in the Target Branch
      $activeTargetBranchCodeAlerts = Get-Alerts -BranchRef $targetBranchRef -AlertType "code"

      # New Alerts:  Compare and Get Dependency Alerts that exist in the Source Branch but not in the Target Branch
      $newlyActivatedCodeAlerts = $activeCodeAlerts | Where-Object { 
          $alert = $_; -not ($activeTargetBranchCodeAlerts | Where-Object { $_.alertId -eq $alert.alertId }) 
      }   

      Write-Host "Newly Activated Code Alerts:" ($newlyActivatedCodeAlerts | ConvertTo-Json -Depth 5)

      if ($newlyActivatedCodeAlerts.count -ne 0) {
        $StatusCode = 1 #Active
        $Markdown += @"
#### :x: Code Alerts

| **Title** | **Severity** | **Description/Recommendation** | **Vulnerability Location - $env:System_PullRequest_SourceBranch** | **Details** |
|---------|---------|---------|---------|---------| 

"@
      } else {
          $Markdown += @"
#### :white_check_mark:  Code Alerts

No New Code Alerts Found. **Code is Secure :rocket:**

"@
      }
      # Add a row to the Markdown table
      $Markdown = Add-AlertToMarkdown -Alerts $newlyActivatedCodeAlerts -IsSourceBranch $true -Markdown $Markdown

      # Fixed Alerts: Compare and Get Dependency Alerts that exist in Target Branch but not in Source Branch
      $fixedCodeAlerts = $activeTargetBranchCodeAlerts | Where-Object { 
        $alert = $_; -not ($activeCodeAlerts | Where-Object { $_.alertId -eq $alert.alertId }) 
      } 
      Write-Host "Fixed Dependency Alerts:" ($fixedCodeAlerts | ConvertTo-Json -Depth 5)
      if ($fixedCodeAlerts.count -ne 0) {
        $Markdown += @"
#### :beginner: Fixed Code Alerts 

| **Title** | **Severity** | **Description/Recommendation** | **Vulnerability Location - $env:System_PullRequest_TargetBranch** | **Details** |
|---------|---------|---------|---------|---------| 

"@
        # Add a row to the Markdown table
        $Markdown = Add-AlertToMarkdown -Alerts $fixedCodeAlerts -IsSourceBranch $false -Markdown $Markdown
        if ($newlyActivatedCodeAlerts.count -ne 0) {
          $Markdown += @"
##### :warning: **Warning**: Modifying files with existing **code vulnerabilities** in the target branch may cause those vulnerabilities to be marked as both **new** and **fixed** in this PR. Please double-check these findings.
"@
        }  
      }
  }
  catch {
    Write-Error $_.Exception.Message
  }
} else {
  $Markdown += @"
#### :warning: Code Alerts

The Analysis for Code Alerts has been **disabled** in the Pipeline Task.

"@
}

#Build the JSON body up
$body = @"
{
    "comments": [
      {
        "parentCommentId": 0,
        "content": "$Markdown",
        "commentType": 1
      }
    ],
    "status": $StatusCode 
  }
"@

#Post the message to the Pull Request, Creating new Thread in PR
try {
    $newThreadUrl = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$env:SYSTEM_TEAMPROJECTID/_apis/git/repositories/$($env:Build_Repository_Name)/pullRequests/$($env:System_PullRequest_PullRequestId)/threads?api-version=7.2-preview.1"
    Write-Host "Creating new Thread -> Post $newThreadUrl"
    $response = Invoke-RestMethod -Uri $newThreadUrl -Method POST -Headers @{Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN"} -Body $Body -ContentType application/json
  if ($Null -ne $response) {
    Write-Host "Created Thread with id $($response.id)"
  }
}
catch {
  Write-Error $_
  Write-Error $_.Exception.Message
}
