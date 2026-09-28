# Installateur d'Arcanes & Lames (Windows 10/11, sans droits administrateur).
# Utilisation (touche Windows + R, ou PowerShell) :
#   powershell -c "irm __BASE__/install.ps1 | iex"
# Télécharge le jeu en HTTPS, vérifie son empreinte SHA-256 et la signature de l'exécutable,
# l'installe dans %LOCALAPPDATA%\Programs\ArcanesEtLames et crée les raccourcis.
# Les mises à jour suivantes se font automatiquement depuis le jeu.

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'   # accélère fortement Invoke-WebRequest sous PowerShell 5
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $base = '__BASE__'
    $thumbprint = '__THUMBPRINT__'             # certificat de signature « Arcanes & Lames »
    $dest = if ($env:ARCANES_INSTALL_DIR) { $env:ARCANES_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\ArcanesEtLames' }

    Write-Host ''
    Write-Host '  ARCANES & LAMES - installation' -ForegroundColor Yellow
    Write-Host ''
    try {
        $latest = Invoke-RestMethod -UseBasicParsing "$base/version.json"
        Write-Host "  Version $($latest.version) - téléchargement ($([math]::Round($latest.download_size / 1MB)) Mo)..."
        $zip = Join-Path $env:TEMP "ArcanesEtLames_$($latest.version).zip"
        Invoke-WebRequest -UseBasicParsing "$base/download/$($latest.download)" -OutFile $zip

        $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
        if ($hash -ne $latest.download_sha256) { throw "Fichier corrompu (empreinte SHA-256 inattendue)." }

        $tmp = Join-Path $env:TEMP "ArcanesEtLames_install"
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $src = Join-Path $tmp 'ArcanesEtLames'

        $sig = Get-AuthenticodeSignature (Join-Path $src 'ArcanesEtLames.exe')
        if ($sig.Status -eq 'NotSigned' -or $sig.Status -eq 'HashMismatch' -or $null -eq $sig.SignerCertificate `
                -or $sig.SignerCertificate.Thumbprint -ne $thumbprint) {
            throw "Signature de l'exécutable invalide : installation annulée."
        }

        Get-Process ArcanesEtLames -ErrorAction SilentlyContinue | Stop-Process -Force
        New-Item -ItemType Directory -Force $dest | Out-Null
        Copy-Item (Join-Path $src '*') $dest -Recurse -Force
        Get-ChildItem $dest -Recurse | Unblock-File
        Remove-Item $zip, $tmp -Recurse -Force

        $exe = Join-Path $dest 'ArcanesEtLames.exe'
        if ($env:ARCANES_NO_SHORTCUTS) {   # mode test : ni raccourcis ni lancement
            Write-Host "  Installé dans $dest (mode test)" -ForegroundColor Green
            return
        }
        $shell = New-Object -ComObject WScript.Shell
        $links = @(
            (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Arcanes & Lames.lnk'),
            (Join-Path ([Environment]::GetFolderPath('Programs')) 'Arcanes & Lames.lnk')
        )
        foreach ($l in $links) {
            $s = $shell.CreateShortcut($l)
            $s.TargetPath = $exe
            $s.WorkingDirectory = $dest
            $s.Description = 'Arcanes & Lames'
            $s.Save()
        }
        # Désinstallation : supprime le dossier et les raccourcis (les réglages restent dans %APPDATA%).
        $uninstall = @(
            '@echo off',
            'taskkill /im ArcanesEtLames.exe /f >nul 2>&1',
            ('del "{0}" "{1}" >nul 2>&1' -f $links[0], $links[1]),
            'cd /d "%TEMP%"',
            ('rmdir /s /q "{0}"' -f $dest)
        ) -join "`r`n"
        Set-Content -Path (Join-Path $dest 'Desinstaller.cmd') -Value $uninstall -Encoding Default

        Write-Host ''
        Write-Host "  Installé dans $dest" -ForegroundColor Green
        Write-Host '  Raccourcis créés sur le Bureau et dans le menu Démarrer. Lancement du jeu...' -ForegroundColor Green
        Start-Process $exe -WorkingDirectory $dest
    } catch {
        Write-Host ''
        Write-Host "  ERREUR : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Vous pouvez aussi télécharger le jeu depuis $base" -ForegroundColor Red
    }
}
