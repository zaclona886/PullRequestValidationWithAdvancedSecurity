# Extension Task  for Azure DevOps - Pull Request Validation with Advanced Secuirty

This task is designed to validate Pull Requests by analyzing results from Advanced Security Scans. Results are then posted to the Pull Request comment section, providing immediate and actionable feedback within your development workflow.

## Getting Started

The foundation of this Azure Pipeline Task, which utilizes PowerShell, is based on [VstsTaskSdk](https://github.com/microsoft/azure-pipelines-task-lib/blob/master/powershell/Docs/README.md).

#### Steps which were Done (you dont need to do those)

1. **Install VstsTaskSdk**: Use the command below to install and save the VstsTaskSdk module. This saves the module to a specified path for later use.

   ```powershell
   Save-Module –Name VstsTaskSdk –Path .\PullRequestValidationWithAdSec\ps_modules –Force
   ```
2. **Prepare the Module**: After installation, extract the contents of `\PullRequestValidationWithAdSec\ps_modules\VstsTaskSdk\x.x.x` and paste them into . `\PullRequestValidationWithAdSec\ps_modules\VstsTaskSdk`. 

3. **Create Task Configuration**: Within the  `\PullRequestValidationWithAdSec\` directory, create a task.json and `script.ps1`. The `task.json` file must adhere to a specific structure to be recognized by Azure Pipelines.

4. **Set Up Extension Manifest**: At the root level, create a `vss-extension.json` file. This file also needs to follow a specific structure for the extension to be correctly packaged and deployed.

## Instalation Instructions & Required Changes

### Instalation
You need to install `TFX` to be able to package extension.
   ```powershell
   npm install -g tfx-cli
   ```

### Required Changes
You need to set your **OrganizationName** in `PullRequestValidationWithAdSec/PRAnalysis.ps1` to configure the task to work properly with your organization.

#### Attributes to change in Manifest Files
For `task.json` & `vss-extension.json`, "id", "author", "name" needs to be changed for yours. You can also change `img/icon.png` (Size 220x220).

## Release and Deploy
### Manual
1. **Versioning**: If changes are made to the `PRAnalysis.ps1` script, remember to update the version in `task.json`.
To update the extension on the Marketplace, you must also update the version in the `vss-extenstion.json` file.
It's a good practice to synchronize the version numbers in both `task.json` and `vss-extension.json`.

2. **Package**: To build and package the extension, use the command below. This generates a `.vsix` file which is used for distribution.

   ```powershell
   tfx extension create --manifest-globs vss-extension.json
   ```
   
2. **Upload to Microsoft Marketplace**: After packaging, upload the `.vsix` file to the **[Microsoft Extension Marketplace](https://marketplace.visualstudio.com/)** through the Azure DevOps portal.

3. **Share and install**: Share it with your organization and install it.

### Automated
Use **[Azure DevOps Extension Tasks](https://marketplace.visualstudio.com/items?itemName=ms-devlabs.vsts-developer-tools-build-tasks)** for automated release and deploy if code is stored inside a Azure DevOps.

## How to Use
To allow a pipeline to contribute to a Pull Request, the Build Service requires specific permissions:
  - **Contribute to pull request**: Set to Allow.
  - **Advanced Security: view alerts**: Set to Allow.

These permissions can be configured under **Project settings -> Repositories -> Security -> Build Service (User)**.

### Pre-requisites for Pull Request Validation
Ensure that **[Code Scan and Dependency Scan by Azure DevOps Advanced Security](https://learn.microsoft.com/en-us/azure/devops/repos/security/configure-github-advanced-security-features?view=azure-devops&tabs=yaml)** are executed before this task in the pipeline for correct Pull Request validation.

### Task Configuration Example
Below is an example of how to use this task in your pipeline together with Code and Dependency Scan, including the necessary parameters for enabling Code Alerts and Dependency Alerts Analysis:

#### pipeline.yml

```yaml
trigger: none

pool:
  vmImage: 'windows-latest'

jobs:
  - job: Autobuild_Dependancy_And_Code_Scan
    steps:
    
    # Init CodeQL
    - task: AdvancedSecurity-Codeql-Init@1
      displayName: 'Init CodeQL'
      inputs: 
        languages: 'csharp'
    
    # AutoBuild project 
    - task: AdvancedSecurity-Codeql-Autobuild@1
      displayName: 'AutoBuild'
    
    # Run dependency scanning 
    - task: AdvancedSecurity-Dependency-Scanning@1
      displayName: 'Dependency Scan'
    
    # Run code scanning  
    - task: AdvancedSecurity-Codeql-Analyze@1
      displayName: 'Code Scan'

    # PR Validation
    - job: PullRequestValidationJob
      displayName: 'Pull Request Validation'
      steps:
      - task: PullRequestValidationWithAdSec@1
        inputs:
          EnableCodeAlertsAnalysis: true
          EnableDependencyAlertsAnalysis: true
        env:
          SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```
