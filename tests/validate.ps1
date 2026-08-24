$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$html = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'index.html')
$css = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'styles.css')

foreach ($file in @('index.html','styles.css','favicon.svg','robots.txt','README.md','docs/SECURITY.md','assets/portfolio-desktop.png','assets/portfolio-mobile.png')) {
  if (-not (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf)) { throw ('Missing required file: ' + $file) }
}
foreach ($id in @('content','top','work','capabilities','approach','contact')) {
  if (-not $html.Contains(('id="' + $id + '"'))) { throw ('Missing required id: ' + $id) }
}
foreach ($fragment in @('href="#work"','href="#capabilities"','href="#approach"','href="#contact"')) {
  if (-not $html.Contains($fragment)) { throw ('Missing navigation target: ' + $fragment) }
}
foreach ($required in @('<title>Suzanne Hoey','name="description"','property="og:title"','property="og:site_name"','name="twitter:title"','name="twitter:description"','application/ld+json','class="skip-link"','aria-label="Primary navigation"')) {
  if (-not $html.Contains($required)) { throw ('Missing metadata or accessibility marker: ' + $required) }
}
if ($html -match 'href="[^"]+\.pdf(?:[#?][^"]*)?"') { throw 'Public portfolio unexpectedly links to a PDF' }
if ($html -match 'govopportunity\.com|suzanne\.hoey@govopportunity\.com') { throw 'Public portfolio contains retired domain or contact identity' }
if ($html -match '<link[^>]+rel="canonical"|property="og:url"|property="og:image"|name="twitter:image"') { throw 'Origin-dependent metadata must wait for an approved production origin' }
if ($html -match 'mailto:') { throw 'Public portfolio contains an unapproved email contact' }
if ($html -match '<script\s+src=') { throw 'Public portfolio unexpectedly loads JavaScript' }
if ($html -match '<(script|img)[^>]+src="https?://' -or $html -match '<link[^>]+rel="stylesheet"[^>]+href="https?://') { throw 'Unexpected third-party resource reference' }
if (-not $css.Contains('@media(max-width:640px)')) { throw 'Missing mobile breakpoint' }
if (-not $css.Contains('prefers-reduced-motion')) { throw 'Missing reduced-motion support' }
$open = ($css.ToCharArray() | Where-Object { $_ -eq '{' }).Count
$close = ($css.ToCharArray() | Where-Object { $_ -eq '}' }).Count
if ($open -ne $close) { throw 'CSS braces are unbalanced' }
$jsonText = [regex]::Match($html, '<script type="application/ld\+json">\s*(.*?)\s*</script>', 'Singleline').Groups[1].Value
$null = $jsonText | ConvertFrom-Json
if ((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'robots.txt')) -match '(?im)^\s*Sitemap:') { throw 'robots.txt must not claim a sitemap before the production origin is approved' }
git diff --check
if ($LASTEXITCODE -ne 0) { throw 'Git whitespace validation failed' }
Write-Output 'portfolio static validation: PASS'
