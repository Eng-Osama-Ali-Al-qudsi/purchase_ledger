# Execute from the Flutter project root. Saves each real exit code and raw log.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$logDir = Join-Path $root 'qa_logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$checks = @(
  @{name='flutter_doctor'; exe='flutter'; args=@('doctor','-v')},
  @{name='pub_get'; exe='flutter'; args=@('pub','get')},
  @{name='dart_format_check'; exe='dart'; args=@('format','--output=none','--set-exit-if-changed','lib','test')},
  @{name='flutter_analyze'; exe='flutter'; args=@('analyze')},
  @{name='flutter_test'; exe='flutter'; args=@('test')},
  @{name='debug_apk'; exe='flutter'; args=@('build','apk','--debug')}
)
$results = @()
foreach ($check in $checks) {
  Write-Host ("Running " + $check.name)
  $path = Join-Path $logDir ($check.name + '.txt')
  $command = Get-Command $check.exe -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    'Command not found: ' + $check.exe | Set-Content -Encoding UTF8 $path
    $code = 127
  } else {
    $arguments = $check.args
    & $check.exe @arguments *> $path
    $code = $LASTEXITCODE
  }
  $results += [PSCustomObject]@{Check=$check.name; ExitCode=$code; Log=$path}
}
$results | Format-Table -AutoSize
$results | Export-Csv -Path (Join-Path $logDir 'summary.csv') -NoTypeInformation -Encoding UTF8
Write-Host ('Saved results in ' + $logDir)
