# ============================================================
#  Diagnostic PC - bilan rapide facon helpdesk
#  Lancement (PowerShell en administrateur pour le contrôle du chiffrement) :
#  powershell -ExecutionPolicy Bypass -File .\diagnostic.ps1
# ============================================================

$rapport = New-Object System.Collections.Generic.List[string]

function Ecrire($texte, $couleur = "White") {
    Write-Host $texte -ForegroundColor $couleur
    $rapport.Add($texte)
}

function Titre($texte) {
    Ecrire ""
    Ecrire "=== $texte ===" "Cyan"
}

$alertes = 0
function Alerte($texte) {
    $script:alertes++
    Ecrire "  [!] $texte" "Yellow"
}

Ecrire "Diagnostic PC - $(Get-Date -Format 'dd/MM/yyyy HH:mm')" "Green"

# ---------- Système ----------
Titre "Système"
$os  = Get-CimInstance Win32_OperatingSystem
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$ramGo = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$ramLibreGo = [math]::Round($os.FreePhysicalMemory * 1KB / 1GB, 1)

Ecrire "  Nom du PC   : $($cs.Name)"
Ecrire "  Windows     : $($os.Caption) (build $($os.BuildNumber))"
Ecrire "  Processeur  : $($cpu.Name.Trim())"
Ecrire "  Mémoire     : $ramGo Go au total, $ramLibreGo Go libres"
if (($ramLibreGo / $ramGo) -lt 0.10) { Alerte "Mémoire presque saturée (moins de 10 % libre)" }

# ---------- Disques ----------
Titre "Disques"
$disques = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
foreach ($d in $disques) {
    if (-not $d.Size) { continue }
    $totalGo = [math]::Round($d.Size / 1GB, 0)
    $libreGo = [math]::Round($d.FreeSpace / 1GB, 0)
    $pct     = [math]::Round(($d.FreeSpace / $d.Size) * 100, 0)
    Ecrire ("  {0}  {1,5} Go libres sur {2,5} Go  ({3} % libre)" -f $d.DeviceID, $libreGo, $totalGo, $pct)
    if ($pct -lt 15) { Alerte "Le disque $($d.DeviceID) a moins de 15 % d'espace libre" }
}

# ---------- Réseau ----------
Titre "Réseau"
$connexions = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq "Up" -and $_.IPv4Address }
if (-not $connexions) {
    Alerte "Aucune connexion réseau active"
} else {
    foreach ($c in $connexions) {
        Ecrire "  Interface   : $($c.InterfaceAlias) ($($c.InterfaceDescription))"
        Ecrire "  Adresse IP  : $($c.IPv4Address.IPAddress)"
        Ecrire "  Passerelle  : $($c.IPv4DefaultGateway.NextHop)"
    }

    $passerelle = ($connexions | Select-Object -First 1).IPv4DefaultGateway.NextHop
    if ($passerelle) {
        if (Test-Connection -ComputerName $passerelle -Count 2 -Quiet) {
            Ecrire "  Box joignable        : oui" "Green"
        } else {
            Alerte "La box ($passerelle) ne répond pas"
        }
    }

    if (Test-Connection -ComputerName 1.1.1.1 -Count 2 -Quiet) {
        Ecrire "  Internet joignable   : oui" "Green"
    } else {
        Alerte "Internet ne répond pas (test vers 1.1.1.1)"
    }

    try {
        Resolve-DnsName -Name "www.google.com" -ErrorAction Stop | Out-Null
        Ecrire "  Résolution DNS       : oui" "Green"
    } catch {
        Alerte "La résolution DNS ne fonctionne pas"
    }
}

# ---------- Démarrage ----------
Titre "Démarrage"
$uptime = (Get-Date) - $os.LastBootUpTime
Ecrire ("  Dernier redémarrage : {0} (il y a {1} j {2} h)" -f $os.LastBootUpTime.ToString("dd/MM/yyyy HH:mm"), $uptime.Days, $uptime.Hours)
if ($uptime.Days -ge 7) { Alerte "PC non redémarré depuis plus de 7 jours : pensez à « Redémarrer » (pas « Arrêter »)" }

# ---------- Erreurs récentes ----------
Titre "Erreurs système (dernières 24 h)"
$erreurs = Get-WinEvent -FilterHashtable @{ LogName = "System"; Level = 1, 2; StartTime = (Get-Date).AddDays(-1) } -ErrorAction SilentlyContinue
$nb = ($erreurs | Measure-Object).Count
Ecrire "  $nb erreur(s) critique(s) ou erreur(s) dans le journal Système"
if ($nb -gt 0) {
    $erreurs | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object {
        Ecrire ("    - {0} : {1} fois" -f $_.Name, $_.Count)
    }
}
if ($nb -ge 20) { Alerte "Beaucoup d'erreurs système, à examiner dans l'Observateur d'événements" }

