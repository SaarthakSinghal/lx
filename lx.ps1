$script:LxScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
elseif (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    Split-Path -Parent $PSCommandPath
}
else {
    (Get-Location).Path
}

$script:LxDirectorySizeScannerMaxDegreeOfParallelism = if ([Environment]::ProcessorCount -gt 1) {
    [Math]::Min(6, [Environment]::ProcessorCount)
}
else {
    1
}

function Resolve-LxOptions {
    [CmdletBinding()]
    param(
        [switch]$r,
        [switch]$s,
        [switch]$a,
        [switch]$rs,
        [switch]$rsa,
        [switch]$ra,

        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$RemainingArgs
    )

    $showAll = $false
    $recurseSize = $false
    $sortBySize = $false
    $sortAscending = $false
    $sortMode = $null
    $treeEnabled = $false
    $treeMode = $null
    $linksEnabled = $false
    $linksMode = $null
    $clearCache = $false
    $showCacheInfo = $false
    $targetPaths = [System.Collections.Generic.List[object]]::new()

    foreach ($arg in $RemainingArgs) {
        if ($arg -is [string] -and $arg -like '--sort=*') {
            $value = $arg.Substring(7).ToLowerInvariant()

            switch ($value) {
                'asc'  { $sortMode = 'asc' }
                'desc' { $sortMode = 'desc' }
                default {
                    Write-Error "Invalid value for --sort. Use --sort=asc or --sort=desc."
                    return $null
                }
            }
        }
        elseif ($arg -is [string] -and $arg -eq '--tree') {
            $treeMode = $true
        }
        elseif ($arg -is [string] -and $arg -eq '--links') {
            $linksMode = $true
        }
        elseif ($arg -is [string] -and $arg -eq '--clear-cache') {
            $clearCache = $true
        }
        elseif ($arg -is [string] -and $arg -eq '--cache-size') {
            $showCacheInfo = $true
        }
        elseif ($arg -is [string] -and $arg -like '--tree=*') {
            $value = $arg.Substring(7).ToLowerInvariant()

            switch ($value) {
                'true'  { $treeMode = $true }
                'false' { $treeMode = $false }
                default {
                    Write-Error "Invalid value for --tree. Use --tree, --tree=true, or --tree=false."
                    return $null
                }
            }
        }
        elseif ($arg -is [string] -and $arg -like '--links=*') {
            $value = $arg.Substring(8).ToLowerInvariant()

            switch ($value) {
                'true'  { $linksMode = $true }
                'false' { $linksMode = $false }
                default {
                    Write-Error "Invalid value for --links. Use --links, --links=true, or --links=false."
                    return $null
                }
            }
        }
        else {
            $null = $targetPaths.Add($arg)
        }
    }

    if ($r)   { $recurseSize = $true }
    if ($s)   { $sortBySize = $true }
    if ($a)   { $showAll = $true }

    if ($rs)  { $recurseSize = $true; $sortBySize = $true }
    if ($rsa) { $recurseSize = $true; $sortBySize = $true; $showAll = $true }
    if ($ra)  { $recurseSize = $true; $showAll = $true }

    if ($sortMode) {
        $sortBySize = $true
        $sortAscending = ($sortMode -eq 'asc')
    }

    if ($null -ne $treeMode) {
        $treeEnabled = $treeMode
    }

    if ($null -ne $linksMode) {
        $linksEnabled = $linksMode
    }

    [PSCustomObject]@{
        ShowAll       = $showAll
        RecurseSize   = $recurseSize
        SortBySize    = $sortBySize
        SortAscending = $sortAscending
        TreeEnabled   = $treeEnabled
        LinksEnabled  = $linksEnabled
        ClearCache    = $clearCache
        ShowCacheInfo = $showCacheInfo
        # Keep TreeDepth in the options shape so future --tree-depth work does not
        # need to restructure the renderer contract again.
        TreeDepth     = 1
        TargetPaths   = @($targetPaths)
    }
}

function Get-LxTopLevelItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Options
    )

    $requestedTargets = if ($Options.TargetPaths.Count -gt 0) {
        @($Options.TargetPaths)
    }
    else {
        @((Resolve-Path -LiteralPath '.').ProviderPath)
    }

    $groupMap = @{}
    $groupOrder = [System.Collections.Generic.List[object]]::new()

    foreach ($target in $requestedTargets) {
        $resolvedPaths = @(Resolve-Path -Path $target -ErrorAction Stop | ForEach-Object { $_.ProviderPath })

        foreach ($resolvedPath in $resolvedPaths) {
            $item = Get-Item -LiteralPath $resolvedPath -ErrorAction Stop

            if ($item.PSIsContainer) {
                $displayPath = $item.FullName
                $resolvedDisplayPath = $item.FullName
                $items = @(Get-ChildItem -LiteralPath $item.FullName -Force:$Options.ShowAll)
            }
            else {
                $displayPath = $item.DirectoryName
                $resolvedDisplayPath = $item.DirectoryName
                $items = @($item)
            }

            if (-not $groupMap.ContainsKey($resolvedDisplayPath)) {
                $group = [PSCustomObject]@{
                    DisplayPath  = $displayPath
                    ResolvedPath = $resolvedDisplayPath
                    Items        = [System.Collections.Generic.List[object]]::new()
                    ItemPaths    = [System.Collections.Generic.HashSet[string]]::new()
                }

                $groupMap[$resolvedDisplayPath] = $group
                $null = $groupOrder.Add($group)
            }

            foreach ($childItem in $items) {
                $childPath = $childItem.FullName
                if ($groupMap[$resolvedDisplayPath].ItemPaths.Add($childPath)) {
                    $null = $groupMap[$resolvedDisplayPath].Items.Add($childItem)
                }
            }
        }
    }

    @($groupOrder | ForEach-Object {
        [PSCustomObject]@{
            DisplayPath  = $_.DisplayPath
            ResolvedPath = $_.ResolvedPath
            Items        = @($_.Items)
        }
    })
}

function Get-LxModeText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.IO.FileSystemInfo]$Item
    )

    process {
        [string]$Item.Mode
    }
}

function Get-LxLastWriteTimeText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.IO.FileSystemInfo]$Item
    )

    process {
        $Item.LastWriteTime.ToString('dd-MM-yyyy  HH:mm')
    }
}

