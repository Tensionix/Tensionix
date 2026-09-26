<#
    Rebuilds the project table of the Tensionix profile README from GitHub itself.

    Every public repository of the account goes in: its About line (Audion Build
    Publisher keeps it in step with the catalogue), its page on audion.dev (the
    repository homepage, set by the same publisher) and its latest release.
    Nothing is listed by hand. A new project appears on the next run; a new
    version appears at once, because the version is a badge GitHub draws live.

    Only the part between the two markers is written, and nothing in it depends on
    the date: the file changes - and gets a commit - only when the projects do.

    Runs the same on the GitHub runner (GITHUB_TOKEN set by the workflow) and on a
    Windows machine without a token (about thirty requests, well inside the
    anonymous limit).
#>
[CmdletBinding()]
param(
    [string]$Owner = 'Tensionix',
    [string]$Readme = ''
)

$ErrorActionPreference = 'Stop'
# Worked out here, not in the parameter default: Windows PowerShell leaves
# $PSScriptRoot empty there.
if (-not $Readme) { $Readme = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'README.md' }
# The source stays ASCII: Windows PowerShell reads a file without BOM as ANSI.
$dot = ' ' + [char]0x00B7 + ' '
$start = '<!-- projects:start -->'
$end = '<!-- projects:end -->'

$headers = @{ 'User-Agent' = 'tensionix-profile-readme'; Accept = 'application/vnd.github+json' }
if ($env:GITHUB_TOKEN) { $headers['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN }

function Get-Json([string]$Uri) {
    # Windows PowerShell hands a JSON array back as one object; unroll it.
    Invoke-RestMethod -Headers $headers -Uri $Uri | ForEach-Object { $_ }
}

function Format-Cell([string]$Text) {
    # A pipe would split the table row; a line break would end it.
    (($Text -replace '\r?\n', ' ') -replace '\|', '\|').Trim()
}

$repos = @(Get-Json "https://api.github.com/users/$Owner/repos?per_page=100&type=owner" |
    Where-Object { -not $_.fork -and -not $_.archived -and -not $_.private -and $_.name -ne $Owner } |
    Sort-Object name)
if (-not $repos.Count) { throw "No public repositories came back for $Owner - refusing to empty the table." }

$lines = New-Object System.Collections.Generic.List[string]
# Blank lines around the table: glued to the marker, it is not a table on GitHub.
$lines.Add('')
$lines.Add('')
$lines.Add('| Project | What it does | Version | |')
$lines.Add('|---|---|:---:|---|')
foreach ($repo in $repos) {
    $release = $null
    try { $release = Invoke-RestMethod -Headers $headers -Uri ("https://api.github.com/repos/$Owner/" + $repo.name + '/releases/latest') }
    catch {
        # 404 is the only answer that means "no release yet". Anything else - a
        # spent rate limit, a network hiccup - stops the run: otherwise the table
        # would be written without its download links and committed that way.
        $status = 0
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        if ($status -ne 404) { throw ("GitHub did not answer for {0}: {1}" -f $repo.name, $_.Exception.Message) }
    }

    $name = '[**{0}**]({1})' -f $repo.name, $repo.html_url
    $about = Format-Cell ([string]$repo.description)
    $links = New-Object System.Collections.Generic.List[string]
    if ($release) {
        $version = '![release](https://img.shields.io/github/v/release/{0}/{1}?style=flat-square&label=&color=2a7488)' -f $Owner, $repo.name
        $links.Add(('[Download]({0}/releases/latest)' -f $repo.html_url))
    } else {
        $version = '-'
    }
    if ($repo.homepage) { $links.Add(('[audion.dev]({0})' -f $repo.homepage)) }
    $lines.Add(('| {0} | {1} | {2} | {3} |' -f $name, $about, $version, ($links -join $dot)))
}
$lines.Add('')
$lines.Add('')

$text = [System.IO.File]::ReadAllText($Readme)
$from = $text.IndexOf($start)
$to = $text.IndexOf($end)
if ($from -lt 0 -or $to -lt $from) { throw "README has no $start ... $end block." }
$block = $start + ($lines -join "`n") + $end
$fresh = $text.Substring(0, $from) + $block + $text.Substring($to + $end.Length)
if ($fresh -ne $text) {
    [System.IO.File]::WriteAllText($Readme, $fresh, (New-Object System.Text.UTF8Encoding $false))
    Write-Host ('README: table rebuilt, {0} project(s).' -f $repos.Count)
} else {
    Write-Host ('README: already current, {0} project(s).' -f $repos.Count)
}
