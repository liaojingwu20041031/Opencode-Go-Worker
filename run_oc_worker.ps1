param(
  [string]$TaskFile = ".ai\OC_TASK.md",
  [string]$Model = "opencode-go/kimi-k2.7-code",
  [string]$Agent = "build",
  [string]$ProjectDir = ".",
  [int]$TimeoutSec = 1800
)

$ErrorActionPreference = "Stop"

function Stop-WithMessage {
  param([string]$Message, [int]$Code = 1)
  Write-Error $Message
  exit $Code
}

function Test-ModelAvailable {
  param([string[]]$Models, [string]$Name)
  return ($Models | Where-Object { $_.Trim() -eq $Name } | Select-Object -First 1) -ne $null
}

$opencodeCommand = Get-Command opencode -ErrorAction SilentlyContinue
if (-not $opencodeCommand) {
  Stop-WithMessage "opencode command not found."
}

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCommand) {
  Stop-WithMessage "git command not found."
}

$resolvedProject = Resolve-Path -LiteralPath $ProjectDir -ErrorAction SilentlyContinue
if (-not $resolvedProject) {
  Stop-WithMessage "ProjectDir not found: $ProjectDir"
}
$projectPath = $resolvedProject.Path

$taskPath = if ([System.IO.Path]::IsPathRooted($TaskFile)) {
  $TaskFile
} else {
  Join-Path $projectPath $TaskFile
}

if (-not (Test-Path -LiteralPath $taskPath -PathType Leaf)) {
  Stop-WithMessage "TaskFile not found: $taskPath"
}

$insideGit = (& git -C $projectPath rev-parse --is-inside-work-tree 2>$null)
if ($LASTEXITCODE -ne 0 -or $insideGit.Trim() -ne "true") {
  Stop-WithMessage "ProjectDir is not inside a git repository: $projectPath"
}

Write-Output "Refreshing OpenCode models..."
& opencode models --refresh
if ($LASTEXITCODE -ne 0) {
  Stop-WithMessage "opencode models --refresh failed."
}

$availableModels = @(& opencode models)
if ($LASTEXITCODE -ne 0) {
  Stop-WithMessage "opencode models failed."
}

if (-not (Test-ModelAvailable -Models $availableModels -Name $Model)) {
  $fallbackModel = "opencode-go/deepseek-v4-flash"
  Write-Warning "Model not found: $Model. Falling back to $fallbackModel."
  $Model = $fallbackModel
}

if (-not (Test-ModelAvailable -Models $availableModels -Name $Model)) {
  Stop-WithMessage "Requested model is not available after fallback: $Model. Run 'opencode models' and pass -Model with an available provider/model."
}

$message = "Strictly execute the task file. Only modify allowed files. Do not do unrelated refactors. Run requested tests if possible. Report changed files, tests, and blockers."

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $opencodeCommand.Source
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.WorkingDirectory = $projectPath
[void]$psi.ArgumentList.Add("run")
[void]$psi.ArgumentList.Add("--agent")
[void]$psi.ArgumentList.Add($Agent)
[void]$psi.ArgumentList.Add("--model")
[void]$psi.ArgumentList.Add($Model)
[void]$psi.ArgumentList.Add("--file")
[void]$psi.ArgumentList.Add($taskPath)
[void]$psi.ArgumentList.Add("--dir")
[void]$psi.ArgumentList.Add($projectPath)
[void]$psi.ArgumentList.Add($message)

Write-Output "Running one-shot opencode run with model: $Model"
$process = [System.Diagnostics.Process]::Start($psi)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$finished = $process.WaitForExit($TimeoutSec * 1000)

if (-not $finished) {
  Write-Warning "Timeout after $TimeoutSec seconds. Terminating only this opencode process tree."
  try {
    $process.Kill($true)
  } catch {
    $process.Kill()
  }
  $process.WaitForExit()
}

$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()

if ($stdout) {
  Write-Output $stdout
}
if ($stderr) {
  Write-Error $stderr
}

$exitCode = if ($finished) { $process.ExitCode } else { 124 }

Write-Output "opencode exit code: $exitCode"
Write-Output "git status --short:"
& git -C $projectPath status --short
Write-Output "git diff --stat:"
& git -C $projectPath diff --stat

exit $exitCode
