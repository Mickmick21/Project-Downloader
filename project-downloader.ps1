# --- Website Configuration ---

# =============================================================================
# WEBSITE CONFIGURATION
# To add a new site, add an item to the $WEBSITE_CONFIG variable:
#     "SITE_ID" = @{
#        Aliases      = @("URL1", "URL2")
#        Reason       = "Reason of why it isn't supported, it should be 'Supported'"
#        UrlPattern   = 'REGEX OF URL'
#        IdExtractor  = { param($url)
#            if ($url -match 'REGEX to extract Project ID') {
#                return [string]$Matches[2]
#            }
#        }
#        AssetBaseUrl = { param($id) return "Base asset URL" }
#        Method       = "extraction_method"
#        Unpackager   = "https://example.com/unpackager/"
#    }
# =============================================================================

$WEBSITE_CONFIG = @{
    "html-classic" = @{
        Aliases      = @("html-classic.itch.zone")
        Reason       = "Supported"
        UrlPattern   = 'html-classic\.itch\.(zone|io)'
        IdExtractor  = { param($url)
            if ($url -match 'html-classic\.itch\.(zone|io)/html/(\d+)') {
                return [string]$Matches[2]
            }
        }
        AssetBaseUrl = { param($id) return "https://html-classic.itch.zone/html/$id/assets" }
        Method       = "embedded_or_json"
        Unpackager   = "https://turbowarp.github.io/unpackager/"
    }
    "scratch" = @{
        Aliases      = @("scratch.mit.edu", "turbowarp.org")
        Reason       = "Supported"
        UrlPattern   = 'scratch\.mit\.edu/projects/\d+|turbowarp\.org/\d+'
        IdExtractor = { param($url)
            if ($url -match 'scratch\.mit\.edu/projects/(\d+)') {
                return $Matches[1]
            }
            if ($url -match 'turbowarp\.org/(\d+)') {
                return $Matches[1]
            }
        }
        AssetBaseUrl = { param($id) return "https://assets.scratch.mit.edu/internalapi/asset" }
        Method       = "scratch_api"
        Unpackager   = ""
    }
}

# --- Colors via Write-Host ---