function Format-LxHumanSize {
    [CmdletBinding()]
    param(
        [long]$Bytes
    )

    $numberText = [string]$Bytes
    $unitText = ' B'

    if ($Bytes -ge 1GB) {
        $numberText = '{0:N2}' -f ($Bytes / 1GB)
        $unitText = 'GB'
    }
    elseif ($Bytes -ge 1MB) {
        $numberText = '{0:N2}' -f ($Bytes / 1MB)
        $unitText = 'MB'
    }
    elseif ($Bytes -ge 1KB) {
        $numberText = '{0:N2}' -f ($Bytes / 1KB)
        $unitText = 'KB'
    }

    "$numberText $unitText"
}

function Get-LxSizeCacheTtl {
    [CmdletBinding()]
    param()

    [TimeSpan]::FromMinutes(5)
}

function Get-LxPersistentSizeCachePath {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($script:LxScriptRoot)) {
        return $null
    }

    Join-Path -Path $script:LxScriptRoot -ChildPath '.lx-size-cache.json'
}

function Prune-LxPersistentSizeCache {
    [CmdletBinding()]
    param(
        [hashtable]$Cache
    )

    if (-not $Cache) {
        return @{}
    }

    $maxAgeTicks = (Get-LxSizeCacheTtl).Ticks
    $nowTicks = [DateTime]::UtcNow.Ticks
    $prunedEntries = @{}

    foreach ($pathKey in $Cache.Keys) {
        $entry = $Cache[$pathKey]
        if ($entry -isnot [hashtable]) {
            continue
        }

        $cachedAtUtcTicks = [long]$entry['CachedAtUtcTicks']
        $entryAgeTicks = $nowTicks - $cachedAtUtcTicks

        if ($entryAgeTicks -lt 0 -or $entryAgeTicks -gt $maxAgeTicks) {
            continue
        }

        $prunedEntries[$pathKey] = @{
            Size                  = [long]$entry['Size']
            CachedAtUtcTicks      = $cachedAtUtcTicks
            LastWriteTimeUtcTicks = [long]$entry['LastWriteTimeUtcTicks']
        }
    }

    $prunedEntries
}

function Load-LxPersistentSizeCache {
    [CmdletBinding()]
    param()

    $cachePath = Get-LxPersistentSizeCachePath
    if ([string]::IsNullOrWhiteSpace($cachePath) -or -not (Test-Path -LiteralPath $cachePath)) {
        return @{}
    }

    try {
        $rawJson = Get-Content -LiteralPath $cachePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($rawJson)) {
            return @{}
        }

        $cacheDocument = $rawJson | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        $entries = if ($cacheDocument.ContainsKey('Entries') -and $cacheDocument['Entries'] -is [hashtable]) {
            $cacheDocument['Entries']
        }
        else {
            @{}
        }

        $normalizedEntries = @{}
        foreach ($pathKey in $entries.Keys) {
            $entry = $entries[$pathKey]
            if ($entry -isnot [hashtable]) {
                continue
            }

            $normalizedEntries[$pathKey] = @{
                Size                  = [long]$entry['Size']
                CachedAtUtcTicks      = [long]$entry['CachedAtUtcTicks']
                LastWriteTimeUtcTicks = [long]$entry['LastWriteTimeUtcTicks']
            }
        }

        return (Prune-LxPersistentSizeCache -Cache $normalizedEntries)
    }
    catch {
        return @{}
    }
}

function Save-LxPersistentSizeCache {
    [CmdletBinding()]
    param(
        [hashtable]$Cache
    )

    if (-not $Cache) {
        return
    }

    $cachePath = Get-LxPersistentSizeCachePath
    if ([string]::IsNullOrWhiteSpace($cachePath)) {
        return
    }

    $entriesToPersist = Prune-LxPersistentSizeCache -Cache $Cache

    if ($entriesToPersist.Count -eq 0) {
        try {
            if (Test-Path -LiteralPath $cachePath) {
                Remove-Item -LiteralPath $cachePath -Force -ErrorAction Stop
            }
        }
        catch {
        }

        return
    }

    $cacheDocument = @{
        Version = 1
        Entries = $entriesToPersist
    }

    try {
        $cacheDocument |
            ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $cachePath -Encoding UTF8 -ErrorAction Stop

        $cacheItem = Get-Item -LiteralPath $cachePath -ErrorAction Stop
        if (($cacheItem.Attributes -band [System.IO.FileAttributes]::Hidden) -eq 0) {
            $cacheItem.Attributes = ($cacheItem.Attributes -bor [System.IO.FileAttributes]::Hidden)
        }
    }
    catch {
    }
}

function Clear-LxPersistentSizeCache {
    [CmdletBinding()]
    param()

    $cachePath = Get-LxPersistentSizeCachePath
    $cleared = $false

    if (-not [string]::IsNullOrWhiteSpace($cachePath) -and (Test-Path -LiteralPath $cachePath)) {
        try {
            Remove-Item -LiteralPath $cachePath -Force -ErrorAction Stop
            $cleared = $true
        }
        catch {
        }
    }

    [PSCustomObject]@{
        Path    = $cachePath
        Cleared = $cleared
    }
}

function Get-LxPersistentSizeCacheInfo {
    [CmdletBinding()]
    param()

    $cachePath = Get-LxPersistentSizeCachePath
    $cacheItem = if (-not [string]::IsNullOrWhiteSpace($cachePath) -and (Test-Path -LiteralPath $cachePath)) {
        Get-Item -LiteralPath $cachePath -Force -ErrorAction SilentlyContinue
    }
    else {
        $null
    }

    [PSCustomObject]@{
        Path              = $cachePath
        LastWriteTimeText = if ($cacheItem) { $cacheItem.LastWriteTime.ToString('dd-MM-yyyy    HH:mm') } else { '-' }
        CacheSizeText     = if ($cacheItem) { Format-LxHumanSize -Bytes ([long]$cacheItem.Length) } else { Format-LxHumanSize -Bytes 0 }
    }
}

