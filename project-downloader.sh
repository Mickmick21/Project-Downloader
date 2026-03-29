#!/usr/bin/env bash

# =============================================================================
# WEBSITE CONFIGURATION
# To add a new site, define the following variables for each SITE_ID:
#
#   SITE_<ID>_ALIASES      - Comma-separated list of hostnames
#   SITE_<ID>_REASON       - "Supported" or reason it's not supported
#   SITE_<ID>_URL_PATTERN  - Extended regex to match the URL (used in =~)
#   SITE_<ID>_ID_EXTRACTOR - Bash function name that extracts the project ID
#   SITE_<ID>_ASSET_BASE   - Bash function name that returns the asset base URL
#   SITE_<ID>_METHOD       - "embedded_or_json" or "not_supported"
#   SITE_<ID>_UNPACKAGER   - URL to the unpackager tool (or empty)
#
# Then add the SITE_ID to the SITES array below.
# =============================================================================

SITES=("HTML_CLASSIC" "SCRATCH")

# --- scratch.mit.edu ---
SITE_SCRATCH_ALIASES="scratch.mit.edu, turbowarp.org"
SITE_SCRATCH_REASON="Supported"
SITE_SCRATCH_URL_PATTERN='turbowarp\.org\/([0-9]+)|scratch\.mit\.edu\/projects\/([0-9]+)'
SITE_SCRATCH_METHOD="scratch_api"
SITE_SCRATCH_UNPACKAGER=""