function Write-Green  { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Blue   { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Red    { param($msg) Write-Host $msg -ForegroundColor Red }
function Write-Yellow { param($msg) Write-Host $msg -ForegroundColor Yellow }

# --- Helper Functions ---

function Prompt-Input {
    param(
        [string]$PromptText,
        [string]$DefaultValue = ""
    )

    if ($DefaultValue -ne "") {
        Write-Host "$PromptText [$DefaultValue]: " -ForegroundColor Cyan -NoNewline
        $userInput = Read-Host
        if ([string]::IsNullOrWhiteSpace($userInput)) { return $DefaultValue }
        return $userInput
    } else {
        Write-Host "${PromptText}: " -ForegroundColor Cyan -NoNewline
        return Read-Host
    }
}

function Validate-File {
    param([string]$File)
    if (-not (Test-Path $File -PathType Leaf)) {
        Write-Red "✗ Error: File '$File' not found"
        return $false
    }
    return $true
}

function Get-WebsiteConfig {
    param([string]$Url)

    foreach ($site in $WEBSITE_CONFIG.GetEnumerator()) {
        if ($Url -match $site.Value.UrlPattern) {
            return @{ Name = $site.Key; Config = $site.Value }
        }
    }
    return $null
}

function Is-ValidUrl {
    param([string]$Url)
    try {
        $uri = [System.Uri]$Url
        return $uri.Scheme -in @('http', 'https')
    } catch {
        return $false
    }
}

function Download-ScratchAssets {
    param(
        [string]$JsonFile,
        [string]$AssetsDir,
        [string]$AssetType
    )

    $json = Get-Content $JsonFile -Raw | ConvertFrom-Json -AsHashtable

    foreach ($target in $json.targets) {
        $assets = $target.$AssetType
        if ($null -eq $assets) { continue }

        foreach ($asset in $assets) {
            $md5ext = $asset.md5ext
            if ([string]::IsNullOrWhiteSpace($md5ext)) { continue }

            $url      = "https://assets.scratch.mit.edu/internalapi/asset/$md5ext/get/"
            $filename = Join-Path $AssetsDir $md5ext

            Write-Host "  Downloading: $md5ext ... " -NoNewline
            try {
                Invoke-WebRequest -Uri $url -OutFile $filename -UseBasicParsing -ErrorAction Stop
                Write-Green "✓"
            } catch {
                Write-Red "✗"
            }
        }
    }
}

function Download-Assets {
    param(
        [string]$JsonFile,
        [string]$BaseUrl,
        [string]$AssetsDir,
        [string]$AssetType
    )

    $json = Get-Content $JsonFile -Raw | ConvertFrom-Json -AsHashtable

    foreach ($target in $json.targets) {
        $assets = $target.$AssetType
        if ($null -eq $assets) { continue }

        foreach ($asset in $assets) {
            $md5ext = $asset.md5ext
            if ([string]::IsNullOrWhiteSpace($md5ext)) { continue }

            $url      = "$BaseUrl/$md5ext"
            $filename = Join-Path $AssetsDir $md5ext

            Write-Host "  Downloading: $md5ext ... " -NoNewline
            try {
                Invoke-WebRequest -Uri $url -OutFile $filename -UseBasicParsing -ErrorAction Stop
                Write-Green "✓"
            } catch {
                Write-Red "✗"
            }
        }
    }
}

# --- Main Logic ---

Write-Blue "=== Project Downloader ===`n"

Write-Blue "Supported websites:"
foreach ($site in $WEBSITE_CONFIG.GetEnumerator()) {
    $aliases = $site.Value.Aliases -join ", "
    $reason = $site.Value.Reason
    Write-Host "  • $aliases ($reason)"
}
Write-Host ""

$INPUT_URL = Prompt-Input "Enter project URL"

if ([string]::IsNullOrWhiteSpace($INPUT_URL)) {
    Write-Red "✗ No URL provided. Exiting."
    exit 1
}

# --- Step 1: Detect website and resolve URL ---

$websiteInfo = Get-WebsiteConfig $INPUT_URL

if ($null -eq $websiteInfo) {
    # Fallback: Try to use the URL as a direct HTML project
    Write-Yellow "`n⚠ URL not found in website configuration."

    if (Is-ValidUrl $INPUT_URL) {
        Write-Yellow "Attempting to use URL as direct HTML project..."

        $headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:124.0) Gecko/20100101 Firefox/124.0" }

        try {
            $PAGE_HTML = (Invoke-WebRequest -Uri $INPUT_URL -Headers $headers -UseBasicParsing -ErrorAction Stop).Content
        } catch {
            Write-Red "✗ Failed to fetch the page: $_"
            Write-Yellow "`nSupported websites:"
            foreach ($site in $WEBSITE_CONFIG.GetEnumerator()) {
                Write-Yellow "  • $($site.Value.Aliases -join ', ')"
            }
            exit 1
        }

        if ([string]::IsNullOrWhiteSpace($PAGE_HTML)) {
            Write-Red "✗ Failed to fetch the page (empty response)."
            exit 1
        }

        Write-Green "✓ Successfully fetched HTML from URL"

        # Generate a short hash from the URL for filenames
        $urlHashBytes = [System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($INPUT_URL))
        $urlHash = ($urlHashBytes | ForEach-Object { $_.ToString("x2") }) -join ""
        $urlHash = $urlHash.Substring(0, 8)

        if ($PAGE_HTML -match '<script data=') {
            # Type A: project data embedded in HTML
            Write-Yellow "`n→ Detected embedded project (data inside HTML)."
            Write-Blue "  Saving HTML file..."

            $SAVE_PATH = Join-Path (Get-Location) "project_fallback_$urlHash.html"
            $PAGE_HTML | Out-File -FilePath $SAVE_PATH -Encoding UTF8

            Write-Green "✓ Saved to: $SAVE_PATH"
            Write-Yellow "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            Write-Yellow "  This HTML file was downloaded from an unrecognized source."
            Write-Yellow "  To unpack this project, upload the saved HTML file to:"
            Write-Green  "  https://turbowarp.github.io/unpackager/"
            Write-Yellow "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n"

        } elseif ($PAGE_HTML -match 'assets/project\.json') {
            # Type B: project.json + assets relative to the page URL
            Write-Blue "`n→ Detected downloadable project (project.json + assets)."

            # Derive asset base URL from the page URL (strip filename, append assets/)
            $pageBaseUrl = $INPUT_URL.Substring(0, $INPUT_URL.LastIndexOf('/'))
            $ASSETS_BASE_URL = "$pageBaseUrl/assets"
            $PROJECT_JSON_URL = "$ASSETS_BASE_URL/project.json"

            Write-Blue "  Assets URL : $ASSETS_BASE_URL"

            $WORK_DIR = Join-Path (Get-Location) "project_fallback_$urlHash"
            New-Item -ItemType Directory -Path $WORK_DIR -Force | Out-Null

            $JSON_FILE = Join-Path $WORK_DIR "project.json"
            Write-Blue "`n→ Downloading project.json..."

            try {
                Invoke-WebRequest -Uri $PROJECT_JSON_URL -OutFile $JSON_FILE -UseBasicParsing -ErrorAction Stop
            } catch {
                Write-Red "✗ Failed to download project.json: $_"
                exit 1
            }

            if (-not (Validate-File $JSON_FILE)) { exit 1 }
            Write-Green "✓ project.json downloaded"

            $ASSETS_DIR = Join-Path $WORK_DIR "assets"
            New-Item -ItemType Directory -Path $ASSETS_DIR -Force | Out-Null

            Write-Blue "`nDownloading costumes..."
            Download-Assets -JsonFile $JSON_FILE -BaseUrl $ASSETS_BASE_URL -AssetsDir $ASSETS_DIR -AssetType "costumes"

            Write-Blue "`nDownloading sounds..."
            Download-Assets -JsonFile $JSON_FILE -BaseUrl $ASSETS_BASE_URL -AssetsDir $ASSETS_DIR -AssetType "sounds"

            Write-Green "`n✓ Asset download complete!`n"

            Write-Host "Do you want to create an .sb3 file? (y/n): " -ForegroundColor Cyan -NoNewline
            $create_zip = Read-Host

            if ($create_zip -match '^[Yy]$') {
                $ZIP_FILENAME = Prompt-Input "Enter sb3 filename" "project_$urlHash.sb3"

                if ($ZIP_FILENAME -notmatch '\.') {
                    $ZIP_FILENAME = "$ZIP_FILENAME.sb3"
                    Write-Blue "No extension provided, using: $ZIP_FILENAME"
                }

                Write-Blue "`nCreating sb3 file..."

                $TEMP_ZIP_DIR = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
                New-Item -ItemType Directory -Path $TEMP_ZIP_DIR -Force | Out-Null

                try {
                    Copy-Item $JSON_FILE (Join-Path $TEMP_ZIP_DIR "project.json")
                    foreach ($f in (Get-ChildItem $ASSETS_DIR -File -ErrorAction SilentlyContinue)) {
                        Copy-Item $f.FullName (Join-Path $TEMP_ZIP_DIR $f.Name)
                    }
                    $OUTPUT_ZIP = Join-Path (Get-Location) $ZIP_FILENAME
                    Compress-Archive -Path "$TEMP_ZIP_DIR\*" -DestinationPath $OUTPUT_ZIP -Force
                    $zip_size = "{0:N2} MB" -f ((Get-Item $OUTPUT_ZIP).Length / 1MB)
                    Write-Green "✓ SB3 created: $OUTPUT_ZIP ($zip_size)"
                } catch {
                    Write-Red "✗ Failed to create sb3 file: $_"
                } finally {
                    Remove-Item $TEMP_ZIP_DIR -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

        } else {
            Write-Red "✗ Could not determine project type from the page."
            Write-Yellow "  The page may use an unsupported packaging format."
            exit 1
        }

        Write-Green "`nDone!"
        exit 0

    } else {
        Write-Red "✗ Invalid URL format."
        Write-Yellow "Supported websites:"
        foreach ($site in $WEBSITE_CONFIG.GetEnumerator()) {
            Write-Yellow "  • $($site.Value.Aliases -join ', ')"
        }
        exit 1
    }
}

$siteName = $websiteInfo.Name
$siteConfig = $websiteInfo.Config

Write-Green "✓ Detected: $siteName"

# Check if website is supported
if ($siteConfig.Method -eq "not_supported") {
    Write-Red "✗ $siteName is not supported: $($siteConfig.Reason)"
    exit 1
}

# Extract project ID
$projectId = & $siteConfig.IdExtractor $INPUT_URL

if ([string]::IsNullOrWhiteSpace($projectId)) {
    Write-Red "✗ Could not extract project ID from URL: $INPUT_URL"
    exit 1
}

Write-Blue "`n→ Project ID: $projectId"

# --- Step 2: Fetch the page ---

Write-Blue "`n→ Fetching project page..."

$headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:124.0) Gecko/20100101 Firefox/124.0" }

try {
    $PAGE_HTML = (Invoke-WebRequest -Uri $INPUT_URL -Headers $headers -UseBasicParsing -ErrorAction Stop).Content
} catch {
    Write-Red "✗ Failed to fetch the page: $_"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($PAGE_HTML)) {
    Write-Red "✗ Failed to fetch the page (empty response)."
    exit 1
}

Write-Green "✓ Page fetched successfully"

# --- Step 3: Detect project type and process ---

if ($PAGE_HTML -match '<script data=') {
    # Type A: project data embedded in HTML
    Write-Yellow "`n→ Detected embedded project (data inside HTML)."
    Write-Blue "  Saving HTML file..."

    $SAVE_PATH = Join-Path (Get-Location) "project_embedded_$projectId.html"
    $PAGE_HTML | Out-File -FilePath $SAVE_PATH -Encoding UTF8

    Write-Green "✓ Saved to: $SAVE_PATH"

    if ($siteConfig.Unpackager) {
        Write-Yellow "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        Write-Yellow "  To unpack this project, upload the saved HTML file to:"
        Write-Green  "  $($siteConfig.Unpackager)"
        Write-Yellow "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n"
    }

} elseif ($PAGE_HTML -match 'assets/project\.json') {
    # Type B: project downloaded at runtime
    Write-Blue "`n→ Detected downloadable project (project.json + assets)."

    $ASSETS_BASE_URL  = & $siteConfig.AssetBaseUrl $projectId
    $PROJECT_JSON_URL = "$ASSETS_BASE_URL/project.json"

    Write-Blue "  Assets URL : $ASSETS_BASE_URL"

    # Download project.json
    $WORK_DIR = Join-Path (Get-Location) "${siteName}_project_$projectId"
    New-Item -ItemType Directory -Path $WORK_DIR -Force | Out-Null

    $JSON_FILE = Join-Path $WORK_DIR "project.json"
    Write-Blue "`n→ Downloading project.json..."

    try {
        Invoke-WebRequest -Uri $PROJECT_JSON_URL -OutFile $JSON_FILE -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Red "✗ Failed to download project.json: $_"
        exit 1
    }

    if (-not (Validate-File $JSON_FILE)) { exit 1 }

    Write-Green "✓ project.json downloaded"

    # Download assets
    $ASSETS_DIR = Join-Path $WORK_DIR "assets"
    New-Item -ItemType Directory -Path $ASSETS_DIR -Force | Out-Null

    Write-Blue "`nDownloading costumes..."
    Download-Assets -JsonFile $JSON_FILE -BaseUrl $ASSETS_BASE_URL -AssetsDir $ASSETS_DIR -AssetType "costumes"

    Write-Blue "`nDownloading sounds..."
    Download-Assets -JsonFile $JSON_FILE -BaseUrl $ASSETS_BASE_URL -AssetsDir $ASSETS_DIR -AssetType "sounds"

    Write-Green "`n✓ Asset download complete!`n"

    # Create SB3
    Write-Host "Do you want to create an .sb3 file? (y/n): " -ForegroundColor Cyan -NoNewline
    $create_zip = Read-Host

    if ($create_zip -match '^[Yy]$') {
        $ZIP_FILENAME = Prompt-Input "Enter sb3 filename" "project_$projectId.sb3"

        if ($ZIP_FILENAME -notmatch '\.') {
            $ZIP_FILENAME = "$ZIP_FILENAME.sb3"
            Write-Blue "No extension provided, using: $ZIP_FILENAME"
        }

        Write-Blue "`nCreating sb3 file..."

        $TEMP_ZIP_DIR = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $TEMP_ZIP_DIR -Force | Out-Null

        try {
            Copy-Item $JSON_FILE (Join-Path $TEMP_ZIP_DIR "project.json")

            $assetFiles = Get-ChildItem $ASSETS_DIR -File -ErrorAction SilentlyContinue
            foreach ($f in $assetFiles) {
                Copy-Item $f.FullName (Join-Path $TEMP_ZIP_DIR $f.Name)
            }

            $OUTPUT_ZIP = Join-Path (Get-Location) $ZIP_FILENAME

            Compress-Archive -Path "$TEMP_ZIP_DIR\*" -DestinationPath $OUTPUT_ZIP -Force

            $zip_size = "{0:N2} MB" -f ((Get-Item $OUTPUT_ZIP).Length / 1MB)
            Write-Green "✓ SB3 created: $OUTPUT_ZIP ($zip_size)"
        } catch {
            Write-Red "✗ Failed to create sb3 file: $_"
        } finally {
            Remove-Item $TEMP_ZIP_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

} elseif ($siteConfig.Method -eq "scratch_api") {
    Write-Blue "`n→ Scratch API project detected."

    $meta  = Invoke-RestMethod -Uri "https://api.scratch.mit.edu/projects/$projectId" -ErrorAction Stop
    $token = $meta.project_token
    $title = $meta.title -replace '[^a-zA-Z0-9_-]', '_'

    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Yellow "⚠ No token found - project may be unshared. Attempting direct download..."
        $projectJsonUrl = "https://projects.scratch.mit.edu/$projectId"
    } else {
        $projectJsonUrl = "https://projects.scratch.mit.edu/${projectId}?token=$token"
    }

    $WORK_DIR = Join-Path (Get-Location) "scratch_project_$projectId"
    New-Item -ItemType Directory -Path $WORK_DIR -Force | Out-Null

    $JSON_FILE = Join-Path $WORK_DIR "project.json"
    Write-Blue "`n→ Downloading project.json..."

    try {
        Invoke-WebRequest -Uri $projectJsonUrl -OutFile $JSON_FILE -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Red "✗ Failed to download project.json: $_"
        exit 1
    }

    if (-not (Validate-File $JSON_FILE)) { exit 1 }
    Write-Green "✓ project.json downloaded"

    $ASSETS_DIR = Join-Path $WORK_DIR "assets"
    New-Item -ItemType Directory -Path $ASSETS_DIR -Force | Out-Null

    Write-Blue "`nDownloading costumes..."
    Download-ScratchAssets -JsonFile $JSON_FILE -AssetsDir $ASSETS_DIR -AssetType "costumes"

    Write-Blue "`nDownloading sounds..."
    Download-ScratchAssets -JsonFile $JSON_FILE -AssetsDir $ASSETS_DIR -AssetType "sounds"

    Write-Green "`n✓ Asset download complete!`n"

    Write-Host "Do you want to create an .sb3 file? (y/n): " -ForegroundColor Cyan -NoNewline
    $create_zip = Read-Host
    if ($create_zip -match '^[Yy]$') {
        $ZIP_FILENAME = Prompt-Input "Enter sb3 filename" "${title}_$projectId.sb3"
        if ($ZIP_FILENAME -notmatch '\.') {
            $ZIP_FILENAME = "$ZIP_FILENAME.sb3"
            Write-Blue "No extension provided, using: $ZIP_FILENAME"
        }
        Write-Blue "`nCreating sb3 file..."
        $TEMP_ZIP_DIR = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $TEMP_ZIP_DIR -Force | Out-Null
        try {
            Copy-Item $JSON_FILE (Join-Path $TEMP_ZIP_DIR "project.json")
            foreach ($f in (Get-ChildItem $ASSETS_DIR -File -ErrorAction SilentlyContinue)) {
                Copy-Item $f.FullName (Join-Path $TEMP_ZIP_DIR $f.Name)
            }
            $OUTPUT_ZIP = Join-Path (Get-Location) $ZIP_FILENAME
            Compress-Archive -Path "$TEMP_ZIP_DIR\*" -DestinationPath $OUTPUT_ZIP -Force
            $zip_size = "{0:N2} MB" -f ((Get-Item $OUTPUT_ZIP).Length / 1MB)
            Write-Green "✓ SB3 created: $OUTPUT_ZIP ($zip_size)"
        } catch {
            Write-Red "✗ Failed to create sb3 file: $_"
        } finally {
            Remove-Item $TEMP_ZIP_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

} else {
    Write-Red "✗ Could not determine project type from the page."
    Write-Yellow "  The page may use an unsupported packaging format."
    exit 1
}

Write-Green "`nDone!"
