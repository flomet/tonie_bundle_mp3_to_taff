# Tonie TAF-Bundles aus MP3-Dateien

Dieses PowerShell-Skript erstellt aus nummerierten MP3-Dateien TAF-Bundles mit ungefaehr einer Stunde Laufzeit. Jede Originaldatei bleibt ein eigenes Kapitel beziehungsweise ein eigener Track. Zu jedem Bundle werden eine `.taf`-Datei und eine `.txt`-Uebersicht mit den Startzeiten der Folgen erzeugt.

## Voraussetzungen

- Windows mit PowerShell 7 oder Windows PowerShell
- `ffprobe` aus FFmpeg im `PATH`
- `tonietoolbox` im `PATH`
- MP3-Dateien im selben Ordner wie das Skript; ihre Dateinamen muessen mit einer Nummer beginnen, zum Beispiel `001 - Folge.mp3`

## Verwendung

Lege die nummerierten MP3-Dateien neben `New-Tonie-TAFBundles.ps1` und starte PowerShell in diesem Ordner:

```powershell
pwsh -NoProfile -File .\New-Tonie-TAFBundles.ps1
```

Alternativ kannst du das Skript in Windows PowerShell mit `powershell -NoProfile -File .\New-Tonie-TAFBundles.ps1` starten.

## Verhalten

- Dateien werden zuerst nach der fuehrenden Zahl und danach nach dem Dateinamen sortiert.
- Die Laufzeit wird mit `ffprobe` ermittelt. Ein Bundle wird abgeschlossen, sobald seine Gesamtlaufzeit mindestens 3.600 Sekunden erreicht.
- Ein verbleibender Rest wird an das letzte Bundle angehaengt. Gibt es noch kein Bundle, bilden die Restdateien das erste.
- Pro Bundle sind maximal 99 Kapitel erlaubt.
- Die Skriptausgabe landet im Unterordner `TAF_Bundles_1h` neben dem Skript.
- Vorhandene `.taf`- oder `.txt`-Zieldateien werden nicht ueberschrieben; das Skript bricht stattdessen ab.

Die TAF-Dateinamen enthalten die Bundle-Nummer und die Nummern der ersten und letzten Folge. Die Textdatei listet die jeweilige Startzeit sowie den Originaldateinamen.

## Hinweise

Das Skript erzeugt Dateien aus deinen lokalen Audiodateien. Pruefe vor einer Veroeffentlichung, ob du die Rechte hast, sowohl das Skript als auch eventuell enthaltene Beispieldaten oder Audioinhalte zu teilen. Audiodateien sollten nicht in dieses Repository aufgenommen werden, sofern du keine ausdrueckliche Freigabe dafuer hast.