# ============================================================
#  SÉCURITÉ
# ============================================================
$estAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------- Antivirus ----------
Titre "Sécurité : antivirus (Windows Defender)"
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    if ($mp.AMRunningMode -ne "Normal") {
        Ecrire "  Defender en mode $($mp.AMRunningMode) : un autre antivirus est probablement installé."
    } else {
        Ecrire ("  Antivirus actif         : {0}" -f $(if ($mp.AntivirusEnabled) { "oui" } else { "non" }))
        Ecrire ("  Protection temps réel   : {0}" -f $(if ($mp.RealTimeProtectionEnabled) { "oui" } else { "non" }))
        if (-not $mp.AntivirusEnabled)          { Alerte "L'antivirus Defender est désactivé" }
        if (-not $mp.RealTimeProtectionEnabled) { Alerte "La protection en temps réel est désactivée" }

        $ageSign = ((Get-Date) - $mp.AntivirusSignatureLastUpdated).Days
        Ecrire ("  Définitions de virus    : {0} (il y a {1} j)" -f $mp.AntivirusSignatureLastUpdated.ToString("dd/MM/yyyy HH:mm"), $ageSign)
        if ($ageSign -gt 3) { Alerte "Définitions de virus vieilles de plus de 3 jours" }

        if ($mp.QuickScanEndTime) {
            $ageScan = ((Get-Date) - $mp.QuickScanEndTime).Days
            Ecrire ("  Dernière analyse rapide : {0} (il y a {1} j)" -f $mp.QuickScanEndTime.ToString("dd/MM/yyyy"), $ageScan)
            if ($ageScan -gt 14) { Alerte "Aucune analyse rapide depuis plus de 14 jours" }
        } else {
            Alerte "Aucune analyse rapide enregistrée"
        }
        if ($mp.FullScanEndTime) {
            Ecrire ("  Dernière analyse complète : {0}" -f $mp.FullScanEndTime.ToString("dd/MM/yyyy"))
        } else {
            Ecrire "  Dernière analyse complète : jamais (conseillé de temps en temps)"
        }
    }
} catch {
    Alerte "Impossible de lire l'état de Windows Defender"
}

# ---------- Pare-feu ----------
Titre "Sécurité : pare-feu"
foreach ($p in Get-NetFirewallProfile) {
    $etat = if ($p.Enabled) { "activé" } else { "DÉSACTIVÉ" }
    Ecrire ("  {0,-8} : {1}, connexions entrantes par défaut : {2}" -f $p.Name, $etat, $p.DefaultInboundAction)
    if (-not $p.Enabled) { Alerte "Pare-feu désactivé sur le profil $($p.Name)" }
    if ("$($p.DefaultInboundAction)" -eq "Allow") { Alerte "Le profil $($p.Name) autorise les connexions entrantes par défaut" }
}

# ---------- Mises à jour ----------
Titre "Sécurité : mises à jour Windows"
$maj = Get-HotFix | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
if ($maj) {
    $ageMaj = ((Get-Date) - $maj.InstalledOn).Days
    Ecrire ("  Dernière mise à jour : {0} ({1}), il y a {2} j" -f $maj.HotFixID, $maj.InstalledOn.ToString("dd/MM/yyyy"), $ageMaj)
    if ($ageMaj -gt 45) { Alerte "Aucune mise à jour Windows depuis plus de 45 jours" }
} else {
    Alerte "Impossible de trouver la date de la dernière mise à jour"
}

# ---------- Comptes ----------
Titre "Sécurité : comptes"
try {
    $admins = Get-LocalGroupMember -SID "S-1-5-32-544" -ErrorAction Stop
    Ecrire "  Membres du groupe Administrateurs :"
    foreach ($a in $admins) { Ecrire "    - $($a.Name)" }
} catch {
    Ecrire "  Liste des administrateurs illisible ici, utiliser : net localgroup Administrateurs"
}
$actifs = Get-LocalUser | Where-Object { $_.Enabled }
Ecrire ("  Comptes locaux actifs : {0}" -f (($actifs | ForEach-Object { $_.Name }) -join ", "))
$adminIntegre = Get-LocalUser | Where-Object { $_.SID.Value -like "*-500" }
$invite       = Get-LocalUser | Where-Object { $_.SID.Value -like "*-501" }
if ($adminIntegre.Enabled) { Alerte "Le compte Administrateur intégré est activé (il devrait être désactivé)" }
if ($invite.Enabled)       { Alerte "Le compte Invité est activé" }

# ---------- Chiffrement ----------
Titre "Sécurité : chiffrement du disque système"
if (-not $estAdmin) {
    Ecrire "  Non vérifiable : relancer PowerShell en administrateur pour ce contrôle."
} else {
    try {
        $vol = Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftVolumeEncryption" -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$env:SystemDrive'" -ErrorAction Stop
        switch ($vol.ProtectionStatus) {
            1       { Ecrire "  $env:SystemDrive chiffré, protection active" "Green" }
            0       { Alerte "$env:SystemDrive n'est pas chiffré (risque surtout en cas de vol, plus important sur un portable)" }
            default { Ecrire "  État du chiffrement inconnu" }
        }
    } catch {
        Ecrire "  Chiffrement non disponible sur ce PC (fréquent sur Windows Famille)"
    }
}

# ---------- Bilan ----------
Titre "Bilan"
if ($alertes -eq 0) {
    Ecrire "  Aucun problème détecté." "Green"
} else {
    Ecrire "  $alertes point(s) d'attention, voir les lignes [!] ci-dessus." "Yellow"
}

# Les rapports vont dans un sous-dossier "rapports" à côté du script
$dossierRapports = Join-Path $PSScriptRoot "rapports"
if (-not (Test-Path $dossierRapports)) { New-Item -ItemType Directory -Path $dossierRapports | Out-Null }
$fichier = Join-Path $dossierRapports ("diagnostic_{0}.txt" -f (Get-Date -Format "yyyy-MM-dd_HHmm"))
$rapport | Out-File -FilePath $fichier -Encoding UTF8
Write-Host ""
Write-Host "Rapport enregistré : $fichier" -ForegroundColor Green
