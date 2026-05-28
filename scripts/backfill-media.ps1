<#
  backfill-media.ps1 -- one-shot media backfill for MooFamily Umbraco CMS.

  What it does, for each mapped entry below:
    1. Copies the existing S3 source asset to s3://$bucket/media/<guid-no-hyphens>/<filename>
       (Umbraco-style media path so the AF.Umbraco.S3.Media.Storage provider can resolve it).
    2. Writes a uSync Media XML at uSync/v17/Media/<NodeName>.config (Image media type).
    3. Patches the corresponding uSync Content XML's MediaPicker3 property value.

  After running:
    - Stop the running dev server (PID 42840) if still up.
    - dotnet build src/MooFamily.Cms.Web
    - dotnet run --project src/MooFamily.Cms.Web
    - uSync auto-imports the new Media + patched Content on first boot.

  Idempotent: safe to re-run; existing S3 keys are overwritten, existing Media XML files
  are rewritten, existing content XML values are replaced.
#>

[CmdletBinding()]
param(
    [string]$Bucket = "cowparadise-cdn-assets-423623846645-us-east-1-an",
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$aws = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
if (-not (Test-Path $aws)) { throw "AWS CLI not found at $aws" }

$uSyncRoot   = Join-Path $RepoRoot 'src\MooFamily.Cms.Web\uSync\v17'
$mediaDir    = Join-Path $uSyncRoot 'Media'
$contentRoot = Join-Path $uSyncRoot 'Content\Home'

if (-not (Test-Path $mediaDir)) { New-Item -ItemType Directory -Path $mediaDir | Out-Null }

# uSync Media XML template (here-string closing must be at column 1)
$global:MediaXmlTemplate = @'
<?xml version="1.0" encoding="utf-8"?>
<Media Key="__MEDIA_GUID__" Alias="Image" Level="1">
  <Info>
    <Parent Key="" />
    <Path>/__NAME__</Path>
    <Trashed>False</Trashed>
    <ContentType>Image</ContentType>
    <CreateDate>2026-05-27T00:00:00</CreateDate>
    <NodeName Default="__NAME__" />
    <SortOrder>0</SortOrder>
  </Info>
  <Properties>
    <umbracoFile>
      <Value><![CDATA[__FILEJSON__]]></Value>
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

# Deterministic GUID v5-style from MD5(namespace + name). Stable across reruns.
function New-DeterministicGuid([string]$key) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes("moofamily-media:$key"))
    # Set version=4 nibble and variant bits for a valid-looking GUID
    $bytes[6] = ($bytes[6] -band 0x0f) -bor 0x40
    $bytes[8] = ($bytes[8] -band 0x3f) -bor 0x80
    return [Guid]::new($bytes).ToString('D')
}

