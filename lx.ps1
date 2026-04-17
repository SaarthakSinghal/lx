$script:LxScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
elseif (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    Split-Path -Parent $PSCommandPath
}
else {
    (Get-Location).Path
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

    [PSCustomObject]@{
        ShowAll       = $showAll
        RecurseSize   = $recurseSize
        SortBySize    = $sortBySize
        SortAscending = $sortAscending
        TreeEnabled   = $treeEnabled
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
        $Item.LastWriteTime.ToString('dd-MM-yyyy    HH:mm')
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

function Get-LxDirectorySizeBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

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

    if ($runtimeCache -and $runtimeCache.ContainsKey($Path)) {
        return [long]$runtimeCache[$Path]
    }

    $directoryItem = $null
    try {
        $directoryItem = Get-Item -LiteralPath $Path -ErrorAction Stop
    }
    catch {
    }

    if ($persistentCache -and $persistentCache.ContainsKey($Path)) {
        $entry = $persistentCache[$Path]
        $currentLastWriteTimeUtcTicks = if ($directoryItem) {
            [long]$directoryItem.LastWriteTimeUtc.Ticks
        }
        else {
            [long]0
        }

        $maxAgeTicks = (Get-LxSizeCacheTtl).Ticks
        $entryAgeTicks = [DateTime]::UtcNow.Ticks - [long]$entry['CachedAtUtcTicks']

        if ($entryAgeTicks -ge 0 -and $entryAgeTicks -le $maxAgeTicks -and [long]$entry['LastWriteTimeUtcTicks'] -eq $currentLastWriteTimeUtcTicks) {
            $cachedSize = [long]$entry['Size']

            if ($runtimeCache) {
                $runtimeCache[$Path] = $cachedSize
            }

            return $cachedSize
        }

        $null = $persistentCache.Remove($Path)
    }

    try {
        $cacheFilePath = Get-LxPersistentSizeCachePath
        $files = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue)

        if (-not [string]::IsNullOrWhiteSpace($cacheFilePath)) {
            $files = @($files | Where-Object { $_.FullName -ne $cacheFilePath })
        }

        $sum = ($files | Measure-Object -Property Length -Sum).Sum

        $size = if ($null -eq $sum) {
            [long]0
        }
        else {
            [long]$sum
        }

        if ($runtimeCache) {
            $runtimeCache[$Path] = $size
        }

        if ($persistentCache) {
            $persistentCache[$Path] = @{
                Size                  = $size
                CachedAtUtcTicks      = [DateTime]::UtcNow.Ticks
                LastWriteTimeUtcTicks = if ($directoryItem) {
                    [long]$directoryItem.LastWriteTimeUtc.Ticks
                }
                else {
                    [long]0
                }
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
                LastWriteTimeUtcTicks = if ($directoryItem) {
                    [long]$directoryItem.LastWriteTimeUtc.Ticks
                }
                else {
                    [long]0
                }
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

    $formatter = Get-Command -Name Format-TerminalIcons -ErrorAction SilentlyContinue
    if (-not $formatter) {
        if ($Item.Extension -in @('.md', '.markdown')) {
            return "  $($Item.Name)"
        }

        return $Item.Name
    }

    $renderedName = (($Item | Format-TerminalIcons | Out-String).Trim())

    if ($Item.Extension -notin @('.md', '.markdown')) {
        return $renderedName
    }

    $escape = [char]27
    $pattern = "^(?<prefix>(?:$([regex]::Escape($escape))\[[0-9;]*m)*).+?(?<gap>\s{2})(?<name>.+?)(?<suffix>(?:$([regex]::Escape($escape))\[[0-9;]*m)*)$"

    if ($renderedName -match $pattern) {
        return "$($matches.prefix)$($matches.gap)$($matches.name)$($matches.suffix)"
    }

    "  $($Item.Name)"
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

    $lengthStart = $headerLine.IndexOf('Length')
    if ($lengthStart -lt 0) {
        $lengthStart = $defaultPrefixWidth
    }

    $rowPrefixes = [System.Collections.Generic.List[string]]::new()
    $rowStartIndex = $headerIndex + 2

    for ($index = 0; $index -lt $Items.Count; $index++) {
        $lineIndex = $rowStartIndex + $index
        $prefix = ' ' * $lengthStart

        if ($lineIndex -lt $lines.Count) {
            $line = $lines[$lineIndex]
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $prefix = if ($line.Length -ge $lengthStart) {
                    $line.Substring(0, $lengthStart)
                }
                else {
                    $line.PadRight($lengthStart)
                }
            }
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

        $availableTextWidth = [Math]::Max(0, $viewportWidth - $continuationPrefix.Length - $linePrefix.Length)
        $lineText = Format-LxTreePreviewText -Text $lineText -AvailableWidth $availableTextWidth

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

    $gapAfterSize = ' ' * $ColumnWidths.GapAfterSize
    $sizeSegment = if ([string]::IsNullOrEmpty($Row.SizeText)) {
        ' ' * $ColumnWidths.SizeWidth
    }
    else {
        $Row.SizeText.PadLeft($ColumnWidths.SizeWidth)
    }

    if ($Row.NativePrefix) {
        Write-Host -NoNewline $Row.NativePrefix -ForegroundColor Gray
    }
    else {
        Write-Host -NoNewline ($Row.ModeText.PadRight($ColumnWidths.ModeWidth)) -ForegroundColor Gray
        Write-Host -NoNewline (' ' * $ColumnWidths.GapAfterMode)
        Write-Host -NoNewline ($Row.LastWriteTimeText.PadRight($ColumnWidths.LastWriteTimeWidth)) -ForegroundColor Gray
        Write-Host -NoNewline (' ' * $ColumnWidths.GapAfterTime)
    }
    Write-Host -NoNewline $sizeSegment -ForegroundColor Gray
    Write-Host -NoNewline $gapAfterSize
    Write-Host $Row.RenderedName

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

    Write-Host ''

    for ($index = 0; $index -lt $pathGroups.Count; $index++) {
        Write-LxPathGroup -PathGroup $pathGroups[$index] -Options $options -DirectorySizeCache $directorySizeCache -PreviewCache $previewCache -IncludeLeadingBlankLine:($index -gt 0)
    }

    Write-Host ''

    Save-LxPersistentSizeCache -Cache $persistentSizeCache
}
