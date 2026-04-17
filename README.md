<h1 align="center"><code>lx</code> - ls evolved</h1>

<div align="center">
  <p>
    <img src="./screenshots/lx.png" alt="lx command" width="78%" />
  </p>

  <p>
    <img src="./screenshots/lx-tree-ra.png" alt="lx recursive with inline tree" width="78%" />
  </p>
</div>


`lx` is a PowerShell directory listing command with a compact table layout, human-readable sizes, recursive directory-size support, Terminal-Icons integration, and inline tree previews for top-level directories.

## Features

- Table-style output with `Mode`, `LastWriteTime`, `Size`, and `Name`
- Human-readable sizes in `KB` / `MB` / `GB`
- Directory-size calculation with `-r` flag
- Size sorting with ascending and descending modes
- Multiple target path support with separate `Directory: ...` sections
- Colored file and folder icons in the main Name column using `Terminal-Icons`
- Inline tree previews with `--tree` flag
- Tree preview coloring:
  - folders are blue
  - normal files use the terminal default color
  - hidden files are dark gray
- Tree-only long-name truncation with `...(+N more)` to keep layout readable

## Requirements

- PowerShell 7 recommended
- Any one [Nerd Fonts](https://www.nerdfonts.com/) recommended
- [`Terminal-Icons`](https://github.com/devblackops/Terminal-Icons) recommended

If `Terminal-Icons` is not installed, `lx` still works and falls back to plain names.

## Installation

Put [`lx.ps1`](./lx.ps1) somewhere permanent, then dot-source it from your PowerShell session or profile.

### Load In The Current Session

If you are in the same directory as `lx.ps1`:

```powershell
. .\lx.ps1
```

Or use an absolute path:

```powershell
. 'C:\path\to\lx.ps1'
```

Then run:

```powershell
lx
```

### Load From `$PROFILE`

1. Copy `lx.ps1` to a permanent location, for example:

```powershell
$HOME\Documents\PowerShell\Scripts\lx.ps1
```

2. Open your PowerShell profile:

```powershell
notepad $PROFILE
```

3. Add this line at the end of the file:

```powershell
. "$HOME\Documents\PowerShell\Scripts\lx.ps1"
```

4. Save the file.

5. Reload the profile:

```powershell
. $PROFILE
```

6. Test it:

```powershell
lx
lx --tree
```

> [!IMPORTANT]
> Add the dot-source line at the end of `$PROFILE`.

## Usage

### Basic

```powershell
lx
lx .
lx C:\Documents
lx C:\Documents C:\Downloads
```

### Hidden Files

```powershell
lx -a
```

### Recursive Directory Sizes

```powershell
lx -r
```

### Size Sorting

```powershell
lx -s
lx --sort=asc
lx --sort=desc
```

### Combined Flags

```powershell
lx -rs
lx -ra
lx -rsa
```

### Tree Mode

```powershell
lx --tree
lx -a --tree
lx -r --tree
lx -rs --tree
lx --tree=false
```

## Flags

| Flag | Description |
| --- | --- |
| `-a` | Show hidden files and folders. |
| `-r` | Calculate recursive directory sizes. |
| `-s` | Sort top-level rows by size descending. |
| `-rs` | Enable recursive directory sizes and size sorting. |
| `-ra` | Enable recursive directory sizes and hidden/all-files mode. |
| `-rsa` | Enable recursive directory sizes, size sorting, and hidden/all-files mode. |
| `--sort=asc` | Sort top-level rows by size ascending. |
| `--sort=desc` | Sort top-level rows by size descending. |
| `--tree` | Show inline tree previews for top-level directories. |
| `--tree=false` | Explicitly disable tree previews. |
| `--clear-cache` | Delete the persistent recursive-size cache file. |
| `--cache-size` | Show cache metadata, including path, last write time, and cache file size. |

## Tree Mode

When `--tree` is enabled:

- only top-level directories get previews
- files remain single-line rows
- preview depth is currently `1`
- only immediate children are shown
- preview children are always sorted by name
- previews respect `-a`
- unreadable directories fail closed and show no preview lines

### Tree Truncation

Only tree preview lines are truncated.

If a child name would overflow the available width, `lx` shortens it like this:

```text
very-long-file-name-th...(+20 more)
```

This keeps tree previews readable without changing normal top-level rows.

## Examples

### Standard Listing

```powershell
lx
```

### Hidden Files

```powershell
lx -a
```

### Sort By Size Ascending

```powershell
lx --sort=asc
```

### Recursive Sizes With Tree Preview

```powershell
lx -rs --tree
```

### Multiple Targets

```powershell
lx C:\Projects C:\Downloads
```

## Cache Behavior

- Recursive directory sizes use a short-lived persistent cache across repeated runs.
- The default cache TTL is 5 minutes.
- Stale cache entries are pruned automatically.
- If no valid entries remain, the cache file is deleted automatically.
- The persistent size cache is stored beside `lx.ps1` as `.lx-size-cache.json`.
- `lx --clear-cache` removes the cache file immediately.
- `lx --cache-size` prints cache path, last write time, and current cache file size.
- Tree previews are memoized only within a single invocation.

## Notes

- Recursive directory sizes use a short-lived persistent cache across repeated runs.
- Tree previews are memoized within a single invocation.
- The persistent size cache is stored beside `lx.ps1` as `.lx-size-cache.json`.
- Tree preview depth is currently fixed at one level.
- Preview child sorting is intentionally separate from top-level sorting.
- Main-row icon rendering depends on `Format-TerminalIcons`.
- Tree continuation lines are aligned under the `Name` column.

## References

- [`Terminal-Icons`](https://github.com/devblackops/Terminal-Icons) for colored file and folder icons in the main `Name` column
- [MartianMono Nerd Fonts](https://www.nerdfonts.com/) used for proper rendering of the icon glyphs
- [Firewatch](https://windowsterminalthemes.dev/?theme=Firewatch) windows terminal theme used
- Unicode box-drawing characters for inline tree preview rendering