# Each row: SourceKey (S3 key under bucket), MediaName (uSync media file name + Umbraco media node name),
#           ContentFile (uSync content XML relative to Content\Home), PickerAlias (property alias on the content XML)
$map = @(
    # ---- Games (9) ----
    @{ SourceKey='images/games/cowrun.webp';     MediaName='Cow Run Cover';     ContentFile='Games\CowRun.config';   PickerAlias='gameCoverImage' }
    @{ SourceKey='images/games/MooClimb.webp';   MediaName='Moo Climb Cover';   ContentFile='Games\MooClimb.config'; PickerAlias='gameCoverImage' }
    @{ SourceKey='images/games/MooCrush.webp';   MediaName='Moo Crush Cover';   ContentFile='Games\MooCrush.config'; PickerAlias='gameCoverImage' }
    @{ SourceKey='images/games/MooDash.webp';    MediaName='Moo Dash Cover';    ContentFile='Games\MooDash.config';  PickerAlias='gameCoverImage' }
    @{ SourceKey='images/games/MooRush.webp';    MediaName='Moo Rash Cover';    ContentFile='Games\MooRash.config';  PickerAlias='gameCoverImage' }  # MooRash node uses MooRush.webp asset
    @{ SourceKey='images/games/MooSkate.webp';   MediaName='Moo Skate Cover';   ContentFile='Games\MooSkate.config'; PickerAlias='gameCoverImage' }
    @{ SourceKey='images/games/Mooski.webp';     MediaName='Moo Ski Cover';     ContentFile='Games\MooSki.config';   PickerAlias='gameCoverImage' }
    @{ SourceKey='images/games/moo_soccer.webp'; MediaName='Moo Soccer Cover';  ContentFile='Games\MooSoccer.config';PickerAlias='gameCoverImage' }
    @{ SourceKey='images/games/MooTag.webp';     MediaName='Moo Tag Cover';     ContentFile='Games\MooTag.config';   PickerAlias='gameCoverImage' }
    @{ SourceKey='images/games/FlyingMoo.webp';  MediaName='Flying Moo Cover';  ContentFile='Games\FlyingMoo.config'; PickerAlias='gameCoverImage' }
    @{ SourceKey='images/games/moochess.webp';   MediaName='Moo Chess Cover';   ContentFile='Games\MooChess.config'; PickerAlias='gameCoverImage' }
    @{ SourceKey='images/games/PaintBall_02.webp'; MediaName='Paintball Madness Cover'; ContentFile='Games\PaintballMadness.config'; PickerAlias='gameCoverImage' }

    # ---- Team (5) ----
    # Jean & Thierry are both art directors; alphabetical-first-name: Jean=art-director-1, Thierry=art-director-2
    @{ SourceKey='images/ceo.png';            MediaName='John Paul Morris';      ContentFile='Team\JohnPaulMorris.config';    PickerAlias='memberPhoto' }
    @{ SourceKey='images/cto.png';            MediaName='Joseph Pascal';         ContentFile='Team\JosephPascal.config';      PickerAlias='memberPhoto' }
    @{ SourceKey='images/3d-artist.png';      MediaName='Robin Haefeil';         ContentFile='Team\RobinHaefeil.config';      PickerAlias='memberPhoto' }
    @{ SourceKey='images/art-director-1.png'; MediaName='Jean Antoine Hierro';   ContentFile='Team\JeanAntoineHierro.config'; PickerAlias='memberPhoto' }
    @{ SourceKey='images/art-director-2.png'; MediaName='Thierry Clauson';       ContentFile='Team\ThierryClauson.config';    PickerAlias='memberPhoto' }

    # ---- News (6) ---- mapped in alphabetical order by node name
    @{ SourceKey='images/news-gallery-1.png'; MediaName='Learning With Little Jack Hero';        ContentFile='News\LearningWithLittleJack.config';        PickerAlias='newsHeroImage' }
    @{ SourceKey='images/news-gallery-2.png'; MediaName='Multiplayer Experiences Hero';          ContentFile='News\MultiplayerExperiences.config';        PickerAlias='newsHeroImage' }
    @{ SourceKey='images/news-gallery-3.png'; MediaName='New Adventures Hero';                   ContentFile='News\NewAdventures.config';                 PickerAlias='newsHeroImage' }
    @{ SourceKey='images/news-gallery-4.png'; MediaName='Play In Competitive Tournaments Hero';  ContentFile='News\PlayInCompetitiveTournaments.config';  PickerAlias='newsHeroImage' }
    @{ SourceKey='images/news-gallery-5.png'; MediaName='Stories That Teach Hero';               ContentFile='News\StoriesThatTeach.config';              PickerAlias='newsHeroImage' }
    @{ SourceKey='images/news-gallery-6.png'; MediaName='Universe Where Kids Learn Hero';        ContentFile='News\UniverseWhereKidsLearn.config';        PickerAlias='newsHeroImage' }

    # ---- Characters (3 of 6) ---- alphabetical: Ellie, Little Jack, Lulu get the available images.
    # Milo, Moo, Tina have no source image yet -- author them later via backoffice.
    @{ SourceKey='images/character_1.png'; MediaName='Ellie';       ContentFile='Characters\Ellie.config';      PickerAlias='characterImage' }
    @{ SourceKey='images/character_2.png'; MediaName='Little Jack'; ContentFile='Characters\LittleJack.config'; PickerAlias='characterImage' }
    @{ SourceKey='images/character_3.png'; MediaName='Lulu';        ContentFile='Characters\Lulu.config';       PickerAlias='characterImage' }
)

function Get-S3Metadata([string]$bucket, [string]$key) {
    $json = & $aws s3api head-object --bucket $bucket --key $key --output json 2>$null
    if ($LASTEXITCODE -ne 0) { throw "head-object failed for s3://$bucket/$key" }
    return $json | ConvertFrom-Json
}

$summary = @()