function Write-LxCacheInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CacheInfo
    )

    $rows = @(
        [PSCustomObject]@{ Label = 'Path';          Underline = '----';          Value = $CacheInfo.Path }
        [PSCustomObject]@{ Label = 'LastWriteTime'; Underline = '-------------'; Value = $CacheInfo.LastWriteTimeText }
        [PSCustomObject]@{ Label = 'CacheSize';     Underline = '---------';     Value = $CacheInfo.CacheSizeText }
    )

    $labelWidth = (($rows | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum)
    if ($null -eq $labelWidth) {
        $labelWidth = 0
    }

    $labelWidth = [Math]::Max(18, [int]$labelWidth + 2)
    $leftPadding = ' ' * 2
    $columnGap = ' ' * 4

    Write-Host ''

    for ($index = 0; $index -lt $rows.Count; $index++) {
        $row = $rows[$index]

        Write-Host -NoNewline $leftPadding
        Write-Host -NoNewline $row.Label.PadRight($labelWidth) -ForegroundColor Green
        Write-Host -NoNewline $columnGap
        Write-Host $row.Value

        Write-Host -NoNewline $leftPadding
        Write-Host $row.Underline.PadRight($labelWidth) -ForegroundColor Green

        if ($index -lt ($rows.Count - 1)) {
            Write-Host ''
        }
    }

    Write-Host ''
}

function Initialize-LxDirectorySizeScanner {
    [CmdletBinding()]
    param()

    if ('Lx.DirectorySizeScanner' -as [type]) {
        return
    }

    $typeDefinition = @'
using System;
using System.IO;
using System.IO.Enumeration;
using System.Threading.Tasks;

namespace Lx
{
    public sealed class DirectorySizeResult
    {
        public string Path { get; set; }
        public long Size { get; set; }
        public bool HadError { get; set; }
    }

    internal sealed class DirectorySizeEnumerator : FileSystemEnumerator<long>
    {
        private readonly string _excludedFullPath;
        private readonly string _excludedFileName;

        public DirectorySizeEnumerator(string path, string excludedFullPath, string excludedFileName)
            : base(path, new EnumerationOptions
            {
                AttributesToSkip = 0,
                IgnoreInaccessible = true,
                RecurseSubdirectories = true,
                ReturnSpecialDirectories = false
            })
        {
            _excludedFullPath = excludedFullPath;
            _excludedFileName = excludedFileName ?? string.Empty;
        }

        protected override bool ShouldIncludeEntry(ref FileSystemEntry entry)
        {
            if (entry.IsDirectory)
            {
                return false;
            }

            if (!string.IsNullOrEmpty(_excludedFullPath)
                && entry.FileName.Equals(_excludedFileName, StringComparison.OrdinalIgnoreCase)
                && string.Equals(entry.ToFullPath(), _excludedFullPath, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            return true;
        }

        protected override bool ShouldRecurseIntoEntry(ref FileSystemEntry entry)
        {
            return entry.IsDirectory
                && (entry.Attributes & FileAttributes.ReparsePoint) == 0;
        }

        protected override long TransformEntry(ref FileSystemEntry entry)
        {
            return entry.Length;
        }
    }

    public static class DirectorySizeScanner
    {
        public static DirectorySizeResult[] MeasureDirectories(string[] paths, string excludedFullPath, int maxDegreeOfParallelism)
        {
            if (paths == null || paths.Length == 0)
            {
                return Array.Empty<DirectorySizeResult>();
            }

            var results = new DirectorySizeResult[paths.Length];
            var effectiveDegree = maxDegreeOfParallelism > 0
                ? maxDegreeOfParallelism
                : Environment.ProcessorCount;
            var excludedFileName = string.IsNullOrWhiteSpace(excludedFullPath)
                ? string.Empty
                : Path.GetFileName(excludedFullPath);

            Parallel.For(0, paths.Length, new ParallelOptions
            {
                MaxDegreeOfParallelism = effectiveDegree
            }, index =>
            {
                var path = paths[index];
                long size;
                var hadError = false;

                try
                {
                    size = MeasureDirectory(path, excludedFullPath, excludedFileName);
                }
                catch
                {
                    size = 0;
                    hadError = true;
                }

                results[index] = new DirectorySizeResult
                {
                    Path = path,
                    Size = size,
                    HadError = hadError
                };
            });

            return results;
        }

        public static long MeasureDirectory(string path, string excludedFullPath)
        {
            var excludedFileName = string.IsNullOrWhiteSpace(excludedFullPath)
                ? string.Empty
                : Path.GetFileName(excludedFullPath);

            return MeasureDirectory(path, excludedFullPath, excludedFileName);
        }

        private static long MeasureDirectory(string path, string excludedFullPath, string excludedFileName)
        {
            long sum = 0;

            using var enumerator = new DirectorySizeEnumerator(path, excludedFullPath, excludedFileName);
            while (enumerator.MoveNext())
            {
                sum += enumerator.Current;
            }

            return sum;
        }
    }
}
'@

    Add-Type -TypeDefinition $typeDefinition -Language CSharp
}

function Get-LxDirectorySizeCaches {
    [CmdletBinding()]
    param(
        [hashtable]$Cache
    )

    $runtimeCache = if ($Cache -and $Cache.ContainsKey('__Runtime')) {
        $Cache['__Runtime']
    }
    elseif ($Cache) {
        $Cache
    }
    else {
        $null
    }

    $persistentCache = if ($Cache -and $Cache.ContainsKey('__Persistent')) {
        $Cache['__Persistent']
    }
    else {
        $null
    }

    [PSCustomObject]@{
        RuntimeCache    = $runtimeCache
        PersistentCache = $persistentCache
    }
}

function Get-LxValidatedCachedDirectorySize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [long]$LastWriteTimeUtcTicks,

        [hashtable]$RuntimeCache,

        [hashtable]$PersistentCache
    )

    if ($RuntimeCache -and $RuntimeCache.ContainsKey($Path)) {
        return [PSCustomObject]@{
            Hit    = $true
            Size   = [long]$RuntimeCache[$Path]
            Source = 'runtime'
        }
    }

    if (-not $PersistentCache -or -not $PersistentCache.ContainsKey($Path)) {
        return $null
    }

    $entry = $PersistentCache[$Path]
    $maxAgeTicks = (Get-LxSizeCacheTtl).Ticks
    $entryAgeTicks = [DateTime]::UtcNow.Ticks - [long]$entry['CachedAtUtcTicks']
    $isValid = (
        $entryAgeTicks -ge 0 -and
        $entryAgeTicks -le $maxAgeTicks -and
        [long]$entry['LastWriteTimeUtcTicks'] -eq [long]$LastWriteTimeUtcTicks
    )

    if (-not $isValid) {
        $null = $PersistentCache.Remove($Path)
        return $null
    }

    $cachedSize = [long]$entry['Size']
    if ($RuntimeCache) {
        $RuntimeCache[$Path] = $cachedSize
    }

    [PSCustomObject]@{
        Hit    = $true
        Size   = $cachedSize
        Source = 'persistent'
    }
}

