<#
  backfill-game-platforms.ps1 -- seeds game.gamePlatformLinks (platform + store URL + icon).

  Three phases, each independently skippable:

    1. Upload  : pushes scripts/assets/platform-icons/* to
                 s3://$Bucket/media/<guid-no-hyphens>/<filename>.
                 SVGs are uploaded with --content-type image/svg+xml -- without it S3 serves
                 binary/octet-stream and browsers refuse to render the file in an <img> tag.
                 (backfill-media.ps1 never hit this because S3->S3 copies preserve content type.)
    2. Media   : writes uSync/v17/Media/<Node Name>.config for each icon.
                 SVG media uses the umbracoMediaVectorGraphics type, whose umbracoFile is an
                 Umbraco.UploadField -- a bare path string, NOT the ImageCropper JSON that
                 Image media uses. Steam is Image, the other five are SVG.
    3. Content : writes <gamePlatformLinks> into each uSync/v17/Content/Home/Games/*.config,
                 one row per value already in that game's gamePlatforms array.

  Deterministic: media GUIDs are MD5("moofamily-media:media:<Node Name>") with the v4/variant
  bits forced -- the same New-DeterministicGuid as backfill-media.ps1 -- and block keys are
  derived from the game index. Re-running overwrites rather than duplicating.

  Usage:
    pwsh scripts/backfill-game-platforms.ps1 -DryRun        # show everything, change nothing
    pwsh scripts/backfill-game-platforms.ps1 -RasteriseOnly # only generate steam.png
    pwsh scripts/backfill-game-platforms.ps1 -SkipUpload    # repo files only, no AWS needed
    pwsh scripts/backfill-game-platforms.ps1                # full run

  Content is NOT imported on boot (uSync ImportAtStartup=Settings), so after running this you
  must import the Content and Media handlers from the backoffice uSync dashboard.
#>

[CmdletBinding()]
param(
    [string]$Bucket = "cowparadise-cdn-assets-423623846645-us-east-1-an",
    [string]$RepoRoot,
    [string]$SourceDir,
    [switch]$DryRun,
    [switch]$SkipUpload,
    [switch]$RasteriseOnly
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not populated inside the param block, so resolve defaults here.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoRoot)  { $RepoRoot  = (Resolve-Path (Join-Path $scriptDir '..')).Path }
if (-not $SourceDir) { $SourceDir = Join-Path $scriptDir 'assets\platform-icons' }

$uSyncRoot = Join-Path $RepoRoot 'src\MooFamily.Cms.Web\uSync\v17'
$mediaDir  = Join-Path $uSyncRoot 'Media'
$gamesDir  = Join-Path $uSyncRoot 'Content\Home\Games'

if (-not (Test-Path $mediaDir)) { New-Item -ItemType Directory -Path $mediaDir | Out-Null }

# ---------------------------------------------------------------- helpers

# Deterministic GUID from MD5(namespace + name), same namespace string as backfill-media.ps1
# so a given node name always resolves to the same key.
#
# NOTE the one deliberate difference from backfill-media.ps1: it forces the version nibble into
# $bytes[6], but [Guid]::new(byte[]) reads bytes 6-7 as a little-endian Int16, so $bytes[6] is the
# LOW byte of Data3 and the version nibble actually comes from $bytes[7]. The result is a GUID
# with an arbitrary version — and Umbraco's IMediaPathScheme *rejects* v7 media keys:
#
#   "The registered implementation of IMediaPathScheme cannot be used with media keys using
#    version 7 GUIDs due to an increased risk of collisions in the generated file paths."
#
# That is not cosmetic: the media item fails to import and every picker pointing at it comes back
# empty. Two of these six icons hashed to v7. So this forces the nibble into $bytes[7] instead,
# which genuinely produces v4.
#
# backfill-media.ps1 is deliberately left alone — "fixing" it would change all 28 existing media
# keys and break every MediaPicker value already committed to content.
function New-DeterministicGuid([string]$key) {
    $md5   = [System.Security.Cryptography.MD5]::Create()
    $bytes = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes("moofamily-media:$key"))
    $bytes[7] = ($bytes[7] -band 0x0f) -bor 0x40   # version 4
    $bytes[8] = ($bytes[8] -band 0x3f) -bor 0x80   # RFC 4122 variant
    return [Guid]::new($bytes).ToString('D')
}

function Write-Utf8NoBom([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}

# ---------------------------------------------------------------- icon map

$IconMap = @(
    @{ Platform='Steam';           Node='Steam Platform Icon';           File='steam.png';           MediaType='image'; Label='Play on Steam' }
    @{ Platform='Epic Games';      Node='Epic Games Platform Icon';      File='epic-games.svg';      MediaType='svg';   Label='Get it on Epic Games' }
    @{ Platform='Apple App Store'; Node='Apple App Store Platform Icon'; File='apple-app-store.svg'; MediaType='svg';   Label='Download on the App Store' }
    @{ Platform='Google Play';     Node='Google Play Platform Icon';     File='google-play.svg';     MediaType='svg';   Label='Get it on Google Play' }
    @{ Platform='Browser';         Node='Browser Platform Icon';         File='browser.svg';         MediaType='svg';   Label='Play in Browser' }
    @{ Platform='PC';              Node='PC Platform Icon';              File='pc.svg';              MediaType='svg';   Label='Download for PC' }
)

foreach ($icon in $IconMap) {
    $icon.Guid   = New-DeterministicGuid "media:$($icon.Node)"
    $icon.Folder = $icon.Guid.Replace('-', '')
    $icon.Ext    = [IO.Path]::GetExtension($icon.File).TrimStart('.').ToLower()
    $icon.Alias  = if ($icon.MediaType -eq 'svg') { 'umbracoMediaVectorGraphics' } else { 'Image' }
    $icon.Local  = Join-Path $SourceDir $icon.File
}

# ---------------------------------------------------------------- per-game rows
#
# Rows are derived from each game's EXISTING gamePlatforms array so the two stay consistent.
# Only two games have a real store link; everything else points at /market, matching the
# existing decision for unreleased titles (see CONTENT_AUDIT_PUNCHLIST.md).
#
# Known data inconsistencies, deliberately NOT auto-corrected here:
#   - CowRun's gamePlayUrl is a Google Play link but Google Play is not in its gamePlatforms.
#   - Paintball Madness ships on Steam but its gamePlatforms says PC, not Steam.
# Both are in the punchlist for the content team to resolve.

$UrlOverrides = @{
    'CowRun:Browser'      = 'https://cowparadisegames.com/games/cow-run'
    'PaintballMadness:PC' = 'https://store.steampowered.com/app/3393780/Paintball_Madness/'
}
$DefaultUrl = '/market'

# ---------------------------------------------------------------- phase 1a: rasterise Steam

$steamSource = Join-Path $SourceDir 'steam-source.svg'
$steamPng    = Join-Path $SourceDir 'steam.png'

if ((Test-Path $steamPng) -eq $false -or $RasteriseOnly) {
    if (Test-Path $steamSource) {
        Write-Host "Rasterising Steam icon -> steam.png (64x64)" -ForegroundColor Cyan
        $py = @'
import base64, io, re, sys
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
svg = open(src, encoding="utf-8").read()
m = re.search(r'base64,\s*([A-Za-z0-9+/=\s]+)', svg)
if not m:
    sys.exit("no embedded base64 raster found in " + src)
raw = base64.b64decode(re.sub(r"\s+", "", m.group(1)))
img = Image.open(io.BytesIO(raw)).convert("RGBA")
img.thumbnail((64, 64), Image.LANCZOS)
img.save(out, "PNG", optimize=True)
print(f"{out} {img.size[0]}x{img.size[1]}")
'@
        $tmp = Join-Path ([IO.Path]::GetTempPath()) 'rasterise-steam.py'
        Write-Utf8NoBom $tmp $py
        if (-not $DryRun) {
            python $tmp $steamSource $steamPng
            if ($LASTEXITCODE -ne 0) { throw "Steam rasterisation failed" }
        }
    }
    else {
        Write-Warning "steam-source.svg not found in $SourceDir -- steam.png will not be generated."
        Write-Warning "Drop the design export there and re-run with -RasteriseOnly. See README.md."
    }
}

if ($RasteriseOnly) { return }

# ---------------------------------------------------------------- phase 1b: upload

$aws = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

foreach ($icon in $IconMap) {
    $icon.Bytes = 0

    if (-not (Test-Path $icon.Local)) {
        Write-Warning "MISSING asset $($icon.Local) -- media XML will be written with 0 bytes."
        continue
    }

    $icon.Bytes = (Get-Item $icon.Local).Length
    $targetKey  = "media/$($icon.Folder)/$($icon.File)"

    Write-Host "-> $($icon.Node)" -ForegroundColor Cyan
    Write-Host "    local : $($icon.Local) ($($icon.Bytes) bytes)"
    Write-Host "    s3    : $targetKey"

    if ($SkipUpload) { Write-Host "    [skip-upload]" -ForegroundColor Yellow; continue }
    if ($DryRun)     { Write-Host "    [dry-run] would upload" -ForegroundColor Yellow; continue }
    if (-not (Test-Path $aws)) { throw "AWS CLI not found at $aws (use -SkipUpload to write repo files only)" }

    $contentType = if ($icon.MediaType -eq 'svg') { 'image/svg+xml' } else { 'image/png' }
    & $aws s3 cp $icon.Local "s3://$Bucket/$targetKey" --content-type $contentType --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "S3 upload failed for $($icon.File)" }
}

# ---------------------------------------------------------------- phase 2: media XML

$SvgMediaTemplate = @'
<?xml version="1.0" encoding="utf-8"?>
<Media Key="__GUID__" Alias="umbracoMediaVectorGraphics" Level="1">
  <Info>
    <Parent Key="" />
    <Path>/__NAME__</Path>
    <Trashed>False</Trashed>
    <ContentType>umbracoMediaVectorGraphics</ContentType>
    <CreateDate>2026-08-12T00:00:00</CreateDate>
    <NodeName Default="__NAME__" />
    <SortOrder>0</SortOrder>
  </Info>
  <Properties>
    <umbracoFile>
      <Value><![CDATA[__SRC__]]></Value>
    </umbracoFile>
    <umbracoExtension>
      <Value><![CDATA[__EXT__]]></Value>
    </umbracoExtension>
    <umbracoBytes>
      <Value><![CDATA[__BYTES__]]></Value>
    </umbracoBytes>
  </Properties>
</Media>
'@

$ImageMediaTemplate = @'
<?xml version="1.0" encoding="utf-8"?>
<Media Key="__GUID__" Alias="Image" Level="1">
  <Info>
    <Parent Key="" />
    <Path>/__NAME__</Path>
    <Trashed>False</Trashed>
    <ContentType>Image</ContentType>
    <CreateDate>2026-08-12T00:00:00</CreateDate>
    <NodeName Default="__NAME__" />
    <SortOrder>0</SortOrder>
  </Info>
  <Properties>
    <umbracoFile>
      <Value><![CDATA[__SRC__]]></Value>
    </umbracoFile>
    <umbracoExtension>
      <Value><![CDATA[__EXT__]]></Value>
    </umbracoExtension>
    <umbracoBytes>
      <Value><![CDATA[__BYTES__]]></Value>
    </umbracoBytes>
  </Properties>
</Media>
'@

foreach ($icon in $IconMap) {
    $src = "/media/$($icon.Folder)/$($icon.File)"

    if ($icon.MediaType -eq 'svg') {
        # UploadField stores a bare path.
        $xml = $SvgMediaTemplate.Replace('__SRC__', $src)
    }
    else {
        # ImageCropper stores JSON.
        $json = '{"src":"' + $src + '","focalPoint":{"left":0.5,"top":0.5},"crops":[]}'
        $xml = $ImageMediaTemplate.Replace('__SRC__', $json)
    }

    $xml = $xml.Replace('__GUID__', $icon.Guid).Replace('__NAME__', $icon.Node)
    $xml = $xml.Replace('__EXT__', $icon.Ext).Replace('__BYTES__', [string]$icon.Bytes)

    $file = Join-Path $mediaDir (($icon.Node -replace '[^\w\-]', '_') + '.config')
    if ($DryRun) { Write-Host "    [dry-run] media xml -> $(Split-Path $file -Leaf)" -ForegroundColor Yellow }
    else         { Write-Utf8NoBom $file $xml; Write-Host "    media xml : $(Split-Path $file -Leaf)" }
}

# ---------------------------------------------------------------- phase 3: game content

$ElementTypeKey = 'f4a00032-0000-0000-0000-000000000032'
$gameFiles = Get-ChildItem -Path $gamesDir -Filter '*.config' | Sort-Object Name
$index = 0
$summary = @()

foreach ($gameFile in $gameFiles) {
    $index++
    $slot = '{0:d2}' -f $index                 # matches the existing fb0000NN block prefixes
    $stem = [IO.Path]::GetFileNameWithoutExtension($gameFile.Name)
    $text = [IO.File]::ReadAllText($gameFile.FullName)

    # Terminate on ]]> -- stopping at ]] would swallow the JSON array's own closing bracket.
    $match = [regex]::Match($text, '<gamePlatforms>.*?CDATA\[(?<json>.*?)\]\]>', 'Singleline')
    if (-not $match.Success) {
        Write-Warning "SKIP $($gameFile.Name): no gamePlatforms value"
        continue
    }

    $platforms = @()
    try   { $platforms = $match.Groups['json'].Value | ConvertFrom-Json }
    catch { Write-Warning "SKIP $($gameFile.Name): gamePlatforms is not valid JSON"; continue }
    if (-not $platforms -or $platforms.Count -eq 0) {
        Write-Warning "SKIP $($gameFile.Name): gamePlatforms is empty"
        continue
    }

    $contentData = @()
    $layout      = @()
    $expose      = @()
    $row         = 0

    foreach ($platform in $platforms) {
        $row++
        $rowSlot    = '{0:d2}' -f $row
        $contentKey = "fb0000$slot-0001-0000-0000-0000000000$rowSlot"
        $mediaKey   = "fb0000$slot-0001-0001-0000-0000000000$rowSlot"

        $icon = $IconMap | Where-Object { $_.Platform -eq $platform } | Select-Object -First 1
        if (-not $icon) { Write-Warning "  $stem : no icon mapped for platform '$platform'" }

        $url = $UrlOverrides["${stem}:${platform}"]
        if (-not $url) { $url = $DefaultUrl }

        $label = if ($icon) { $icon.Label } else { $platform }

        # platformIcon is a JSON string containing JSON, so the inner quotes are escaped once.
        $iconValue = ''
        if ($icon) {
            $iconValue = '[{\"key\":\"' + $mediaKey + '\",\"mediaKey\":\"' + $icon.Guid +
                         '\",\"mediaTypeAlias\":\"' + $icon.Alias + '\",\"crops\":[],\"focalPoint\":null}]'
        }

        $values = @(
            '{"culture":null,"editorAlias":"Umbraco.DropDown.Flexible","alias":"platformName","value":"[\"' + $platform + '\"]","segment":null}'
            '{"culture":null,"editorAlias":"Umbraco.TextBox","alias":"platformLabel","value":"' + $label + '","segment":null}'
            '{"culture":null,"editorAlias":"Umbraco.TextBox","alias":"platformUrl","value":"' + $url + '","segment":null}'
            '{"culture":null,"editorAlias":"Umbraco.MediaPicker3","alias":"platformIcon","value":"' + $iconValue + '","segment":null}'
        ) -join ','

        $contentData += '{"contentTypeKey":"' + $ElementTypeKey + '","key":"' + $contentKey + '","values":[' + $values + ']}'
        $layout      += '{"contentKey":"' + $contentKey + '"}'
        $expose      += '{"culture":null,"contentKey":"' + $contentKey + '","segment":null}'

        $summary += [pscustomobject]@{ Game = $stem; Platform = $platform; Url = $url; Icon = if ($icon) { $icon.File } else { '(none)' } }
    }

    $blockJson = '{"contentData":[' + ($contentData -join ',') + '],"settingsData":[],"layout":{"Umbraco.BlockList":[' +
                 ($layout -join ',') + ']},"expose":[' + ($expose -join ',') + ']}'

    $block = "    <gamePlatformLinks>`r`n      <Value><![CDATA[$blockJson]]></Value>`r`n    </gamePlatformLinks>`r`n"

    # Replace when the tag already exists (re-run), otherwise insert before </Properties>.
    $openTag  = '<gamePlatformLinks>'
    $closeTag = '</gamePlatformLinks>'
    $start    = $text.IndexOf($openTag)

    if ($start -ge 0) {
        $end = $text.IndexOf($closeTag, $start)
        if ($end -lt 0) { Write-Warning "SKIP $($gameFile.Name): unbalanced <gamePlatformLinks>"; continue }
        # Rewind to the start of the indentation so we do not accumulate whitespace.
        $lineStart = $text.LastIndexOf("`n", $start) + 1
        $patched   = $text.Substring(0, $lineStart) + $block + $text.Substring($end + $closeTag.Length).TrimStart("`r", "`n")
    }
    else {
        $anchor = $text.LastIndexOf('</Properties>')
        if ($anchor -lt 0) { Write-Warning "SKIP $($gameFile.Name): no </Properties>"; continue }
        $lineStart = $text.LastIndexOf("`n", $anchor) + 1
        $patched   = $text.Substring(0, $lineStart) + $block + $text.Substring($lineStart)
    }

    if ($DryRun) { Write-Host "  [dry-run] $($gameFile.Name): $($platforms.Count) row(s)" -ForegroundColor Yellow }
    else         { Write-Utf8NoBom $gameFile.FullName $patched; Write-Host "  $($gameFile.Name): $($platforms.Count) row(s)" -ForegroundColor Green }
}

# ---------------------------------------------------------------- summary

Write-Host ""
Write-Host "==== Platform links ($($summary.Count) rows across $($gameFiles.Count) games) ====" -ForegroundColor Green
$summary | Format-Table Game, Platform, Url, Icon -AutoSize | Out-String -Width 200 | Write-Host

$unused = $IconMap | Where-Object { $p = $_.Platform; -not ($summary | Where-Object { $_.Platform -eq $p }) }
if ($unused) {
    Write-Host "Icons with no game row (created but currently unreferenced):" -ForegroundColor Yellow
    $unused | ForEach-Object { Write-Host "  - $($_.Platform)" -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "Next: dotnet build, dotnet run, then Settings > uSync > Import (Content + Media handlers)." -ForegroundColor Green
Write-Host "Content does NOT import on boot -- uSync ImportAtStartup is set to Settings." -ForegroundColor Green
