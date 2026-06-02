$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$OutputTracksFile = Join-Path $ScriptDir "tracks.txt"
$LogFile = Join-Path $ScriptDir "autofind-log.txt"

$ResultsPerSearch = 8
$MaxTracks = 45

$AutoGitPush = $false
$GitCommitMessage = "Update ScrollFunk auto tracks"

$SearchTerms = @(
    "brazilian funk edit",
    "funk carioca edit",
    "montagem funk edit",
    "phonk funk edit",
    "funk remix edit",
    "slowed funk edit",
    "aggressive funk edit",
    "brazilian phonk edit",
    "tiktok funk edit",
    "mc funk edit"
)

function Write-Log {
    param([string]$Text)

    $Line = "[" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "] " + $Text
    Write-Host $Line
    Add-Content -Path $LogFile -Value $Line -Encoding UTF8
}

function Get-YtdlpPath {
    $PossiblePaths = @(
        (Join-Path $ScriptDir "yt-dlp.exe"),
        (Join-Path $ScriptDir "tools\yt-dlp.exe"),
        (Join-Path (Split-Path -Parent $ScriptDir) "tools\yt-dlp.exe")
    )

    foreach ($Path in $PossiblePaths) {
        if (Test-Path $Path) {
            return $Path
        }
    }

    $Command = Get-Command "yt-dlp.exe" -ErrorAction SilentlyContinue

    if ($null -ne $Command) {
        return $Command.Source
    }

    throw "yt-dlp.exe nebyl nalezen. Dej yt-dlp.exe do stejne slozky jako AutoFindFunks.ps1 nebo do slozky tools."
}

function Clean-Title {
    param([string]$Title)

    if ($null -eq $Title) {
        return ""
    }

    $Clean = $Title.Trim()
    $Clean = $Clean.Replace("|", "-")
    $Clean = $Clean.Replace("`r", " ")
    $Clean = $Clean.Replace("`n", " ")
    $Clean = $Clean -replace "\s+", " "

    if ($Clean.Length -gt 95) {
        $Clean = $Clean.Substring(0, 95).Trim()
    }

    return $Clean
}

function Is-BadResult {
    param(
        [string]$Title,
        [string]$Url
    )

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $true
    }

    if ($Url -notmatch "youtube\.com|youtu\.be") {
        return $true
    }

    $LowerTitle = $Title.ToLower()
    $LowerUrl = $Url.ToLower()

    if ($LowerUrl.Contains("/shorts/")) {
        return $true
    }

    $BlockedWords = @(
        "1 hour",
        "10 hours",
        "extended",
        "full album",
        "playlist",
        "mix 2020",
        "mix 2021",
        "mix 2022",
        "mix 2023",
        "mix 2024",
        "mix 2025",
        "live stream",
        "reaction",
        "tutorial",
        "how to",
        "podcast"
    )

    foreach ($Word in $BlockedWords) {
        if ($LowerTitle.Contains($Word)) {
            return $true
        }
    }

    return $false
}

function Normalize-Url {
    param([string]$Url)

    if ($null -eq $Url) {
        return ""
    }

    $Clean = $Url.Trim()

    if ($Clean.StartsWith("https://www.youtube.com/watch?v=")) {
        $VideoId = $Clean.Replace("https://www.youtube.com/watch?v=", "")
        $VideoId = ($VideoId -split "&")[0]
        return "https://www.youtube.com/watch?v=$VideoId"
    }

    if ($Clean.StartsWith("https://youtu.be/")) {
        $VideoId = $Clean.Replace("https://youtu.be/", "")
        $VideoId = ($VideoId -split "\?")[0]
        return "https://www.youtube.com/watch?v=$VideoId"
    }

    return $Clean
}