function Invoke-LxDirectorySizeScanBatch {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$Paths,

        [int]$MaxDegreeOfParallelism = $script:LxDirectorySizeScannerMaxDegreeOfParallelism
    )

    $scanPaths = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($scanPaths.Count -eq 0) {
        return @()
    }

    Initialize-LxDirectorySizeScanner

    $cacheFilePath = Get-LxPersistentSizeCachePath
    @([Lx.DirectorySizeScanner]::MeasureDirectories(
            [string[]]$scanPaths,
            $cacheFilePath,
            $MaxDegreeOfParallelism))
}

function Get-LxDirectorySizePlan {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Items,

        [hashtable]$Cache
    )

    $stores = Get-LxDirectorySizeCaches -Cache $Cache
    $pendingDirectories = [System.Collections.Generic.List[object]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $cacheHitCount = 0
    $runtimeHitCount = 0
    $persistentHitCount = 0

    foreach ($item in @($Items)) {
        if (-not $item -or -not $item.PSIsContainer) {
            continue
        }

        $path = [string]$item.FullName
        if (-not $seenPaths.Add($path)) {
            continue
        }

        $lastWriteTimeUtcTicks = [long]$item.LastWriteTimeUtc.Ticks
        $cachedSize = Get-LxValidatedCachedDirectorySize -Path $path -LastWriteTimeUtcTicks $lastWriteTimeUtcTicks -RuntimeCache $stores.RuntimeCache -PersistentCache $stores.PersistentCache

        if ($cachedSize) {
            $cacheHitCount++
            if ($cachedSize.Source -eq 'runtime') {
                $runtimeHitCount++
            }
            elseif ($cachedSize.Source -eq 'persistent') {
                $persistentHitCount++
            }

            continue
        }

        $null = $pendingDirectories.Add([PSCustomObject]@{
                Path                  = $path
                LastWriteTimeUtcTicks = $lastWriteTimeUtcTicks
            })
    }

    [PSCustomObject]@{
        RuntimeCache       = $stores.RuntimeCache
        PersistentCache    = $stores.PersistentCache
        PendingDirectories = @($pendingDirectories)
        DirectoryCount     = $seenPaths.Count
        CacheHitCount      = $cacheHitCount
        RuntimeHitCount    = $runtimeHitCount
        PersistentHitCount = $persistentHitCount
    }
}

function Merge-LxDirectorySizeResults {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Results,

        [hashtable]$RuntimeCache,

        [hashtable]$PersistentCache
    )

    $nowTicks = [DateTime]::UtcNow.Ticks
    $mergedCount = 0

    foreach ($result in @($Results)) {
        $path = [string]$result.Path
        $size = [long]$result.Size

        if ($RuntimeCache) {
            $RuntimeCache[$path] = $size
        }

        if ($PersistentCache) {
            $PersistentCache[$path] = @{
                Size                  = $size
                CachedAtUtcTicks      = $nowTicks
                LastWriteTimeUtcTicks = [long]$result.LastWriteTimeUtcTicks
            }
        }

        $mergedCount++
    }

    $mergedCount
}

function Prime-LxDirectorySizes {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$PathGroups,

        [Parameter(Mandatory)]
        [object]$Options,

        [hashtable]$DirectorySizeCache
    )

    if (-not $Options.RecurseSize) {
        return
    }

    $directoryItems = foreach ($pathGroup in @($PathGroups)) {
        foreach ($item in @($pathGroup.Items)) {
            if ($item.PSIsContainer) {
                $item
            }
        }
    }

    $plan = Get-LxDirectorySizePlan -Items @($directoryItems) -Cache $DirectorySizeCache
    if ($plan.PendingDirectories.Count -eq 0) {
        return
    }

    $lastWriteTimeByPath = @{}
    foreach ($directory in @($plan.PendingDirectories)) {
        $lastWriteTimeByPath[[string]$directory.Path] = [long]$directory.LastWriteTimeUtcTicks
    }

    $results = foreach ($result in @(Invoke-LxDirectorySizeScanBatch -Paths @($plan.PendingDirectories.Path))) {
        [PSCustomObject]@{
            Path                  = [string]$result.Path
            Size                  = [long]$result.Size
            HadError              = [bool]$result.HadError
            LastWriteTimeUtcTicks = if ($lastWriteTimeByPath.ContainsKey([string]$result.Path)) { [long]$lastWriteTimeByPath[[string]$result.Path] } else { [long]0 }
        }
    }

    $null = Merge-LxDirectorySizeResults -Results @($results) -RuntimeCache $plan.RuntimeCache -PersistentCache $plan.PersistentCache
}

function Get-LxDirectorySizeBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [hashtable]$Cache
    )

    $stores = Get-LxDirectorySizeCaches -Cache $Cache
    $runtimeCache = $stores.RuntimeCache
    $persistentCache = $stores.PersistentCache

    $directoryItem = $null
    try {
        $directoryItem = Get-Item -LiteralPath $Path -ErrorAction Stop
    }
    catch {
    }

    $currentLastWriteTimeUtcTicks = if ($directoryItem) {
        [long]$directoryItem.LastWriteTimeUtc.Ticks
    }
    else {
        [long]0
    }

    $cachedSize = Get-LxValidatedCachedDirectorySize -Path $Path -LastWriteTimeUtcTicks $currentLastWriteTimeUtcTicks -RuntimeCache $runtimeCache -PersistentCache $persistentCache
    if ($cachedSize) {
        return [long]$cachedSize.Size
    }

    try {
        $scanResult = @(Invoke-LxDirectorySizeScanBatch -Paths @($Path) -MaxDegreeOfParallelism 1) | Select-Object -First 1
        $size = if ($scanResult) {
            [long]$scanResult.Size
        }
        else {
            [long]0
        }

        if ($runtimeCache) {
            $runtimeCache[$Path] = $size
        }

        if ($persistentCache) {
            $persistentCache[$Path] = @{
                Size                  = $size
                CachedAtUtcTicks      = [DateTime]::UtcNow.Ticks
                LastWriteTimeUtcTicks = $currentLastWriteTimeUtcTicks
            }
        }

        return $size
    }
    catch {
        if ($runtimeCache) {
            $runtimeCache[$Path] = [long]0
        }

        if ($persistentCache) {
            $persistentCache[$Path] = @{
                Size                  = [long]0
                CachedAtUtcTicks      = [DateTime]::UtcNow.Ticks
                LastWriteTimeUtcTicks = $currentLastWriteTimeUtcTicks
            }
        }

        return [long]0
    }
}

