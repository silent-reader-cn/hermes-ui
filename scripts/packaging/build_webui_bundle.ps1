# build_webui_bundle.ps1
# Build script for bundling embedded Python, runtime dependencies, and hermes-webui source.
# All characters in this file are strictly ASCII (required by project standards).

[CmdletBinding()]
param(
    [string]$OutDir = "build\webui-bundle",
    [string]$WebuiRepo = "https://github.com/nesquena/hermes-webui.git",
    [string]$WebuiRef = "",
    [string]$PythonVersion = "3.11.9"
)

$ErrorActionPreference = "Stop"

function Log-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Log-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Log-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Log-Err {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Resolve destination directory
$resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
Log-Info "Target bundle directory: $resolvedOutDir"

$pythonDir = Join-Path $resolvedOutDir "python"
$serverDir = Join-Path $resolvedOutDir "server"
$versionFile = Join-Path $resolvedOutDir "webui_version.txt"

# Ensure target directories exist
if (-not (Test-Path $resolvedOutDir)) {
    New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null
}
if (-not (Test-Path $pythonDir)) {
    New-Item -ItemType Directory -Force -Path $pythonDir | Out-Null
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("webui_build_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    # -------------------------------------------------------------------------
    # Step 1: Download & extract Python embeddable zip
    # -------------------------------------------------------------------------
    $pythonZip = Join-Path $tempDir "python-$PythonVersion-embed-amd64.zip"
    $pythonOrgUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"
    # Mirror fallback: npmmirror hosts the SAME official embeddable zip
    # (verified reachable from CN networks; python.org itself is often
    # blocked/slow here). NOTE: the old nuget.org "python" package fallback was
    # removed - its tools\ payload is a FULL install WITHOUT pythonXX._pth,
    # so Step 2 below could never succeed from that route.
    $npmmirrorFallbackUrl = "https://registry.npmmirror.com/-/binary/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"

    $downloadSuccess = $false

    # Check local cache first if available
    $localCaches = @(
        "C:\tmp\embed-test\python.zip",
        (Join-Path ([System.IO.Path]::GetTempPath()) "python-$PythonVersion-embed-amd64.zip")
    )
    foreach ($cachePath in $localCaches) {
        if (Test-Path $cachePath) {
            Log-Info "Found existing cached archive at $cachePath, copying..."
            Copy-Item -Path $cachePath -Destination $pythonZip -Force
            $downloadSuccess = $true
            break
        }
    }

    if (-not $downloadSuccess) {
        # Primary route: python.org official embeddable zip
        Log-Info "Downloading Python embeddable from python.org: $pythonOrgUrl"
        try {
            curl.exe -f -sSL "$pythonOrgUrl" -o "$pythonZip"
            if ($LASTEXITCODE -eq 0 -and (Test-Path $pythonZip) -and ((Get-Item $pythonZip).Length -gt 1000000)) {
                $downloadSuccess = $true
                Log-Success "Downloaded Python embed from python.org"
            } else {
                Log-Warn "curl download from python.org failed with exit code $LASTEXITCODE"
            }
        } catch {
            Log-Warn "Exception downloading from python.org: $_"
        }
    }

    if (-not $downloadSuccess) {
        # Fallback route: npmmirror official-embeddable mirror (same zip).
        Log-Info "Primary download failed. Attempting fallback from npmmirror: $npmmirrorFallbackUrl"
        try {
            curl.exe -f -sSL "$npmmirrorFallbackUrl" -o "$pythonZip"
            if ($LASTEXITCODE -eq 0 -and (Test-Path $pythonZip) -and ((Get-Item $pythonZip).Length -gt 1000000)) {
                $downloadSuccess = $true
                Log-Success "Downloaded Python embed from npmmirror"
            } else {
                Log-Warn "npmmirror download failed with exit code $LASTEXITCODE"
            }
        } catch {
            Log-Warn "Fallback npmmirror download failed: $_"
        }
    }

    if (-not $downloadSuccess) {
        Log-Err "Failed to download Python embeddable package from all sources."
        exit 1
    }

    # If downloaded zip file, extract into $pythonDir
    if ((Test-Path $pythonZip) -and (-not (Test-Path (Join-Path $pythonDir "python.exe")))) {
        Log-Info "Extracting Python zip to $pythonDir..."
        Expand-Archive -Path $pythonZip -DestinationPath $pythonDir -Force
    }

    $pythonExe = Join-Path $pythonDir "python.exe"
    if (-not (Test-Path $pythonExe)) {
        Log-Err "python.exe not found at $pythonExe after extraction"
        exit 1
    }

    # -------------------------------------------------------------------------
    # Step 2: Modify python311._pth to enable site-packages
    # -------------------------------------------------------------------------
    $pthFiles = Get-ChildItem -Path $pythonDir -Filter "python*._pth"
    if ($pthFiles.Count -eq 0) {
        Log-Err "No ._pth file found in $pythonDir"
        exit 1
    }
    $pthFile = $pthFiles[0].FullName
    Log-Info "Enabling site-packages in $pthFile..."

    $pthLines = Get-Content $pthFile
    $newPthLines = @()
    $sitePackagesAdded = $false

    foreach ($line in $pthLines) {
        $trimmed = $line.Trim()
        # Idempotency: keep exactly one Lib\site-packages entry, drop dupes
        if ($trimmed -eq "Lib\site-packages") {
            if (-not $sitePackagesAdded) {
                $newPthLines += "Lib\site-packages"
                $sitePackagesAdded = $true
            }
            continue
        }
        if ($trimmed -eq "..\server") {
            continue
        }
        if ($trimmed -eq "#import site") {
            if (-not $sitePackagesAdded) {
                $newPthLines += "Lib\site-packages"
                $sitePackagesAdded = $true
            }
            $newPthLines += "import site"
        } elseif ($trimmed -eq "import site") {
            if (-not $sitePackagesAdded) {
                $newPthLines += "Lib\site-packages"
                $sitePackagesAdded = $true
            }
            $newPthLines += "import site"
        } else {
            $newPthLines += $line
        }
    }

    if (-not $sitePackagesAdded) {
        $newPthLines += "Lib\site-packages"
        $newPthLines += "import site"
    }

    # Embeddable python with a ._pth file runs in isolated mode (sys.path is
    # fixed, PYTHONPATH is ignored). The server dir must be on sys.path so
    # `import api` works; S1 starts the process with cwd=server dir but that
    # does not add it to sys.path under isolated mode. Path is relative to the
    # python dir, i.e. ..\server.
    $newPthLines += "..\server"

    $newPthLines | Set-Content $pthFile -Encoding ASCII
    Log-Success "Updated $pthFile successfully"

    # -------------------------------------------------------------------------
    # Step 3: Install dependencies with get-pip.py and remove pip afterwards
    # -------------------------------------------------------------------------
    $sitePackagesDir = Join-Path $pythonDir "Lib\site-packages"
    if (-not (Test-Path $sitePackagesDir)) {
        New-Item -ItemType Directory -Force -Path $sitePackagesDir | Out-Null
    }

    # Download get-pip.py
    $getPipPy = Join-Path $tempDir "get-pip.py"
    $getPipDownloaded = $false

    # Check local cache first
    $localPipCaches = @(
        "C:\tmp\embed-test\get-pip.py",
        (Join-Path ([System.IO.Path]::GetTempPath()) "get-pip.py")
    )
    foreach ($cacheP in $localPipCaches) {
        if (Test-Path $cacheP) {
            Log-Info "Using cached get-pip.py from $cacheP"
            Copy-Item -Path $cacheP -Destination $getPipPy -Force
            $getPipDownloaded = $true
            break
        }
    }

    if (-not $getPipDownloaded) {
        Log-Info "Downloading get-pip.py..."
        $pipUrls = @(
            "https://bootstrap.pypa.io/get-pip.py",
            "https://raw.githubusercontent.com/pypa/get-pip/main/public/get-pip.py"
        )
        foreach ($pUrl in $pipUrls) {
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                try {
                    curl.exe -f -sSL "$pUrl" -o "$getPipPy"
                    if ($LASTEXITCODE -eq 0 -and (Test-Path $getPipPy) -and ((Get-Item $getPipPy).Length -gt 100000)) {
                        $getPipDownloaded = $true
                        break
                    }
                } catch {}
                Start-Sleep -Seconds 1
            }
            if ($getPipDownloaded) { break }
        }
    }

    if (-not $getPipDownloaded -or -not (Test-Path $getPipPy)) {
        Log-Err "Failed to download get-pip.py from all sources"
        exit 1
    }

    Log-Info "Bootstrapping pip in embedded Python..."
    # Default route (pypi.org) works on GitHub runners; on CN networks pypi.org
    # is unreachable -> retry once against the Tsinghua TUNA mirror.
    $indexArgs = @()
    & $pythonExe $getPipPy --no-warn-script-location @indexArgs
    if ($LASTEXITCODE -ne 0) {
        Log-Warn "pip bootstrap via pypi.org failed; retrying with TUNA mirror"
        $indexArgs = @("-i", "https://pypi.tuna.tsinghua.edu.cn/simple")
        & $pythonExe $getPipPy --no-warn-script-location @indexArgs
        if ($LASTEXITCODE -ne 0) {
            Log-Err "Failed to bootstrap pip (both pypi.org and TUNA mirror)"
            exit 1
        }
    }

    Log-Info "Installing pyyaml and cryptography into site-packages..."
    & $pythonExe -m pip install --target "$sitePackagesDir" @indexArgs "pyyaml>=6.0" "cryptography>=42.0"
    if ($LASTEXITCODE -ne 0 -and $indexArgs.Count -eq 0) {
        Log-Warn "pip install via pypi.org failed; retrying with TUNA mirror"
        $indexArgs = @("-i", "https://pypi.tuna.tsinghua.edu.cn/simple")
        & $pythonExe -m pip install --target "$sitePackagesDir" @indexArgs "pyyaml>=6.0" "cryptography>=42.0"
        if ($LASTEXITCODE -ne 0) {
            Log-Err "Failed to install dependencies via pip (both routes)"
            exit 1
        }
    } elseif ($LASTEXITCODE -ne 0) {
        Log-Err "Failed to install dependencies via pip"
        exit 1
    }

    Log-Info "Verifying dependencies before pip cleanup..."
    & $pythonExe -c "import yaml; import cryptography; print('DEPS_VERIFIED: yaml=' + yaml.__version__ + ', cryptography=' + cryptography.__version__)"
    if ($LASTEXITCODE -ne 0) {
        Log-Err "Dependency import verification failed"
        exit 1
    }

    # Clean up pip, setuptools, wheel and bytecode to ensure zero-pip runtime
    Log-Info "Removing pip, build tools, and bytecode for zero-pip runtime..."
    $toolsToRemove = @(
        "pip",
        "setuptools",
        "pkg_resources",
        "wheel",
        "packaging",
        "_distutils_hack",
        "distutils-precedence.pth"
    )
    foreach ($toolName in $toolsToRemove) {
        $targetToolPath = Join-Path $sitePackagesDir $toolName
        if (Test-Path $targetToolPath) {
            Remove-Item -Recurse -Force $targetToolPath
        }
    }

    Get-ChildItem -Path $sitePackagesDir -Filter "*.dist-info" | Where-Object {
        $_.Name -match "^(pip|setuptools|wheel|packaging)-"
    } | Remove-Item -Recurse -Force

    $scriptsDir = Join-Path $pythonDir "Scripts"
    if (Test-Path $scriptsDir) {
        Remove-Item -Recurse -Force $scriptsDir
    }

    Get-ChildItem -Path $pythonDir -Recurse -Filter "__pycache__" | Remove-Item -Recurse -Force
    Get-ChildItem -Path $pythonDir -Recurse -Filter "*.pyc" | Remove-Item -Force

    # Verify zero-pip condition: pip module must not exist
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        $null = & cmd.exe /c "`"$pythonExe`" -m pip --version >nul 2>&1"
        $pipExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    if ($pipExitCode -eq 0) {
        Log-Err "Pip is still present in python directory after cleanup!"
        exit 1
    }
    Log-Success "Zero-pip runtime verified (pip is absent)"

    # Verify dependencies still import cleanly after cleanup
    $verifyCheck = & cmd.exe /c "`"$pythonExe`" -c `"import yaml; import cryptography; print('RUNTIME_DEPS_OK')`""
    if ($LASTEXITCODE -ne 0 -or $verifyCheck -notmatch "RUNTIME_DEPS_OK") {
        Log-Err "Dependencies failed to import after pip removal"
        exit 1
    }
    Log-Success "Runtime dependencies verified without pip"

    # -------------------------------------------------------------------------
    # Step 4: Clone webui repository, write version, and strip git/tests/docs
    # -------------------------------------------------------------------------
    if (Test-Path $serverDir) {
        Log-Info "Cleaning up existing server directory..."
        Get-ChildItem -Path $serverDir -Recurse -Force | ForEach-Object { $_.Attributes = "Normal" }
        Remove-Item -Recurse -Force $serverDir
    }

    Log-Info "Cloning hermes-webui from $WebuiRepo into $serverDir..."
    $cloneSuccess = $false

    # Attempt git clone with specified ref or depth 1
    if ($WebuiRef -ne "") {
        Log-Info "Cloning specific ref: $WebuiRef"
        & git clone --depth=1 --branch $WebuiRef $WebuiRepo "$serverDir"
        if ($LASTEXITCODE -eq 0) {
            $cloneSuccess = $true
        } else {
            Log-Warn "Branch clone failed, trying generic clone and checkout..."
            & git clone $WebuiRepo "$serverDir"
            if ($LASTEXITCODE -eq 0) {
                & git -C "$serverDir" checkout $WebuiRef
                if ($LASTEXITCODE -eq 0) {
                    $cloneSuccess = $true
                }
            }
        }
    } else {
        & git clone --depth=1 $WebuiRepo "$serverDir"
        if ($LASTEXITCODE -eq 0) {
            $cloneSuccess = $true
        }
    }

    # Fallback to local repo if remote clone fails and D:\hermes-webui exists
    if (-not $cloneSuccess) {
        $localFallback = "D:\hermes-webui"
        if (Test-Path (Join-Path $localFallback "server.py")) {
            Log-Warn "Remote clone failed. Falling back to local repository at $localFallback"
            & git clone --depth=1 $localFallback "$serverDir"
            if ($LASTEXITCODE -eq 0) {
                $cloneSuccess = $true
            }
        }
    }

    if (-not $cloneSuccess) {
        Log-Err "Failed to clone hermes-webui repository"
        exit 1
    }

    # Get upstream commit sha BEFORE deleting .git
    $commitSha = (git -C "$serverDir" rev-parse HEAD).Trim()
    if (-not $commitSha) {
        Log-Err "Could not determine git commit SHA from $serverDir"
        exit 1
    }
    Log-Info "WebUI upstream commit SHA: $commitSha"

    # Write single line commit sha to webui_version.txt
    $commitSha | Set-Content $versionFile -Encoding ASCII -NoNewline
    Log-Success "Wrote version file to $versionFile"

    # Strip .git, tests, docs, and bytecode from server directory
    Log-Info "Removing .git directory from server payload..."
    $gitDir = Join-Path $serverDir ".git"
    if (Test-Path $gitDir) {
        Get-ChildItem -Path $gitDir -Recurse -Force | ForEach-Object { $_.Attributes = "Normal" }
        Remove-Item -Path $gitDir -Recurse -Force
    }

    $testsDir = Join-Path $serverDir "tests"
    if (Test-Path $testsDir) {
        Log-Info "Removing tests directory..."
        Remove-Item -Path $testsDir -Recurse -Force
    }

    $docsDir = Join-Path $serverDir "docs"
    if (Test-Path $docsDir) {
        Log-Info "Removing docs directory..."
        Remove-Item -Path $docsDir -Recurse -Force
    }

    Get-ChildItem -Path $serverDir -Recurse -Filter "__pycache__" | Remove-Item -Recurse -Force
    Get-ChildItem -Path $serverDir -Recurse -Filter "*.pyc" | Remove-Item -Force

    # -------------------------------------------------------------------------
    # Step 5: Validate bundle artifacts
    # -------------------------------------------------------------------------
    $pyCheck = Test-Path (Join-Path $pythonDir "python.exe")
    $serverCheck = Test-Path (Join-Path $serverDir "server.py")
    $verCheck = Test-Path $versionFile

    if (-not $pyCheck) {
        Log-Err "Artifact check failed: python/python.exe is missing"
        exit 1
    }
    if (-not $serverCheck) {
        Log-Err "Artifact check failed: server/server.py is missing"
        exit 1
    }
    if (-not $verCheck) {
        Log-Err "Artifact check failed: webui_version.txt is missing"
        exit 1
    }

    # Measure total bundle size
    $totalSizeBytes = (Get-ChildItem -Path $resolvedOutDir -Recurse | Measure-Object -Property Length -Sum).Sum
    $totalSizeMb = [math]::Round($totalSizeBytes / 1MB, 2)

    Log-Success "================================================="
    Log-Success "WebUI sidecar bundle assembled successfully!"
    Log-Success "Artifact verification:"
    Log-Success "  [OK] webui\python\python.exe"
    Log-Success "  [OK] webui\server\server.py"
    Log-Success "  [OK] webui_version.txt (SHA: $commitSha)"
    Log-Success "Total bundle size: $totalSizeMb MB ($totalSizeBytes bytes)"
    Log-Success "================================================="

    exit 0
} finally {
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    }
}