foreach ($row in $map) {
    $src      = $row.SourceKey
    $name     = $row.MediaName
    $contentP = Join-Path $contentRoot $row.ContentFile
    $alias    = $row.PickerAlias

    if (-not (Test-Path $contentP)) {
        Write-Warning "SKIP: content file missing -- $contentP"
        continue
    }

    $filename = [IO.Path]::GetFileName($src)
    $ext      = [IO.Path]::GetExtension($filename).TrimStart('.').ToLower()

    $mediaGuid = New-DeterministicGuid "media:$name"
    $entryGuid = New-DeterministicGuid "picker:$($row.ContentFile):$alias"
    $folder    = $mediaGuid.Replace('-','')

    $targetKey = "media/$folder/$filename"
    $srcArn    = "s3://$Bucket/$src"
    $tgtArn    = "s3://$Bucket/$targetKey"

    Write-Host "-> $name" -ForegroundColor Cyan
    Write-Host "    src   : $src"
    Write-Host "    media : $targetKey"
    Write-Host "    guid  : $mediaGuid"

    # --- 1. Copy S3 source -> media/<guid>/<filename> ---
    if ($DryRun) {
        Write-Host "    [dry-run] would copy" -ForegroundColor Yellow
        $bytes = 0
    } else {
        & $aws s3 cp $srcArn $tgtArn --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw "S3 copy failed for $src" }
        $meta = Get-S3Metadata $Bucket $targetKey
        $bytes = [int64]$meta.ContentLength
    }

    # --- 2. Write uSync Media XML ---
    $umbracoFileJson = '{"src":"/media/' + $folder + '/' + $filename + '","focalPoint":{"left":0.5,"top":0.5},"crops":[]}'
    $mediaXml = $global:MediaXmlTemplate
    $mediaXml = $mediaXml.Replace('__MEDIA_GUID__', $mediaGuid)
    $mediaXml = $mediaXml.Replace('__NAME__', $name)
    $mediaXml = $mediaXml.Replace('__FILEJSON__', $umbracoFileJson)
    $mediaXml = $mediaXml.Replace('__EXT__', $ext)
    $mediaXml = $mediaXml.Replace('__BYTES__', [string]$bytes)
    $safeName  = $name -replace '[^\w\-]','_'
    $mediaFile = (Join-Path $mediaDir $safeName) + '.config'
    if (-not $DryRun) {
        [IO.File]::WriteAllText($mediaFile, $mediaXml, [Text.UTF8Encoding]::new($false))
    }
    Write-Host "    media xml : $(Split-Path $mediaFile -Leaf)"

    # --- 3. Patch the Content XML's MediaPicker3 value ---
    $pickerValue = '[{"key":"' + $entryGuid + '","mediaKey":"' + $mediaGuid + '","mediaTypeAlias":"Image","crops":[],"focalPoint":null}]'
    $content = [IO.File]::ReadAllText($contentP)
    $openTag  = '<'  + $alias + '>'
    $closeTag = '</' + $alias + '>'
    $startIdx = $content.IndexOf($openTag)
    $endIdx   = -1
    if ($startIdx -ge 0) { $endIdx = $content.IndexOf($closeTag, $startIdx) }
    if ($startIdx -ge 0 -and $endIdx -gt 0) {
        $newBlock = $openTag + "`r`n      <Value><" + '![CDATA[' + $pickerValue + ']]' + "></Value>`r`n    " + $closeTag
        $patched  = $content.Substring(0, $startIdx) + $newBlock + $content.Substring($endIdx + $closeTag.Length)
        if (-not $DryRun) {
            [IO.File]::WriteAllText($contentP, $patched, [Text.UTF8Encoding]::new($false))
        }
        Write-Host "    content   : patched $alias"
    } else {
        Write-Warning "    content   : tag <$alias> not found in $contentP"
    }

    $summary += [pscustomobject]@{
        Name      = $name
        Source    = $src
        Target    = $targetKey
        MediaGuid = $mediaGuid
        Bytes     = $bytes
        Content   = $row.ContentFile
        Alias     = $alias
    }
}

Write-Host ""
Write-Host "==== Backfill summary ($($summary.Count) items) ====" -ForegroundColor Green
$summary | Format-Table Name, Bytes, Target, Content, Alias -AutoSize | Out-String -Width 200 | Write-Host
Write-Host ""
Write-Host "Next: stop dev server (PID 42840), dotnet build, dotnet run. uSync will import on first boot." -ForegroundColor Green