function Search-Funks {
    param(
        [string]$YtdlpPath,
        [string]$SearchTerm,
        [int]$Limit
    )

    $SearchArg = "ytsearch$Limit`:$SearchTerm"

    Write-Log "Hledam: $SearchTerm"

    $Output = & $YtdlpPath `
        --flat-playlist `
        --no-warnings `
        --ignore-errors `
        --print "%(title)s|||%(webpage_url)s" `
        $SearchArg 2>$null

    $Found = @()

    foreach ($RawLine in $Output) {
        $Line = [string]$RawLine

        if ($Line -notmatch "\|\|\|") {
            continue
        }

        $Parts = $Line -split "\|\|\|", 2

        if ($Parts.Count -ne 2) {
            continue
        }

        $Title = Clean-Title $Parts[0]
        $Url = Normalize-Url $Parts[1]

        if (Is-BadResult $Title $Url) {
            continue
        }

        $Found += [PSCustomObject]@{
            Title = $Title
            Url = $Url
            Search = $SearchTerm
        }
    }

    return $Found
}

function Save-TracksFile {
    param(
        [array]$Tracks,
        [string]$Path
    )

    $Lines = @()
    $Lines += "# ScrollFunk auto generated tracks"
    $Lines += "# Generated: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $Lines += "# Format: Title | YouTube URL"
    $Lines += ""

    foreach ($Track in $Tracks) {
        $Lines += $Track.Title + " | " + $Track.Url
    }

    Set-Content -Path $Path -Value $Lines -Encoding UTF8
}

function Try-GitPush {
    param(
        [string]$RepoDir,
        [string]$CommitMessage
    )

    $GitFolder = Join-Path $RepoDir ".git"

    if (!(Test-Path $GitFolder)) {
        Write-Log "Git push preskocen: tahle slozka neni git repo."
        return
    }

    $GitCommand = Get-Command "git.exe" -ErrorAction SilentlyContinue

    if ($null -eq $GitCommand) {
        Write-Log "Git push preskocen: git.exe nebyl nalezen."
        return
    }

    Write-Log "Git add tracks.txt..."
    & git -C $RepoDir add tracks.txt | Out-Null

    $Status = & git -C $RepoDir status --porcelain

    if ([string]::IsNullOrWhiteSpace($Status)) {
        Write-Log "Git: zadne zmeny k uploadu."
        return
    }

    Write-Log "Git commit..."
    & git -C $RepoDir commit -m $CommitMessage | Out-Null

    Write-Log "Git push..."
    & git -C $RepoDir push | Out-Null

    Write-Log "Git push hotovy."
}

try {
    if (Test-Path $LogFile) {
        Remove-Item $LogFile -Force
    }

    Write-Log "Startuju ScrollFunk Auto Finder."

    $YtdlpPath = Get-YtdlpPath
    Write-Log "Pouzivam yt-dlp: $YtdlpPath"

    $AllTracks = @()
    $SeenUrls = @{}

    $RandomTerms = $SearchTerms | Sort-Object { Get-Random }

    foreach ($Term in $RandomTerms) {
        $Results = Search-Funks $YtdlpPath $Term $ResultsPerSearch

        foreach ($Result in $Results) {
            if ($AllTracks.Count -ge $MaxTracks) {
                break
            }

            if ($SeenUrls.ContainsKey($Result.Url)) {
                continue
            }

            $SeenUrls[$Result.Url] = $true
            $AllTracks += $Result

            Write-Log "OK: $($Result.Title)"
        }

        if ($AllTracks.Count -ge $MaxTracks) {
            break
        }
    }

    if ($AllTracks.Count -eq 0) {
        throw "Nenalezen zadny funk. Zkontroluj internet nebo yt-dlp."
    }

    $FinalTracks = $AllTracks | Sort-Object { Get-Random }

    Save-TracksFile $FinalTracks $OutputTracksFile

    Write-Log "Vytvoren soubor: $OutputTracksFile"
    Write-Log "Pocet tracku: $($FinalTracks.Count)"

    if ($AutoGitPush -eq $true) {
        Try-GitPush $ScriptDir $GitCommitMessage
    }
    else {
        Write-Log "AutoGitPush je vypnuty. tracks.txt je jen lokalne aktualizovany."
    }

    Write-Host ""
    Write-Host "======================================" -ForegroundColor Green
    Write-Host " HOTOVO - ScrollFunk nasel funky sam" -ForegroundColor Green
    Write-Host "======================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Soubor vytvoren:"
    Write-Host $OutputTracksFile
    Write-Host ""
    Write-Host "Prvni nalezene funky:"
    Write-Host ""

    $Preview = $FinalTracks | Select-Object -First 10

    foreach ($Track in $Preview) {
        Write-Host ("- " + $Track.Title)
    }

    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "ERROR:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    Add-Content -Path $LogFile -Value ("ERROR: " + $_.Exception.Message) -Encoding UTF8
    exit 1
}