site_scratch_id_extractor() {
    local url="$1"
    if [[ "$url" =~ scratch\.mit\.edu/projects/([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ "$url" =~ turbowarp\.org/([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

site_scratch_asset_base() {
    echo "https://assets.scratch.mit.edu/internalapi/asset"
}

# --- html-classic.itch.zone / html-classic.itch.io ---
SITE_HTML_CLASSIC_ALIASES="html-classic.itch.zone"
SITE_HTML_CLASSIC_REASON="Supported"
SITE_HTML_CLASSIC_URL_PATTERN='html-classic\.itch\.zone'
SITE_HTML_CLASSIC_METHOD="embedded_or_json"
SITE_HTML_CLASSIC_UNPACKAGER="https://turbowarp.github.io/unpackager/"

site_html_classic_id_extractor() {
    local url="$1"
    if [[ "$url" =~ html-classic\.itch\.(zone|io)/html/([0-9]+) ]]; then
        echo "${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

site_html_classic_asset_base() {
    local id="$1"
    echo "https://html-classic.itch.zone/html/${id}/assets"
}

# =============================================================================
# END OF WEBSITE CONFIGURATION
# =============================================================================

# --- Colors ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

write_green()  { echo -e "${GREEN}$1${NC}"; }
write_blue()   { echo -e "${CYAN}$1${NC}"; }
write_red()    { echo -e "${RED}$1${NC}"; }
write_yellow() { echo -e "${YELLOW}$1${NC}"; }

# --- Helper Functions ---

prompt_input() {
    local prompt_text="$1"
    local default_value="$2"
    local user_input

    if [[ -n "$default_value" ]]; then
        echo -ne "${CYAN}${prompt_text} [${default_value}]: ${NC}" >&2
        read user_input
        echo "${user_input:-$default_value}"
    else
        echo -ne "${CYAN}${prompt_text}: ${NC}" >&2
        read user_input
        echo "$user_input"
    fi
}

validate_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        write_red "✗ Error: File '$file' not found"
        return 1
    fi
    return 0
}

# Returns the SITE_ID (e.g. "HTML_CLASSIC") matching the given URL, or nothing
get_site_id() {
    local url="$1"
    for site_id in "${SITES[@]}"; do
        local pattern_var="SITE_${site_id}_URL_PATTERN"
        local pattern="${!pattern_var}"
        if [[ "$url" =~ $pattern ]]; then
            echo "$site_id"
            return 0
        fi
    done
    return 1
}

download_scratch_assets() {
    local json_file="$1"
    local assets_dir="$2"
    local asset_type="$3"

    local md5exts
    md5exts=$(python3 -c "
import json
with open('$json_file') as f:
    data = json.load(f)
for target in data.get('targets', []):
    for asset in target.get('$asset_type', []):
        ext = asset.get('md5ext', '')
        if ext:
            print(ext)
")

    while IFS= read -r md5ext; do
        [[ -z "$md5ext" ]] && continue
        local url="https://assets.scratch.mit.edu/internalapi/asset/${md5ext}/get/"
        local filename="${assets_dir}/${md5ext}"

        if [[ -f "$filename" ]]; then
            echo "  Skipping: ${md5ext} (already exists)"
            continue
        fi

        echo -ne "  Downloading: ${md5ext} ... "
        if curl -s -f -o "$filename" "$url"; then
            write_green "✓"
        else
            write_red "✗"
        fi
    done <<< "$md5exts"
}

download_assets() {
    local json_file="$1"
    local base_url="$2"
    local assets_dir="$3"
    local asset_type="$4"   # "costumes" or "sounds"

    local md5exts
    md5exts=$(python3 -c "
import json, sys
with open('$json_file') as f:
    data = json.load(f)
for target in data.get('targets', []):
    for asset in target.get('$asset_type', []):
        ext = asset.get('md5ext', '')
        if ext:
            print(ext)
")

    while IFS= read -r md5ext; do
        [[ -z "$md5ext" ]] && continue
        local url="${base_url}/${md5ext}"
        local filename="${assets_dir}/${md5ext}"

        if [[ -f "$filename" ]]; then
            echo "  Skipping: ${md5ext} (already exists)"
            continue
        fi

        echo -ne "  Downloading: ${md5ext} ... "
        if curl -s -f -o "$filename" "$url"; then
            write_green "✓"
        else
            write_red "✗"
        fi
    done <<< "$md5exts"
}

download_fonts() {
    local json_file="$1"
    local base_url="$2"
    local assets_dir="$3"

    local md5exts
    md5exts=$(python3 -c "
import json, sys
with open('$json_file') as f:
    data = json.load(f)
for font in data.get('customFonts', []):
    ext = font.get('md5ext', '')
    if ext:
        print(ext)
")

    local found=0
    while IFS= read -r md5ext; do
        [[ -z "$md5ext" ]] && continue
        found=1
        local url="${base_url}/${md5ext}"
        local filename="${assets_dir}/${md5ext}"

        if [[ -f "$filename" ]]; then
            echo "  Skipping: ${md5ext} (already exists)"
            continue
        fi

        echo -ne "  Downloading: ${md5ext} ... "
        if curl -s -f -o "$filename" "$url"; then
            write_green "✓"
        else
            write_red "✗"
        fi
    done <<< "$md5exts"

    [[ $found -eq 0 ]] && write_blue "  (no custom fonts)"
}

# --- Main Logic ---

write_blue "=== Project Downloader ===\n"

write_blue "Supported websites:"
for site_id in "${SITES[@]}"; do
    aliases_var="SITE_${site_id}_ALIASES"
    reason_var="SITE_${site_id}_REASON"
    echo "  • ${!aliases_var} (${!reason_var})"
done
echo ""

INPUT_URL=$(prompt_input "Enter project URL")

if [[ -z "$INPUT_URL" ]]; then
    write_red "✗ No URL provided. Exiting."
    exit 1
fi

# --- Step 1: Detect website ---

SITE_ID=$(get_site_id "$INPUT_URL")

if [[ -z "$SITE_ID" ]]; then
    write_yellow "\n⚠ URL not found in website configuration."

    # Validate that it at least looks like an http(s) URL
    if [[ "$INPUT_URL" =~ ^https?:// ]]; then
        write_yellow "Attempting to use URL as direct HTML project..."

        PAGE_HTML=$(curl -s -f -L \
            -A "Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0" \
            "$INPUT_URL")

        if [[ $? -ne 0 || -z "$PAGE_HTML" ]]; then
            write_red "✗ Failed to fetch the page."
            write_yellow "\nSupported websites:"
            for site_id in "${SITES[@]}"; do
                aliases_var="SITE_${site_id}_ALIASES"
                write_yellow "  • ${!aliases_var}"
            done
            exit 1
        fi

        write_green "✓ Successfully fetched HTML from URL"

        URL_HASH=$(echo -n "$INPUT_URL" | md5sum | cut -c1-8)

        if echo "$PAGE_HTML" | grep -q '<script data='; then
            # Type A: project data embedded in HTML
            write_yellow "\n→ Detected embedded project (data inside HTML)."
            write_blue "  Saving HTML file..."

            SAVE_PATH="$(pwd)/project_fallback_${URL_HASH}.html"
            echo "$PAGE_HTML" > "$SAVE_PATH"

            write_green "✓ Saved to: $SAVE_PATH"
            write_yellow "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            write_yellow "  This HTML file was downloaded from an unrecognized source."
            write_yellow "  To unpack this project, upload the saved HTML file to:"
            write_green  "  https://turbowarp.github.io/unpackager/"
            write_yellow "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

        elif echo "$PAGE_HTML" | grep -q 'assets/project\.json'; then
            # Type B: project.json + assets relative to the page URL
            write_blue "\n→ Detected downloadable project (project.json + assets)."

            # Derive asset base URL from the page URL (strip filename, append assets/)
            PAGE_BASE_URL="${INPUT_URL%/*}"
            ASSETS_BASE_URL="${PAGE_BASE_URL}/assets"
            PROJECT_JSON_URL="${ASSETS_BASE_URL}/project.json"

            write_blue "  Assets URL : $ASSETS_BASE_URL"

            WORK_DIR="$(pwd)/project_fallback_${URL_HASH}"
            mkdir -p "$WORK_DIR"

            JSON_FILE="${WORK_DIR}/project.json"
            write_blue "\n→ Downloading project.json..."

            if ! curl -s -f -o "$JSON_FILE" "$PROJECT_JSON_URL"; then
                write_red "✗ Failed to download project.json"
                exit 1
            fi

            validate_file "$JSON_FILE" || exit 1
            write_green "✓ project.json downloaded"

            ASSETS_DIR="${WORK_DIR}/assets"
            mkdir -p "$ASSETS_DIR"

            write_blue "\nDownloading costumes..."
            download_assets "$JSON_FILE" "$ASSETS_BASE_URL" "$ASSETS_DIR" "costumes"

            write_blue "\nDownloading sounds..."
            download_assets "$JSON_FILE" "$ASSETS_BASE_URL" "$ASSETS_DIR" "sounds"

            write_blue "\nDownloading fonts..."
            download_fonts "$JSON_FILE" "$ASSETS_BASE_URL" "$ASSETS_DIR"

            write_green "\n✓ Asset download complete!\n"

            echo -ne "${CYAN}Do you want to create an .sb3 file? (y/n): ${NC}"
            read create_zip

            if [[ "$create_zip" =~ ^[Yy]$ ]]; then
                ZIP_FILENAME=$(prompt_input "Enter sb3 filename" "project_${URL_HASH}.sb3")

                if [[ "$ZIP_FILENAME" != *.* ]]; then
                    ZIP_FILENAME="${ZIP_FILENAME}.sb3"
                    write_blue "No extension provided, using: $ZIP_FILENAME"
                fi

                write_blue "\nCreating sb3 file..."

                TEMP_ZIP_DIR=$(mktemp -d)
                trap "rm -rf $TEMP_ZIP_DIR" EXIT

                cp "$JSON_FILE" "${TEMP_ZIP_DIR}/project.json"
                for f in "$ASSETS_DIR"/*; do
                    [[ -f "$f" ]] && cp "$f" "$TEMP_ZIP_DIR/"
                done

                OUTPUT_ZIP="$(pwd)/${ZIP_FILENAME}"

                if (cd "$TEMP_ZIP_DIR" && zip -r "$OUTPUT_ZIP" .); then
                    ZIP_SIZE=$(du -sh "$OUTPUT_ZIP" | cut -f1)
                    write_green "✓ SB3 created: $OUTPUT_ZIP ($ZIP_SIZE)"
                else
                    write_red "✗ Failed to create sb3 file"
                fi
            fi

        else
            write_red "✗ Could not determine project type from the page."
            write_yellow "  The page may use an unsupported packaging format."
            exit 1
        fi

        write_green "\nDone!"
        exit 0
    else
        write_red "✗ Invalid URL format."
        write_yellow "Supported websites:"
        for site_id in "${SITES[@]}"; do
            aliases_var="SITE_${site_id}_ALIASES"
            write_yellow "  • ${!aliases_var}"
        done
        exit 1
    fi
fi

aliases_var="SITE_${SITE_ID}_ALIASES"
write_green "✓ Detected: ${!aliases_var}"

method_var="SITE_${SITE_ID}_METHOD"
if [[ "${!method_var}" == "not_supported" ]]; then
    reason_var="SITE_${SITE_ID}_REASON"
    write_red "✗ ${!aliases_var} is not supported: ${!reason_var}"
    exit 1
fi

# Extract project ID via this site's extractor function
id_extractor_fn="site_${SITE_ID,,}_id_extractor"
PROJECT_ID=$("$id_extractor_fn" "$INPUT_URL")

if [[ -z "$PROJECT_ID" ]]; then
    write_red "✗ Could not extract project ID from URL: $INPUT_URL"
    exit 1
fi

write_blue "\n→ Project ID: $PROJECT_ID"

# --- Step 2: Fetch the page ---

write_blue "\n→ Fetching project page..."

PAGE_HTML=$(curl -s -f -A "Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0" "$INPUT_URL")

if [[ $? -ne 0 || -z "$PAGE_HTML" ]]; then
    write_red "✗ Failed to fetch the page."
    exit 1
fi

write_green "✓ Page fetched successfully"

# --- Step 3: Detect project type and process ---

unpackager_var="SITE_${SITE_ID}_UNPACKAGER"

if echo "$PAGE_HTML" | grep -q '<script data='; then
    # Type A: project data embedded in HTML
    write_yellow "\n→ Detected embedded project (data inside HTML)."
    write_blue "  Saving HTML file..."

    SAVE_PATH="$(pwd)/project_embedded_${PROJECT_ID}.html"
    echo "$PAGE_HTML" > "$SAVE_PATH"

    write_green "✓ Saved to: $SAVE_PATH"

    if [[ -n "${!unpackager_var}" ]]; then
        write_yellow "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        write_yellow "  To unpack this project, upload the saved HTML file to:"
        write_green  "  ${!unpackager_var}"
        write_yellow "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    fi

elif [[ "${!method_var}" == "scratch_api" ]]; then
    write_blue "\n→ Scratch API project detected."

    META=$(curl -s "https://api.scratch.mit.edu/projects/$PROJECT_ID")
    TOKEN=$(echo "$META" | jq -r '.project_token // empty')
    TITLE=$(echo "$META" | jq -r '.title' | sed 's/[^a-zA-Z0-9_-]/_/g')

    if [[ -z "$TOKEN" ]]; then
        write_yellow "⚠ No token found — project may be unshared. Attempting direct download..."
        PROJECT_JSON_URL="https://projects.scratch.mit.edu/$PROJECT_ID"
    else
        PROJECT_JSON_URL="https://projects.scratch.mit.edu/$PROJECT_ID?token=$TOKEN"
    fi

    WORK_DIR="$(pwd)/scratch_project_${PROJECT_ID}"
    mkdir -p "$WORK_DIR"

    JSON_FILE="${WORK_DIR}/project.json"
    write_blue "\n→ Downloading project.json..."

    if ! curl -s -f -L -o "$JSON_FILE" "$PROJECT_JSON_URL"; then
        write_red "✗ Failed to download project.json"
        exit 1
    fi

    validate_file "$JSON_FILE" || exit 1
    write_green "✓ project.json downloaded"

    ASSETS_DIR="${WORK_DIR}/assets"
    mkdir -p "$ASSETS_DIR"

    # Scratch assets are fetched from a different URL structure
    download_scratch_assets "$JSON_FILE" "$ASSETS_DIR" "costumes"
    download_scratch_assets "$JSON_FILE" "$ASSETS_DIR" "sounds"

    write_green "\n✓ Asset download complete!\n"

    # SB3 creation (same as before)
    echo -ne "${CYAN}Do you want to create an .sb3 file? (y/n): ${NC}"
    read create_zip
    if [[ "$create_zip" =~ ^[Yy]$ ]]; then
        ZIP_FILENAME=$(prompt_input "Enter sb3 filename" "${TITLE:-project_${PROJECT_ID}}.sb3")
        if [[ "$ZIP_FILENAME" != *.* ]]; then
            ZIP_FILENAME="${ZIP_FILENAME}.sb3"
            write_blue "No extension provided, using: $ZIP_FILENAME"
        fi
        write_blue "\nCreating sb3 file..."
        TEMP_ZIP_DIR=$(mktemp -d)
        cp "$JSON_FILE" "${TEMP_ZIP_DIR}/project.json"
        for f in "$ASSETS_DIR"/*; do
            [[ -f "$f" ]] && cp "$f" "$TEMP_ZIP_DIR/"
        done
        OUTPUT_ZIP="$(pwd)/${ZIP_FILENAME}"
        if (cd "$TEMP_ZIP_DIR" && zip -r "$OUTPUT_ZIP" .); then
            ZIP_SIZE=$(du -sh "$OUTPUT_ZIP" | cut -f1)
            write_green "✓ SB3 created: $OUTPUT_ZIP ($ZIP_SIZE)"
        else
            write_red "✗ Failed to create sb3 file"
        fi
        rm -rf "$TEMP_ZIP_DIR"
    fi

elif echo "$PAGE_HTML" | grep -q 'assets/project\.json'; then
    # Type B: project downloaded at runtime
    write_blue "\n→ Detected downloadable project (project.json + assets)."

    asset_base_fn="site_${SITE_ID,,}_asset_base"
    ASSETS_BASE_URL=$("$asset_base_fn" "$PROJECT_ID")
    PROJECT_JSON_URL="${ASSETS_BASE_URL}/project.json"

    write_blue "  Assets URL : $ASSETS_BASE_URL"

    WORK_DIR="$(pwd)/${SITE_ID,,}_project_${PROJECT_ID}"
    mkdir -p "$WORK_DIR"

    JSON_FILE="${WORK_DIR}/project.json"
    write_blue "\n→ Downloading project.json..."

    if ! curl -s -f -o "$JSON_FILE" "$PROJECT_JSON_URL"; then
        write_red "✗ Failed to download project.json"
        exit 1
    fi

    validate_file "$JSON_FILE" || exit 1
    write_green "✓ project.json downloaded"

    ASSETS_DIR="${WORK_DIR}/assets"
    mkdir -p "$ASSETS_DIR"

    write_blue "\nDownloading costumes..."
    download_assets "$JSON_FILE" "$ASSETS_BASE_URL" "$ASSETS_DIR" "costumes"

    write_blue "\nDownloading sounds..."
    download_assets "$JSON_FILE" "$ASSETS_BASE_URL" "$ASSETS_DIR" "sounds"

    write_blue "\nDownloading fonts..."
    download_fonts "$JSON_FILE" "$ASSETS_BASE_URL" "$ASSETS_DIR"

    write_green "\n✓ Asset download complete!\n"

    echo -ne "${CYAN}Do you want to create an .sb3 file? (y/n): ${NC}"
    read create_zip

    if [[ "$create_zip" =~ ^[Yy]$ ]]; then
        ZIP_FILENAME=$(prompt_input "Enter sb3 filename" "project_${PROJECT_ID}.sb3")

        if [[ "$ZIP_FILENAME" != *.* ]]; then
            ZIP_FILENAME="${ZIP_FILENAME}.sb3"
            write_blue "No extension provided, using: $ZIP_FILENAME"
        fi

        write_blue "\nCreating sb3 file..."

        TEMP_ZIP_DIR=$(mktemp -d)

        cp "$JSON_FILE" "${TEMP_ZIP_DIR}/project.json"
        for f in "$ASSETS_DIR"/*; do
            [[ -f "$f" ]] && cp "$f" "$TEMP_ZIP_DIR/"
        done

        OUTPUT_ZIP="$(pwd)/${ZIP_FILENAME}"

        if (cd "$TEMP_ZIP_DIR" && zip -r "$OUTPUT_ZIP" .); then
            ZIP_SIZE=$(du -sh "$OUTPUT_ZIP" | cut -f1)
            write_green "✓ SB3 created: $OUTPUT_ZIP ($ZIP_SIZE)"
        else
            write_red "✗ Failed to create sb3 file"
        fi

        rm -rf "$TEMP_ZIP_DIR"
    fi

else
    write_red "✗ Could not determine project type from the page."
    write_yellow "  The page may use an unsupported packaging format."
    exit 1
fi

write_green "\nDone!"