function Get-LxSizeInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory)]
        [object]$Options,

        [hashtable]$DirectorySizeCache
    )

    if ($Item.PSIsContainer) {
        if ($Options.RecurseSize) {
            $rawSize = Get-LxDirectorySizeBytes -Path $Item.FullName -Cache $DirectorySizeCache

            return [PSCustomObject]@{
                RawSize  = [long]$rawSize
                SizeText = Format-LxHumanSize -Bytes $rawSize
            }
        }

        return [PSCustomObject]@{
            RawSize  = [long]-1
            SizeText = ''
        }
    }

    $fileSize = [long]$Item.Length

    [PSCustomObject]@{
        RawSize  = $fileSize
        SizeText = Format-LxHumanSize -Bytes $fileSize
    }
}

function Get-LxRenderedName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    function Replace-LxIconPreserveStyle {
        param(
            [Parameter(Mandatory)]
            [string]$RenderedName,

            [Parameter(Mandatory)]
            [string]$NewIcon,

            [Parameter(Mandatory)]
            [string]$FallbackName
        )

        $escape = [char]27
        $escapedEscape = [regex]::Escape([string]$escape)
        $pattern = "^(?<prefix>(?:${escapedEscape}\[[0-9;]*m)*).+?(?<gap>\s{2})(?<name>.+?)(?<suffix>(?:${escapedEscape}\[[0-9;]*m)*)$"

        if ($RenderedName -match $pattern) {
            return "$($matches.prefix)$NewIcon$($matches.gap)$($matches.name)$($matches.suffix)"
        }

        return "$NewIcon  $FallbackName"
    }

    $formatter = Get-Command -Name Format-TerminalIcons -ErrorAction SilentlyContinue
    if (-not $formatter) {
        if ($Item.PSIsContainer) {
            switch -Regex ($Item.Name) {
                '^Downloads$' { return "󰉍  $($Item.Name)" }
                '^Videos$'    { return "󛿺  $($Item.Name)" }
                '^Desktop$'   { return "  $($Item.Name)" }
                '^Contacts$'  { return "󰛋  $($Item.Name)" }
                '^Pictures$'  { return "󰉏  $($Item.Name)" }
                '^Music$'     { return "󰲸  $($Item.Name)" }
                '^OneDrive$'  { return "󰅧  $($Item.Name)" }
            }
        }

        if ($Item.Extension -in @('.md', '.markdown')) {
            return "  $($Item.Name)"
        }

        if ($Item.Extension -in @('.ps1')) {
            return " $($Item.Name)"
        }

        return $Item.Name
    }

    $renderedName = (($Item | Format-TerminalIcons | Out-String).Trim())

    if ($Item.PSIsContainer) {
        switch -Regex ($Item.Name) {
            '^Downloads$' { return (Replace-LxIconPreserveStyle -RenderedName $renderedName -NewIcon "󰉍" -FallbackName $Item.Name) }
            '^Videos$'    { return (Replace-LxIconPreserveStyle -RenderedName $renderedName -NewIcon "󱧺" -FallbackName $Item.Name) }
            '^Desktop$'   { return (Replace-LxIconPreserveStyle -RenderedName $renderedName -NewIcon "" -FallbackName $Item.Name) }
            '^Contacts$'  { return (Replace-LxIconPreserveStyle -RenderedName $renderedName -NewIcon "󰛋" -FallbackName $Item.Name) }
            '^Pictures$'  { return (Replace-LxIconPreserveStyle -RenderedName $renderedName -NewIcon "󰉏" -FallbackName $Item.Name) }
            '^Music$'     { return (Replace-LxIconPreserveStyle -RenderedName $renderedName -NewIcon "󰲸" -FallbackName $Item.Name) }
            '^OneDrive$'  { return (Replace-LxIconPreserveStyle -RenderedName $renderedName -NewIcon "󰅧" -FallbackName $Item.Name) }
        }
    }

    if ($Item.Extension -in @('.md', '.markdown')) {
        return (Replace-LxIconPreserveStyle -RenderedName $renderedName -NewIcon "" -FallbackName $Item.Name)
    }

    if ($Item.Extension -in @('.ps1')) {
        return (Replace-LxIconPreserveStyle -RenderedName $renderedName -NewIcon "" -FallbackName $Item.Name)
    }

    return $renderedName
}

function Test-LxHyperlinkSupport {
    [CmdletBinding()]
    param()

    if (-not $Host.UI.SupportsVirtualTerminal) {
        return $false
    }

    if (-not $PSStyle -or $PSStyle.PSObject.Methods.Name -notcontains 'FormatHyperlink') {
        return $false
    }

    if ($PSStyle.OutputRendering -eq [System.Management.Automation.OutputRendering]::PlainText) {
        return $false
    }

    $true
}

function Get-LxHyperlinkUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory)]
        [object]$Options
    )

    if (-not $Options.LinksEnabled -or -not $Item.PSIsContainer -or -not (Test-LxHyperlinkSupport)) {
        return $null
    }

    try {
        return ([System.Uri]$Item.FullName).AbsoluteUri
    }
    catch {
        return $null
    }
}

function Format-LxHyperlinkText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [string]$Uri
    )

    if ([string]::IsNullOrWhiteSpace($Uri)) {
        return $Text
    }

    try {
        return $PSStyle.FormatHyperlink($Text, [System.Uri]$Uri)
    }
    catch {
        return $Text
    }
}

