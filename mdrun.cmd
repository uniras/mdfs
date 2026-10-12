<# : batch part (cmd reads this; PowerShell sees it as a block comment)
@echo off
setlocal
set "MDRUN_SELF=%~f0"
set "MDRUN_ARGS=%*"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content -LiteralPath $env:MDRUN_SELF -Raw -Encoding UTF8)"
exit /b %errorlevel%
#>
# mdrun.cmd - run a Markdown app with docker compose (Windows)
#
# This is a batch file only so that it can be double-clicked / drag-and-dropped.
# The batch part above re-runs this file with the built-in Windows PowerShell;
# everything below is PowerShell.
#
#   The front matter of the .md is the compose file. This script only cuts it out,
#   renames a top-level "entangled:" key to "x-entangled:" (compose rejects unknown
#   top-level keys; Entangled in the container still reads the original .md),
#   and passes it to docker compose on stdin. Nothing is written to the host.
#
# usage:
#   mdrun.cmd app.md                  build, start, wait until healthy, open the x-open URL
#                                     (dragging app.md onto this file does the same)
#   mdrun.cmd app.md open             open the x-open URL in the browser
#   mdrun.cmd app.md down             stop and remove
#   mdrun.cmd app.md COMMAND [args]   any other docker compose command (logs -f, ps, ...)
#
# options (anywhere on the command line):
#   --no-open    do not open the browser after "up" (or set MDRUN_NO_OPEN=1)
#
# The .md file name is set as MDFS_SRC, so the front matter can use
#   build: { args: { MDFS_SRC: ${MDFS_SRC} } }
# for .md files not named app.md.
#
# Note: a path containing "&" cannot be passed through the batch part.

$ErrorActionPreference = 'Stop'

function Fail([string]$msg, [int]$code = 1) {
  [Console]::Error.WriteLine("mdrun: $msg")
  exit $code
}

# Split the raw argument string from the batch part ("quoted args" keep their spaces).
$argv = @([regex]::Matches([string]$env:MDRUN_ARGS, '"([^"]*)"|(\S+)') | ForEach-Object {
  if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
})
# Take --no-open out of the arguments (the rest is passed to docker compose).
$noOpen = [bool]$env:MDRUN_NO_OPEN -or ($argv -contains '--no-open')
$argv = @($argv | Where-Object { $_ -ne '--no-open' })
if ($argv.Count -lt 1) {
  Fail 'usage: mdrun.cmd app.md [up|open|down|COMMAND] [args...] [--no-open]' 2
}
$file = $argv[0]
$cmd  = if ($argv.Count -ge 2) { $argv[1] } else { 'up' }
$rest = if ($argv.Count -ge 3) { @($argv[2..($argv.Count - 1)]) } else { @() }

if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Fail "file not found: $file" }
$path = (Resolve-Path -LiteralPath $file).Path
# a trailing "." avoids a quoted path ending in \" (e.g. C:\) being misread by docker
$dir = Join-Path (Split-Path -Parent $path) '.'
$env:MDFS_SRC = Split-Path -Leaf $path

# Front matter = lines between the first-line '---' and the next '---'.
$lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
$end = if ($lines.Count -ge 3 -and $lines[0] -eq '---') { [Array]::IndexOf($lines, '---', 1) } else { -1 }
if ($end -lt 2) { Fail "no front matter in $($env:MDFS_SRC)" }
$fm = @($lines[1..($end - 1)] -replace '^entangled:', 'x-entangled:')

function Invoke-Compose([string[]]$composeArgs) {
  $OutputEncoding = [Text.UTF8Encoding]::new($false)   # send UTF-8 (no BOM) to docker
  # Out-Host: show docker's output instead of returning it from this function
  $fm | docker compose -f - --project-directory $dir @composeArgs | Out-Host
  return $LASTEXITCODE
}

function Get-AppUrl {
  $fm | ForEach-Object {
    if ($_ -match '^x-open:\s*(\S+)') { $Matches[1].Trim([char]34, [char]39) }
  } | Select-Object -First 1
}

switch ($cmd) {
  'up' {
    $rc = Invoke-Compose (@('up', '--build', '--wait') + $rest)
    if ($rc -ne 0) { exit $rc }
    $url = Get-AppUrl
    # no x-open in the front matter: nothing to open, which is fine for "up"
    if ($url -and -not $noOpen) { Start-Process $url }
  }
  'open' {
    $url = Get-AppUrl
    if (-not $url) { Fail "no x-open URL in the front matter of $($env:MDFS_SRC)" }
    Start-Process $url
  }
  default {
    exit (Invoke-Compose (@($cmd) + $rest))
  }
}
exit 0
