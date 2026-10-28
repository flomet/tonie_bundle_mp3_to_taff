<#
.SYNOPSIS
Erstellt aus nummerierten MP3-Dateien TAF-Bundles mit ungefaehr einer Stunde Laufzeit.

.DESCRIPTION
MP3-Dateien werden nach ihrer fuehrenden Nummer sortiert und zu Bundles gruppiert.
Fuer jedes Bundle entstehen eine TAF-Datei und eine Kapiteluebersicht im Ausgabeordner.

.REQUIREMENTS
ffprobe und tonietoolbox muessen im PATH verfuegbar sein.
#>
$ErrorActionPreference = 'Stop'

# Eingaben liegen neben dem Skript; erzeugte Dateien werden getrennt gesammelt.
$quelle = $PSScriptRoot
$ausgabe = Join-Path $quelle 'TAF_Bundles_1h'
$zielSekunden = 3600
$maxKapitel = 99

# Fehlende Werkzeuge frueh melden, bevor Dateien verarbeitet werden.
foreach ($programm in @('ffprobe', 'tonietoolbox')) {
    if (-not (Get-Command $programm -ErrorAction SilentlyContinue)) {
        throw "$programm fehlt oder ist nicht im PATH."
    }
}

function Format-Dauer([double]$sekunden) {
    $t = [TimeSpan]::FromSeconds($sekunden)
    return '{0:00}:{1:00}:{2:00}' -f [int][Math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds
}

function Get-Dauer([string]$pfad) {
    $wert = & ffprobe -v error -show_entries format=duration -of 'default=noprint_wrappers=1:nokey=1' $pfad
    if ($LASTEXITCODE -ne 0) { throw "Dauer konnte nicht gelesen werden: $pfad" }
    $dauer = 0.0
    $ok = [double]::TryParse(($wert -join '').Trim(),
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture, [ref]$dauer)
    if (-not $ok -or $dauer -le 0) { throw "Ungueltige Audiodauer: $pfad" }
    return $dauer
}

# Nur nummerierte MP3s direkt neben dem Skript; numerische Sortierung.
$dateien = @(
    Get-ChildItem -LiteralPath $quelle -File -Filter '*.mp3' |
    Where-Object { $_.Name -match '^\d+.*\.mp3$' } |
    Sort-Object @{ Expression = { [long]([regex]::Match($_.Name, '^\d+').Value) } }, Name
)
if ($dateien.Count -eq 0) { throw "Keine nummerierten MP3-Dateien gefunden: $quelle" }

$bundles = [System.Collections.Generic.List[object]]::new()
$aktuell = @()
$dauer = 0.0
# Folgen werden in Quellreihenfolge gesammelt; ein Bundle endet beim Erreichen einer Stunde.
foreach ($datei in $dateien) {
    Write-Host "Lese Dauer: $($datei.Name)"
    $sekunden = Get-Dauer $datei.FullName
    $aktuell += [pscustomobject]@{ Datei = $datei; Dauer = $sekunden }
    $dauer += $sekunden
    if ($dauer -ge $zielSekunden) {
        $bundles.Add([pscustomobject]@{ Folgen = @($aktuell); Dauer = $dauer })
        $aktuell = @()
        $dauer = 0.0
    }
}
# Einen unvollstaendigen Rest an das letzte Bundle anhaengen, damit kein kleines Einzelbundle entsteht.
if ($aktuell.Count -gt 0) {
    if ($bundles.Count -gt 0) {
        $letztes = $bundles[$bundles.Count - 1]
        $letztes.Folgen = @($letztes.Folgen) + @($aktuell)
        $letztes.Dauer += $dauer
    }
    else {
        $bundles.Add([pscustomobject]@{ Folgen = @($aktuell); Dauer = $dauer })
    }
}

New-Item -ItemType Directory -Path $ausgabe -Force | Out-Null

# Vor dem Erzeugen alle Bundle-Grenzen und Zielnamen pruefen, damit vorhandene Ausgaben
# nicht ueberschrieben werden und zu viele Kapitel frueh auffallen.
for ($i = 0; $i -lt $bundles.Count; $i++) {
    $bundle = $bundles[$i]
    if ($bundle.Folgen.Count -gt $maxKapitel) {
        throw "Bundle $($i + 1) enthaelt $($bundle.Folgen.Count) Folgen (maximal $maxKapitel). Bitte Bundle-Groesse anpassen."
    }
    $erste = [int]([regex]::Match($bundle.Folgen[0].Datei.Name, '^\d+').Value)
    $letzte = [int]([regex]::Match($bundle.Folgen[-1].Datei.Name, '^\d+').Value)
    $name = 'AnnaUndDieWildenTiere_Bundle{0:D2}_{1:D3}-{2:D3}' -f ($i + 1), $erste, $letzte
    $bundle | Add-Member -NotePropertyName Name -NotePropertyValue $name
    foreach ($endung in @('.taf', '.txt')) {
        $ziel = Join-Path $ausgabe ($name + $endung)
        if (Test-Path -LiteralPath $ziel) { throw "Zieldatei existiert bereits: $ziel" }
    }
    Write-Host ("Bundle {0}: {1} Folgen, {2}" -f ($i + 1), $bundle.Folgen.Count, (Format-Dauer $bundle.Dauer)) -ForegroundColor Cyan
}

foreach ($bundle in $bundles) {
    $playlist = Join-Path $ausgabe ('.temp_' + [guid]::NewGuid().ToString('N') + '.lst')
    $ziel = Join-Path $ausgabe ($bundle.Name + '.taf')
    $txtZiel = Join-Path $ausgabe ($bundle.Name + '.txt')
    $erfolg = $false
    try {
        # Eine Playlist-Zeile pro Original-MP3 = getrennte Tracks/Kapitel.
        # Anfuehrungszeichen erlauben Windows-Pfade mit Leerzeichen.
        $pfade = @($bundle.Folgen | ForEach-Object { '"' + $_.Datei.FullName + '"' })
        [System.IO.File]::WriteAllLines($playlist, [string[]]$pfade,
            [System.Text.UTF8Encoding]::new($false))

        Write-Host "`nErstelle TAF: $($bundle.Name)" -ForegroundColor Cyan
        & tonietoolbox $playlist $ziel --auto-download
        if ($LASTEXITCODE -ne 0) { throw "TonieToolbox fehlgeschlagen: Exitcode $LASTEXITCODE" }
        if (-not (Test-Path -LiteralPath $ziel -PathType Leaf)) {
            throw "TAF nicht am erwarteten Ziel gefunden: $ziel (pruefe TonieToolbox-Ausgabepfad)"
        }
        if ((Get-Item -LiteralPath $ziel).Length -le 0) { throw "Leere TAF-Datei: $ziel" }

        # Die Textdatei ordnet jeder Folge ihre Startposition im Bundle zu.
        $position = 0.0
        $inhalt = foreach ($folge in $bundle.Folgen) {
            $zeile = '{0}  {1}' -f (Format-Dauer $position), $folge.Datei.Name
            $position += $folge.Dauer
            $zeile
        }
        @(
            "Bundle: $($bundle.Name)"
            "Dauer (Quelle): $(Format-Dauer $bundle.Dauer)"
            "Kapitel/Folgen: $($bundle.Folgen.Count)"
            ''
            'Startzeit und Folge:'
        ) + @($inhalt) | Set-Content -LiteralPath $txtZiel -Encoding UTF8
        $erfolg = $true
        Write-Host "Fertig: $ziel" -ForegroundColor Green
    }
    finally {
        if (Test-Path -LiteralPath $playlist) { Remove-Item -LiteralPath $playlist -Force }
        if (-not $erfolg) { Write-Warning "Fehler bei $($bundle.Name). Eventuelle Teil-TAF vor erneutem Start pruefen." }
    }
}
Write-Host "`nAbgeschlossen! Ausgabe: $ausgabe" -ForegroundColor Green