function Get-LxNativeLayout {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Items
    )

    $defaultHeaderPrefix = 'Mode                LastWriteTime         '
    $defaultUnderlinePrefix = '----                -------------         '
    $defaultPrefixWidth = $defaultHeaderPrefix.Length
    $defaultLastWriteTimeStart = $defaultHeaderPrefix.IndexOf('LastWriteTime')

    if ($Items.Count -eq 0) {
        return [PSCustomObject]@{
            HeaderPrefix   = $defaultHeaderPrefix
            UnderlinePrefix = $defaultUnderlinePrefix
            PrefixWidth    = $defaultPrefixWidth
            RowPrefixes    = @()
        }
    }

    $lines = @($Items | Out-String -Width 4096 -Stream)
    $headerIndex = -1

    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*Mode\s+LastWriteTime\s+Length\s+Name\s*$') {
            $headerIndex = $index
            break
        }
    }

    if ($headerIndex -lt 0) {
        return [PSCustomObject]@{
            HeaderPrefix   = $defaultHeaderPrefix
            UnderlinePrefix = $defaultUnderlinePrefix
            PrefixWidth    = $defaultPrefixWidth
            RowPrefixes    = @((' ' * $defaultPrefixWidth) * $Items.Count)
        }
    }

    $headerLine = $lines[$headerIndex]
    $underlineLine = if (($headerIndex + 1) -lt $lines.Count) {
        $lines[$headerIndex + 1]
    }
    else {
        $defaultUnderlinePrefix
    }

    $lastWriteTimeStart = $headerLine.IndexOf('LastWriteTime')
    if ($lastWriteTimeStart -lt 0) {
        $lastWriteTimeStart = $defaultLastWriteTimeStart
    }

    $lengthStart = $headerLine.IndexOf('Length')
    if ($lengthStart -lt 0) {
        $lengthStart = $defaultPrefixWidth
    }

    $rowPrefixes = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $Items) {
        $modeText = Get-LxModeText -Item $item
        $lastWriteTimeText = Get-LxLastWriteTimeText -Item $item

        # Match the native header spacing without reusing raw row text, so
        # PowerShell's original Length digits cannot bleed into lx's Size column.
        $rowLastWriteTimeStart = [Math]::Max($modeText.Length + 2, $lastWriteTimeStart - 4)

        $prefix = (
            $modeText.PadRight($rowLastWriteTimeStart) +
            $lastWriteTimeText.PadRight([Math]::Max(0, $lengthStart - $lastWriteTimeStart))
        )

        if ($prefix.Length -gt $lengthStart) {
            $prefix = $prefix.Substring(0, $lengthStart)
        }
        else {
            $prefix = $prefix.PadRight($lengthStart)
        }

        $null = $rowPrefixes.Add($prefix)
    }

    [PSCustomObject]@{
        HeaderPrefix    = $headerLine.Substring(0, $lengthStart)
        UnderlinePrefix = if ($underlineLine.Length -ge $lengthStart) {
            $underlineLine.Substring(0, $lengthStart)
        }
        else {
            $underlineLine.PadRight($lengthStart)
        }
        PrefixWidth     = $lengthStart
        RowPrefixes     = @($rowPrefixes)
    }
}

function Get-LxTreePreviewCacheKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory)]
        [object]$Options
    )

    '{0}|all={1}|depth={2}' -f $Item.FullName, [bool]$Options.ShowAll, [int]$Options.TreeDepth
}

function Get-LxTreePreviewForegroundColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    $isHidden = (($Item.Attributes -band [System.IO.FileAttributes]::Hidden) -ne 0)

    if ($isHidden -and -not $Item.PSIsContainer) {
        return [System.ConsoleColor]::DarkGray
    }

    if ($Item.PSIsContainer) {
        return [System.ConsoleColor]::Blue
    }

    $null
}

function Get-LxTreePreviewLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory)]
        [object]$Options,

        [hashtable]$PreviewCache
    )

    if (-not $Item.PSIsContainer) {
        return @()
    }

    $cacheKey = $null
    if ($PreviewCache) {
        $cacheKey = Get-LxTreePreviewCacheKey -Item $Item -Options $Options
        if ($PreviewCache.ContainsKey($cacheKey)) {
            return @($PreviewCache[$cacheKey])
        }
    }

    try {
        $children = @(Get-ChildItem -LiteralPath $Item.FullName -Force:$Options.ShowAll -ErrorAction Stop)
    }
    catch {
        if ($PreviewCache -and $null -ne $cacheKey) {
            $PreviewCache[$cacheKey] = @()
        }
        return @()
    }

    if ($children.Count -eq 0) {
        if ($PreviewCache -and $null -ne $cacheKey) {
            $PreviewCache[$cacheKey] = @()
        }
        return @()
    }

    $sortedChildren = @($children | Sort-Object -Property Name -Stable)
    $previewLines = [System.Collections.Generic.List[object]]::new()

    # Preview children stay name-sorted in v1 even when the top-level rows are
    # size-sorted. TreeDepth is fixed at 1 for now, but the cache key and options
    # object already leave room for deeper previews later.
    for ($index = 0; $index -lt $sortedChildren.Count; $index++) {
        $child = $sortedChildren[$index]
        $branch = if ($index -eq ($sortedChildren.Count - 1)) {
            '└── '
        }
        else {
            '├── '
        }

        $null = $previewLines.Add([PSCustomObject]@{
            PrefixText      = $branch
            Text            = $child.Name
            ForegroundColor = Get-LxTreePreviewForegroundColor -Item $child
            HyperlinkUri    = Get-LxHyperlinkUri -Item $child -Options $Options
        })
    }

    if ($PreviewCache -and $null -ne $cacheKey) {
        $PreviewCache[$cacheKey] = @($previewLines)
    }

    @($previewLines)
}

function ConvertTo-LxDisplayRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory)]
        [object]$Options,

        [int]$OriginalIndex = 0,

        [hashtable]$DirectorySizeCache,

        [hashtable]$PreviewCache,

        [string]$NativePrefix = ''
    )

    $sizeInfo = Get-LxSizeInfo -Item $Item -Options $Options -DirectorySizeCache $DirectorySizeCache
    $continuationLines = @()

    if ($Options.TreeEnabled -and $Item.PSIsContainer) {
        $continuationLines = @(Get-LxTreePreviewLines -Item $Item -Options $Options -PreviewCache $PreviewCache)
    }

    [PSCustomObject]@{
        Item              = $Item
        ModeText          = Get-LxModeText -Item $Item
        LastWriteTimeText = Get-LxLastWriteTimeText -Item $Item
        SizeText          = $sizeInfo.SizeText
        RawSize           = [long]$sizeInfo.RawSize
        RenderedName      = Get-LxRenderedName -Item $Item
        HyperlinkUri      = Get-LxHyperlinkUri -Item $Item -Options $Options
        IsDirectory       = [bool]$Item.PSIsContainer
        ContinuationLines = $continuationLines
        NativePrefix      = $NativePrefix
        OriginalIndex     = $OriginalIndex
    }
}

