# Active les composants Windows dont Solon a besoin, et rien d'autre.
#
# L'installeur NSIS fait ce travail lui-même (setup.ps1). Ce script existe pour le paquet MSIX du
# Microsoft Store : un paquet MSIX s'installe sans élévation et ne peut donc pas toucher aux
# composants Windows. L'application le lance élevée, à la demande de l'utilisateur, depuis l'écran
# de vérification du système.
#
# Codes de retour : 0 déjà bon ou activé, 3010 redémarrage requis, 1 échec.
# Journal : %ProgramData%\Solon\logs\setup-features.log
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$logDir = Join-Path $env:ProgramData "Solon\logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "setup-features.log"
function Log($m) {
    $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m
    Add-Content -Path $log -Value $line
    Write-Output $line
}

Log "activation des composants demandée"
$needsReboot = $false
$enabledSomething = $false

# Microsoft-Hyper-V n'existe pas sur Windows Famille : la Plateforme de machine virtuelle suffit,
# depuis que le partage de fichiers passe par solonfs (0.1.12).
foreach ($feature in @("Microsoft-Hyper-V", "VirtualMachinePlatform")) {
    try {
        $info = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction Stop
    } catch {
        Log "composant ${feature} : absent de cette édition (Famille : la Plateforme de machine virtuelle suffit)"
        continue
    }
    if ($info.State -eq "Enabled") { Log "composant ${feature} : déjà activé"; continue }
    Log "composant ${feature} : activation"
    try {
        $r = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction Stop
        $enabledSomething = $true
        if ($r.RestartNeeded) { $needsReboot = $true }
        Log "composant ${feature} : activé (redémarrage requis : $($r.RestartNeeded))"
    } catch {
        Log "composant ${feature} : ÉCHEC $($_.Exception.Message)"
        exit 1
    }
}

# Le service vmcompute démarre à la demande, mais un premier démarrage explicite évite une attente
# au premier lancement du moteur juste après l'activation.
if ($enabledSomething -and -not $needsReboot) {
    try { Start-Service vmcompute -ErrorAction Stop; Log "service vmcompute démarré" } catch { Log "service vmcompute : $($_.Exception.Message)" }
}

if ($needsReboot) { Log "redémarrage requis"; exit 3010 }
Log "terminé"
exit 0
