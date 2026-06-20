param(
  [string]$TaskFile = ".ai\OC_TASK.md",
  [string]$Model = "",
  [string]$ProviderPreference = "opencode-go,opencode,copilot,github-copilot,gemini,google",
  [bool]$AllowFreeFallback = $true,
  [switch]$AllowPaidFallback,
  [ValidateSet("auto", "small", "coding", "hard", "review", "docs")]
  [string]$ModelIntent = "auto",
  [ValidateSet("auto", "build", "plan", "explore", "scout")]
  [string]$Agent = "auto",
  [ValidateSet("USER_TASK", "MAINTAIN_SKILL")]
  [string]$Mode = "USER_TASK",
  [string]$ProjectDir = ".",
  [int]$TimeoutSec = 1800,
  [switch]$DryRun,
  [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
  @"
opencode-go-worker PowerShell wrapper

Runs one short-lived opencode run. Codex decides whether to run another round.

Parameters:
  -TaskFile <path>                 Default: .ai\OC_TASK.md
  -Model <provider/model>          Optional. If set, must exist in opencode models.
  -ProviderPreference <csv>        Default: opencode-go,opencode,copilot,github-copilot,gemini,google
  -AllowFreeFallback <bool>        Default: true
  -AllowPaidFallback               Allow paid providers when no preferred/free model is available.
  -ModelIntent <auto|small|coding|hard|review|docs>
  -Agent <auto|build|plan|explore|scout>
  -Mode <USER_TASK|MAINTAIN_SKILL> Default: USER_TASK
  -ProjectDir <path>               Default: .
  -TimeoutSec <seconds>            Default: 1800
  -DryRun                          Do not run opencode. Check ProjectDir, resolve model, print command.
  -Help                            Show this help.

Examples:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\run_oc_worker.ps1 -DryRun
  powershell -NoProfile -ExecutionPolicy Bypass -File .\run_oc_worker.ps1 -ModelIntent coding -ProjectDir C:\repo
"@
}

function Stop-WithMessage {
  param([string]$Message, [int]$Code = 1)
  [Console]::Error.WriteLine($Message)
  exit $Code
}

function Get-ProviderName {
  param([string]$ModelName)
  if ($ModelName -match "^([^/]+)/") { return $Matches[1] }
  return ""
}

function Test-ModelAvailable {
  param([string[]]$Models, [string]$Name)
  return ($Models | Where-Object { $_.Trim() -eq $Name } | Select-Object -First 1) -ne $null
}

function Get-IntentPatterns {
  param([string]$Intent)
  switch ($Intent) {
    "small" { @("flash", "mini", "lite", "fast", "small") }
    "docs" { @("flash", "mini", "lite", "fast", "small") }
    "review" { @("flash", "mini", "lite", "fast", "small") }
    "coding" { @("code", "coder", "k2", "deepseek", "qwen", "glm") }
    "hard" { @("code", "coder", "k2", "deepseek", "qwen", "glm") }
    default { @("code", "coder", "k2", "deepseek", "qwen", "glm", "flash", "mini", "fast") }
  }
}

function Get-ModelScore {
  param([string]$ModelName, [string]$Intent)
  $score = 0
  $patterns = @(Get-IntentPatterns -Intent $Intent)
  for ($i = 0; $i -lt $patterns.Count; $i++) {
    if ($ModelName -like "*$($patterns[$i])*" ) {
      $score += (100 - $i)
    }
  }
  if ($Intent -eq "hard") {
    if ($ModelName -match "(?i)(flash|mini|lite)") { $score -= 50 }
    else { $score += 25 }
  }
  return $score
}

function Select-ByIntent {
  param([string[]]$Candidates, [string]$Intent)
  if (-not $Candidates -or $Candidates.Count -eq 0) { return $null }

  $ranked = @($Candidates | ForEach-Object {
    [pscustomobject]@{ Name = $_; Score = (Get-ModelScore -ModelName $_ -Intent $Intent) }
  } | Sort-Object -Property Score -Descending)

  if ($ranked.Count -gt 0 -and $ranked[0].Score -gt 0) { return $ranked[0].Name }
  return $Candidates[0]
}
function Resolve-Model {
  param(
    [string[]]$Models,
    [string]$ExplicitModel,
    [string]$PreferenceCsv,
    [bool]$FreeFallback,
    [bool]$PaidFallback,
    [string]$Intent
  )

  $cleanModels = @($Models | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^[^/\s]+/[^\s]+$" })
  if ($ExplicitModel) {
    if (Test-ModelAvailable -Models $cleanModels -Name $ExplicitModel) {
      return [pscustomobject]@{ Model = $ExplicitModel; Provider = (Get-ProviderName $ExplicitModel); Reason = "explicit model exists"; Fallback = $false }
    }
    Stop-WithMessage "Explicit model not found in opencode models: $ExplicitModel"
  }

  $preferences = @($PreferenceCsv.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $freeProviders = @("opencode-go", "opencode", "copilot", "github-copilot", "gemini", "google")
  $paidProviders = @("openai", "anthropic", "openrouter", "deepseek", "qwen", "zhipu", "moonshot")

  foreach ($provider in $preferences) {
    if ($provider -ne "opencode-go" -and ($freeProviders -notcontains $provider) -and (-not $PaidFallback)) { continue }
    if (($paidProviders -contains $provider) -and (-not $PaidFallback)) { continue }
    if (($provider -ne "opencode-go") -and ($freeProviders -contains $provider) -and (-not $FreeFallback)) { continue }

    $candidates = @($cleanModels | Where-Object { $_ -like "$provider/*" })
    $selected = Select-ByIntent -Candidates $candidates -Intent $Intent
    if ($selected) {
      $isFallback = $provider -ne "opencode-go"
      $reason = if ($provider -eq "opencode-go") { "preferred opencode-go provider matched intent '$Intent'" } else { "fallback provider '$provider' matched intent '$Intent'" }
      return [pscustomobject]@{ Model = $selected; Provider = $provider; Reason = $reason; Fallback = $isFallback }
    }
  }

  if ($PaidFallback) {
    foreach ($provider in $paidProviders) {
      $candidates = @($cleanModels | Where-Object { $_ -like "$provider/*" })
      $selected = Select-ByIntent -Candidates $candidates -Intent $Intent
      if ($selected) {
        return [pscustomobject]@{ Model = $selected; Provider = $provider; Reason = "paid fallback allowed and provider '$provider' matched intent '$Intent'"; Fallback = $true }
      }
    }
  }

  Stop-WithMessage "No acceptable model found. Run 'opencode models' or pass -Model with a visible provider/model. Paid providers require -AllowPaidFallback."
}

function Resolve-Agent {
  param([string]$AgentName, [string]$Intent)
  if ($AgentName -ne "auto") {
    return [pscustomobject]@{ Agent = $AgentName; Reason = "explicit agent"; Fallback = $false }
  }

  switch ($Intent) {
    "review" { return [pscustomobject]@{ Agent = "plan"; Reason = "auto review maps to plan"; Fallback = $false } }
    default { return [pscustomobject]@{ Agent = "build"; Reason = "auto edit/docs/coding maps to build"; Fallback = $false } }
  }
}

function Test-PluginRepository {
  param([string]$Path)
  $leaf = Split-Path -Leaf $Path
  if ($leaf -match "(?i)(opencode-go-worker|codex-opencode-worker)") { return $true }
  if ((Test-Path -LiteralPath (Join-Path $Path "SKILL.md")) -and (Test-Path -LiteralPath (Join-Path $Path "run_oc_worker.ps1"))) { return $true }
  $readme = Join-Path $Path "README.md"
  if (Test-Path -LiteralPath $readme) {
    $head = Get-Content -LiteralPath $readme -TotalCount 20 -ErrorAction SilentlyContinue
    if (($head -join "`n") -match "(?i)opencode-go-worker") { return $true }
  }
  return $false
}

function Get-OpencodeLauncher {
  $cmd = Get-Command opencode.cmd -ErrorAction SilentlyContinue
  if ($cmd) { return [pscustomobject]@{ File = "cmd.exe"; PrefixArgs = @("/d", "/c", $cmd.Source); Source = $cmd.Source } }

  $exe = Get-Command opencode.exe -ErrorAction SilentlyContinue
  if ($exe) { return [pscustomobject]@{ File = $exe.Source; PrefixArgs = @(); Source = $exe.Source } }

  $any = Get-Command opencode -ErrorAction SilentlyContinue
  if (-not $any) { Stop-WithMessage "opencode command not found." }

  if ([System.IO.Path]::GetExtension($any.Source) -ieq ".ps1") {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) { $pwsh = Get-Command powershell -ErrorAction SilentlyContinue }
    if (-not $pwsh) { Stop-WithMessage "opencode resolved to a PowerShell shim, but neither pwsh nor powershell was found." }
    return [pscustomobject]@{ File = $pwsh.Source; PrefixArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $any.Source); Source = $any.Source }
  }

  return [pscustomobject]@{ File = $any.Source; PrefixArgs = @(); Source = $any.Source }
}

function Format-CommandLine {
  param([string]$File, [string[]]$ArgList)
  $all = @($File) + $ArgList
  return ($all | ForEach-Object {
    if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
  }) -join " "
}

if ($Help) {
  Show-Help
  exit 0
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Stop-WithMessage "git command not found." }

$resolvedProject = Resolve-Path -LiteralPath $ProjectDir -ErrorAction SilentlyContinue
if (-not $resolvedProject) { Stop-WithMessage "ProjectDir not found: $ProjectDir" }
$projectPath = $resolvedProject.Path

$insideGit = (& git -C $projectPath rev-parse --is-inside-work-tree 2>$null)
if ($LASTEXITCODE -ne 0 -or $insideGit.Trim() -ne "true") { Stop-WithMessage "ProjectDir is not inside a git repository: $projectPath" }

if ($Mode -eq "USER_TASK" -and (Test-PluginRepository -Path $projectPath)) {
  $pluginRepoMessage = "Current directory looks like the opencode-go-worker plugin repository.`nUSER_TASK mode cannot run OpenCode inside the plugin repo.`nSwitch to the target project directory, or rerun in MAINTAIN_SKILL mode."
  if ($DryRun) {
    [Console]::Error.WriteLine("dry run warning: real execution would be refused. $pluginRepoMessage")
  } else {
    Stop-WithMessage $pluginRepoMessage
  }
}

$taskPath = if ([System.IO.Path]::IsPathRooted($TaskFile)) { $TaskFile } else { Join-Path $projectPath $TaskFile }
if (-not $DryRun -and -not (Test-Path -LiteralPath $taskPath -PathType Leaf)) { Stop-WithMessage "TaskFile not found: $taskPath" }

Write-Output "Refreshing OpenCode models..."
& opencode models --refresh
if ($LASTEXITCODE -ne 0) { Stop-WithMessage "opencode models --refresh failed." }

$availableModels = @(& opencode models)
if ($LASTEXITCODE -ne 0) { Stop-WithMessage "opencode models failed." }

$modelSelection = Resolve-Model -Models $availableModels -ExplicitModel $Model -PreferenceCsv $ProviderPreference -FreeFallback $AllowFreeFallback -PaidFallback ([bool]$AllowPaidFallback) -Intent $ModelIntent
$agentSelection = Resolve-Agent -AgentName $Agent -Intent $ModelIntent
$launcher = Get-OpencodeLauncher

$message = "Strictly execute the task file. Only modify allowed files. Do not do unrelated refactors. Do not commit or push. Run requested tests if possible. Report changed files, tests, blockers, and summary."
$runArgs = @($launcher.PrefixArgs) + @("run", "--agent", $agentSelection.Agent, "--model", $modelSelection.Model, "--file", $taskPath, "--dir", $projectPath, $message)

Write-Output "selected model: $($modelSelection.Model)"
Write-Output "selected provider: $($modelSelection.Provider)"
Write-Output "selection reason: $($modelSelection.Reason)"
Write-Output "fallback used: $($modelSelection.Fallback)"
Write-Output "selected agent: $($agentSelection.Agent)"
Write-Output "agent reason: $($agentSelection.Reason)"
Write-Output "opencode source: $($launcher.Source)"
Write-Output "command: $(Format-CommandLine -File $launcher.File -ArgList $runArgs)"

if ($DryRun) {
  Write-Output "dry run: opencode run was not executed."
  exit 0
}

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $launcher.File
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.WorkingDirectory = $projectPath
foreach ($arg in $runArgs) { [void]$psi.ArgumentList.Add($arg) }

$process = [System.Diagnostics.Process]::Start($psi)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$finished = $process.WaitForExit($TimeoutSec * 1000)

if (-not $finished) {
  [Console]::Error.WriteLine("Timeout after $TimeoutSec seconds. Terminating only this opencode process tree.")
  & taskkill /PID $process.Id /T /F 2>$null | Out-Null
  if (-not $process.HasExited) {
    try { $process.Kill($true) } catch { $process.Kill() }
  }
  $process.WaitForExit()
}

$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
if ($stdout) { Write-Output $stdout }
if ($stderr) { [Console]::Error.WriteLine($stderr) }

$exitCode = if ($finished) { $process.ExitCode } else { 124 }
Write-Output "opencode exit code: $exitCode"
Write-Output "git status --short:"
& git -C $projectPath status --short
Write-Output "git diff --stat:"
& git -C $projectPath diff --stat

exit $exitCode