function Sort-LxDisplayRows {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [Parameter(Mandatory)]
        [object]$Options
    )

    if (-not $Options.SortBySize) {
        return @($Rows)
    }

    if ($Options.SortAscending) {
        return @($Rows | Sort-Object -Property RawSize -Stable)
    }

    @($Rows | Sort-Object -Property RawSize -Descending -Stable)
}

function Measure-LxColumnWidths {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $modeMax = ($Rows | ForEach-Object { $_.ModeText.Length } | Measure-Object -Maximum).Maximum
    $timeMax = ($Rows | ForEach-Object { $_.LastWriteTimeText.Length } | Measure-Object -Maximum).Maximum
    $sizeMax = ($Rows | ForEach-Object { $_.SizeText.Length } | Measure-Object -Maximum).Maximum

    if ($null -eq $modeMax) {
        $modeMax = 0
    }

    if ($null -eq $timeMax) {
        $timeMax = 0
    }

    if ($null -eq $sizeMax) {
        $sizeMax = 0
    }

    [PSCustomObject]@{
        ModeWidth          = [Math]::Max([Math]::Max(20, [int]$modeMax), 'Mode'.Length)
        LastWriteTimeWidth = [Math]::Max([Math]::Max(22, [int]$timeMax), 'LastWriteTime'.Length)
        SizeWidth          = [Math]::Max([Math]::Max(6, [int]$sizeMax), 'Size'.Length)
        GapAfterMode       = 0
        GapAfterTime       = 0
        GapAfterSize       = 3
        PrefixWidth        = [Math]::Max([Math]::Max(20, [int]$modeMax), 'Mode'.Length) + [Math]::Max([Math]::Max(22, [int]$timeMax), 'LastWriteTime'.Length)
        HeaderPrefix       = ''
        UnderlinePrefix    = ''
    }
}

function Write-LxHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ColumnWidths
    )

    $gapAfterSize = ' ' * $ColumnWidths.GapAfterSize
    $headerPrefix = if ($ColumnWidths.HeaderPrefix) {
        $ColumnWidths.HeaderPrefix
    }
    else {
        ('Mode'.PadRight($ColumnWidths.ModeWidth)) +
        (' ' * $ColumnWidths.GapAfterMode) +
        ('LastWriteTime'.PadRight($ColumnWidths.LastWriteTimeWidth)) +
        (' ' * $ColumnWidths.GapAfterTime)
    }
    $underlinePrefix = if ($ColumnWidths.UnderlinePrefix) {
        $ColumnWidths.UnderlinePrefix
    }
    else {
        (('----').PadRight($ColumnWidths.ModeWidth)) +
        (' ' * $ColumnWidths.GapAfterMode) +
        (('-------------').PadRight($ColumnWidths.LastWriteTimeWidth)) +
        (' ' * $ColumnWidths.GapAfterTime)
    }

    Write-Host -NoNewline $headerPrefix -ForegroundColor Green
    Write-Host -NoNewline ('Size'.PadRight($ColumnWidths.SizeWidth)) -ForegroundColor Green
    Write-Host -NoNewline $gapAfterSize
    Write-Host 'Name' -ForegroundColor Green

    Write-Host -NoNewline $underlinePrefix -ForegroundColor Green
    Write-Host -NoNewline (('----').PadRight($ColumnWidths.SizeWidth)) -ForegroundColor Green
    Write-Host -NoNewline $gapAfterSize
    Write-Host '----' -ForegroundColor Green
}

function Get-LxContinuationPrefix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ColumnWidths
    )

    (' ' * $ColumnWidths.PrefixWidth) +
    (' ' * $ColumnWidths.SizeWidth) +
    (' ' * $ColumnWidths.GapAfterSize)
}

function Get-LxViewportWidth {
    [CmdletBinding()]
    param()

    try {
        if ($Host -and $Host.UI -and $Host.UI.RawUI) {
            $windowWidth = [int]$Host.UI.RawUI.WindowSize.Width
            if ($windowWidth -gt 0) {
                return $windowWidth
            }

            $bufferWidth = [int]$Host.UI.RawUI.BufferSize.Width
            if ($bufferWidth -gt 0) {
                return $bufferWidth
            }
        }
    }
    catch {
    }

    try {
        $consoleWidth = [int][System.Console]::WindowWidth
        if ($consoleWidth -gt 0) {
            return $consoleWidth
        }
    }
    catch {
    }

    # If width detection is unavailable, keep the original tree text unchanged.
    4096
}

function Format-LxTreePreviewText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [int]$AvailableWidth
    )

    if ($AvailableWidth -le 0) {
        return ''
    }

    if ($Text.Length -le $AvailableWidth) {
        return $Text
    }

    for ($visibleChars = $Text.Length - 1; $visibleChars -ge 0; $visibleChars--) {
        $remainingChars = $Text.Length - $visibleChars
        $suffix = "...(+$remainingChars more)"

        if (($visibleChars + $suffix.Length) -le $AvailableWidth) {
            if ($visibleChars -le 0) {
                return $suffix
            }

            return $Text.Substring(0, $visibleChars) + $suffix
        }
    }

    if ($AvailableWidth -le 3) {
        return '.' * $AvailableWidth
    }

    $fallbackVisibleChars = [Math]::Max(0, $AvailableWidth - 3)
    $Text.Substring(0, $fallbackVisibleChars) + '...'
}

function Write-LxContinuationLines {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Lines,

        [Parameter(Mandatory)]
        [object]$ColumnWidths
    )

    $continuationLines = @($Lines)
    if ($continuationLines.Count -eq 0) {
        return
    }

    $continuationPrefix = Get-LxContinuationPrefix -ColumnWidths $ColumnWidths
    $viewportWidth = Get-LxViewportWidth

    foreach ($line in $continuationLines) {
        Write-Host -NoNewline $continuationPrefix

        $linePrefix = if ($line -isnot [string] -and $line.PSObject.Properties.Match('PrefixText').Count -gt 0) {
            [string]$line.PrefixText
        }
        else {
            ''
        }

        $lineText = if ($line -isnot [string] -and $line.PSObject.Properties.Match('Text').Count -gt 0) {
            [string]$line.Text
        }
        else {
            [string]$line
        }

        $foregroundColor = if ($line -isnot [string] -and $line.PSObject.Properties.Match('ForegroundColor').Count -gt 0) {
            $line.ForegroundColor
        }
        else {
            $null
        }

        $hyperlinkUri = if ($line -isnot [string] -and $line.PSObject.Properties.Match('HyperlinkUri').Count -gt 0) {
            [string]$line.HyperlinkUri
        }
        else {
            ''
        }

        $availableTextWidth = [Math]::Max(0, $viewportWidth - $continuationPrefix.Length - $linePrefix.Length)
        $lineText = Format-LxTreePreviewText -Text $lineText -AvailableWidth $availableTextWidth
        $lineText = Format-LxHyperlinkText -Text $lineText -Uri $hyperlinkUri

        Write-Host -NoNewline $linePrefix -ForegroundColor DarkGray

        if ($null -ne $foregroundColor -and $foregroundColor -ne '') {
            Write-Host $lineText -ForegroundColor $foregroundColor
        }
        else {
            Write-Host $lineText
        }
    }
}

