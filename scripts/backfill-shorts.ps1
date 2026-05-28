<#
  backfill-shorts.ps1 -- generates 21 Short content nodes (one per YouTube video ID
  observed in the live cowparadisegames.com bundle).
#>
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path)

$ErrorActionPreference = 'Stop'
$shortsDir = Join-Path $RepoRoot 'src\MooFamily.Cms.Web\uSync\v17\Content\Home\Shorts'
if (-not (Test-Path $shortsDir)) { New-Item -ItemType Directory -Path $shortsDir | Out-Null }

function New-DGuid([string]$key) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes("moofamily-short:$key"))
    $bytes[6] = ($bytes[6] -band 0x0f) -bor 0x40
    $bytes[8] = ($bytes[8] -band 0x3f) -bor 0x80
    return [Guid]::new($bytes).ToString('D')
}

# 21 YouTube video IDs extracted from the live bundle
$videoIds = @(
    'GmmCJCuhXVY','MRr53jCZJao','MYl5Sihfi2Y','QyAQ293-8zk','VJ2yel1dsR8',
    'WC0SFtTKsic','WNcScFUqoE0','_R0c9ANHA6Y','clrJzbMww8A','dwfgWy7OrTo',
    'f8qPIUjkhAs','fMLO7IQ4pEo','gqmTuG2SR7w','lk8ASXS-Ic4','op3qTKf1J4U',
    'p7kd-dIerWk','pMgbrxNSOac','r8CfSREXCYk','s5SzQJWYYT8','xiZdAnjGxag',
    'yVMOiyrTjlk'
)

$template = @'
<?xml version="1.0" encoding="utf-8"?>
<Content Key="__KEY__" Alias="short" Level="3">
  <Info>
    <Parent Key="f1a00015-0000-0000-0000-000000000015">Shorts</Parent>
    <Path>/Home/Shorts/__NAME__</Path>
    <Trashed Locked="False">False</Trashed>
    <ContentType>short</ContentType>
    <CreateDate>2026-05-28T20:00:00</CreateDate>
    <NodeName Default="__NAME__" />
    <SortOrder>__SORT__</SortOrder>
    <Published Default="true" />
    <Schedule />
    <Template Key="00000000-0000-0000-0000-000000000000" />
  </Info>
  <Properties>
    <shortTitle>
      <Value><![CDATA[__TITLE__]]></Value>
    </shortTitle>
    <shortYoutubeId>
      <Value><![CDATA[__YT__]]></Value>
    </shortYoutubeId>
    <shortDescription>
      <Value><![CDATA[__DESC__]]></Value>
    </shortDescription>
    <shortCategory>
      <Value><![CDATA[["Cow Paradise Shorts"]]]></Value>
    </shortCategory>
  </Properties>
</Content>
'@

$sortOrder = 0
foreach ($id in $videoIds) {
    $sortOrder++
    $nodeName = "Short " + ('{0:D2}' -f $sortOrder)
    $guid     = New-DGuid "short:$id"
    $fileName = "Short" + ('{0:D2}' -f $sortOrder) + ".config"
    $xml = $template
    $xml = $xml.Replace('__KEY__', $guid)
    $xml = $xml.Replace('__NAME__', $nodeName)
    $xml = $xml.Replace('__SORT__', [string]$sortOrder)
    $xml = $xml.Replace('__TITLE__', $nodeName)
    $xml = $xml.Replace('__YT__', $id)
    $xml = $xml.Replace('__DESC__', "Cow Paradise short clip $sortOrder. Replace this title and description from the backoffice.")

    $path = Join-Path $shortsDir $fileName
    [IO.File]::WriteAllText($path, $xml, [Text.UTF8Encoding]::new($false))
    Write-Host "$fileName  yt=$id  guid=$guid"
}
Write-Host ""
Write-Host "21 Short content nodes generated under uSync/v17/Content/Home/Shorts/"
