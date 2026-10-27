param(
    [ValidateSet('olmoe','minicpm1b','minicpm2b')][string]$Model='olmoe',
    [string]$Folder=(Join-Path $PSScriptRoot '../pobrane-modele'),
    [switch]$TylkoPobierz
)
$ErrorActionPreference='Stop'
$taskProfiles=@{
    olmoe=@('olmoe-colibri-int8-0125','OLMoE-Colibri-parts.json','OLMoE-1B-7B-0125-Instruct-Colibri-int8.zip','f0edda8eb956aef77f1820ba6e50bf317c9d233b5e83f9a3a83dfffbd6da24e2')
    minicpm1b=@('minicpm5-gguf-q4-k-m','MiniCPM5-1B-parts.json','MiniCPM5-1B-Q4_K_M.gguf','81b64d05a23b17b34c475f42b3e72fbde62d4b92cc34541f7a8031d0752deafa')
    minicpm2b=@('minicpm5-gguf-q4-k-m','MiniCPM5-2B-parts.json','MiniCPM5-2B-Q4_K_M.gguf','ec2d5801640099e97d8d7e8003ad4d81f336e757811f03a26173dddf386602fd')
}
$taskProfile=$taskProfiles[$Model]
$taskBase='https://github.com/wtiptop/Ai-app-phone/releases/download/'+$taskProfile[0]+'/'
$taskDirectory=[IO.Path]::GetFullPath($Folder)
New-Item -ItemType Directory -Path $taskDirectory -Force | Out-Null
$taskCurl=(Get-Command curl.exe -ErrorAction Stop).Source
function DownloadPart([string]$Name,[string]$ExpectedSha,[long]$ExpectedBytes=0) {
    if($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,180}$'){throw 'Niedozwolona nazwa pliku'}
    $taskFile=Join-Path $script:taskDirectory $Name
    if(Test-Path -LiteralPath $taskFile){
        if($ExpectedSha -and (Get-FileHash -LiteralPath $taskFile -Algorithm SHA256).Hash.ToLowerInvariant() -eq $ExpectedSha -and (!$ExpectedBytes -or (Get-Item -LiteralPath $taskFile).Length -eq $ExpectedBytes)) { return $taskFile }
        throw "Plik już istnieje; nie nadpisuję: $Name"
    }
    $taskPartial=$taskFile+'.partial'
    & $script:taskCurl --fail --location --continue-at - --retry 3 --connect-timeout 30 --max-time 9000 --output $taskPartial ($script:taskBase+$Name)
    if($LASTEXITCODE -ne 0){throw "Nie ukończono pobierania: $Name. Zachowano .partial do wznowienia."}
    if($ExpectedBytes -and (Get-Item -LiteralPath $taskPartial).Length -ne $ExpectedBytes){throw "Zły rozmiar: $Name"}
    if($ExpectedSha -and (Get-FileHash -LiteralPath $taskPartial -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedSha){throw "Niezgodny SHA-256: $Name"}
    [IO.File]::Move($taskPartial,$taskFile)
    return $taskFile
}
# Manifest jest danymi. Oczekiwany końcowy hash jest przypięty powyżej.
$taskManifestPath=Join-Path $taskDirectory $taskProfile[1]
if(!(Test-Path -LiteralPath $taskManifestPath)) { $taskManifestPath=DownloadPart $taskProfile[1] '' }
$taskManifest=Get-Content -LiteralPath $taskManifestPath -Raw | ConvertFrom-Json
if($taskManifest.schemaVersion -ne 1 -or $taskManifest.file -ne $taskProfile[2] -or $taskManifest.sha256 -ne $taskProfile[3] -or @($taskManifest.parts).Count -lt 1 -or @($taskManifest.parts).Count -gt 128){throw 'Nieprawidłowy manifest wybranego modelu'}
$taskNames=@{}
foreach($taskPart in $taskManifest.parts){
    if($taskPart.file -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,180}$' -or $taskPart.sha256 -notmatch '^[a-f0-9]{64}$' -or $taskPart.bytes -le 0 -or $taskNames.ContainsKey($taskPart.file)){throw 'Nieprawidłowa część manifestu'}
    $taskNames[$taskPart.file]=$true
}
$taskTotal=0
foreach($taskPart in $taskManifest.parts){
    $taskTotal++
    Write-Host "Część $taskTotal z $(@($taskManifest.parts).Count): $($taskPart.file)"
    DownloadPart $taskPart.file $taskPart.sha256 $taskPart.bytes | Out-Null
}
Write-Host 'Wszystkie części pobrane i sprawdzone SHA-256.'
if(!$TylkoPobierz){
    $taskJoin=Join-Path $taskDirectory 'join_release_parts.py'
    if(!(Test-Path -LiteralPath $taskJoin)){ $taskJoin=DownloadPart 'join_release_parts.py' 'ede517ee17d37b507a2972f1c647ca086ff39452e41d2dd9859b09a88b746e16' }
    if((Get-FileHash -LiteralPath $taskJoin -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'ede517ee17d37b507a2972f1c647ca086ff39452e41d2dd9859b09a88b746e16'){throw 'Niezgodny program składania'}
    & python $taskJoin $taskManifestPath
    if($LASTEXITCODE -ne 0){throw 'Nie ukończono składania modelu'}
}