function Write-LxRowBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Row,

        [Parameter(Mandatory)]
        [object]$ColumnWidths
    )

    $sizeShiftLeft = 2
    $rowPrefix = $Row.NativePrefix
    $actualSizeShift = 0

    if ($rowPrefix) {
        $trailingSpaces = $rowPrefix.Length - $rowPrefix.TrimEnd().Length
        $actualSizeShift = [Math]::Min($sizeShiftLeft, $trailingSpaces)

        if ($actualSizeShift -gt 0) {
            $rowPrefix = $rowPrefix.Substring(0, $rowPrefix.Length - $actualSizeShift)
        }
    }

    $gapAfterSize = ' ' * ($ColumnWidths.GapAfterSize + $actualSizeShift)
    $sizeSegment = if ([string]::IsNullOrEmpty($Row.SizeText)) {
        ' ' * $ColumnWidths.SizeWidth
    }
    else {
        $Row.SizeText.PadLeft($ColumnWidths.SizeWidth)
    }

    if ($rowPrefix) {
        Write-Host -NoNewline $rowPrefix -ForegroundColor Gray
    }
    else {
        Write-Host -NoNewline ($Row.ModeText.PadRight($ColumnWidths.ModeWidth)) -ForegroundColor Gray
        Write-Host -NoNewline (' ' * $ColumnWidths.GapAfterMode)
        Write-Host -NoNewline ($Row.LastWriteTimeText.PadRight($ColumnWidths.LastWriteTimeWidth)) -ForegroundColor Gray
        Write-Host -NoNewline (' ' * $ColumnWidths.GapAfterTime)
    }
    Write-Host -NoNewline $sizeSegment -ForegroundColor Gray
    Write-Host -NoNewline $gapAfterSize
    Write-Host (Format-LxHyperlinkText -Text $Row.RenderedName -Uri $Row.HyperlinkUri)

    if (-not $Row.PSObject.Properties.Match('ContinuationLines')) {
        return
    }

    Write-LxContinuationLines -Lines @($Row.ContinuationLines) -ColumnWidths $ColumnWidths
}

function Write-LxPathGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$PathGroup,

        [Parameter(Mandatory)]
        [object]$Options,

        [hashtable]$DirectorySizeCache,

        [hashtable]$PreviewCache,

        [switch]$IncludeLeadingBlankLine
    )

    $nativeLayout = Get-LxNativeLayout -Items @($PathGroup.Items)
    $rows = for ($index = 0; $index -lt $PathGroup.Items.Count; $index++) {
        $nativePrefix = if ($index -lt $nativeLayout.RowPrefixes.Count) {
            $nativeLayout.RowPrefixes[$index]
        }
        else {
            ''
        }

        ConvertTo-LxDisplayRow -Item $PathGroup.Items[$index] -Options $Options -OriginalIndex $index -DirectorySizeCache $DirectorySizeCache -PreviewCache $PreviewCache -NativePrefix $nativePrefix
    }

    $rows = Sort-LxDisplayRows -Rows @($rows) -Options $Options
    $columnWidths = Measure-LxColumnWidths -Rows @($rows)
    $columnWidths.PrefixWidth = $nativeLayout.PrefixWidth
    $columnWidths.HeaderPrefix = $nativeLayout.HeaderPrefix
    $columnWidths.UnderlinePrefix = $nativeLayout.UnderlinePrefix

    if ($IncludeLeadingBlankLine) {
        Write-Host ''
    }

    Write-Host "    Directory: $($PathGroup.DisplayPath)"
    Write-Host ''
    Write-LxHeader -ColumnWidths $columnWidths

    foreach ($row in $rows) {
        Write-LxRowBlock -Row $row -ColumnWidths $columnWidths
    }
}

function lx {
    [CmdletBinding()]
    param(
        [switch]$r,
        [switch]$s,
        [switch]$a,
        [switch]$rs,
        [switch]$rsa,
        [switch]$ra,

        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$RemainingArgs
    )

    $options = Resolve-LxOptions -r:$r -s:$s -a:$a -rs:$rs -rsa:$rsa -ra:$ra -RemainingArgs $RemainingArgs
    if ($null -eq $options) {
        return
    }

    if ($options.ClearCache) {
        $clearResult = Clear-LxPersistentSizeCache

        if (-not $options.ShowCacheInfo) {
            if ($clearResult.Cleared) {
                Write-Host "Cache cleared: $($clearResult.Path)"
            }
            else {
                Write-Host "Cache already empty: $($clearResult.Path)"
            }

            return
        }
    }

    if ($options.ShowCacheInfo) {
        $persistentSizeCache = Load-LxPersistentSizeCache
        Save-LxPersistentSizeCache -Cache $persistentSizeCache
        $cacheInfo = Get-LxPersistentSizeCacheInfo
        Write-LxCacheInfo -CacheInfo $cacheInfo
        return
    }

    $persistentSizeCache = Load-LxPersistentSizeCache
    $directorySizeCache = @{
        __Runtime    = @{}
        __Persistent = $persistentSizeCache
    }
    $previewCache = @{}
    $pathGroups = @(Get-LxTopLevelItems -Options $options)

    Prime-LxDirectorySizes -PathGroups @($pathGroups) -Options $options -DirectorySizeCache $directorySizeCache

    Write-Host ''

    for ($index = 0; $index -lt $pathGroups.Count; $index++) {
        Write-LxPathGroup -PathGroup $pathGroups[$index] -Options $options -DirectorySizeCache $directorySizeCache -PreviewCache $previewCache -IncludeLeadingBlankLine:($index -gt 0)
    }

    Write-Host ''

    Save-LxPersistentSizeCache -Cache $persistentSizeCache
}
