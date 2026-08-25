$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$html = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'index.html')
$css = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'styles.css')

foreach ($file in @('index.html','styles.css','favicon.svg','robots.txt','sitemap.xml','README.md','docs/SECURITY.md','assets/portfolio-desktop.png','assets/portfolio-mobile.png')) {
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
foreach ($required in @('<link rel="canonical" href="https://suzannehoey.com/">','property="og:url" content="https://suzannehoey.com/"','property="og:image" content="https://suzannehoey.com/assets/portfolio-desktop.png"','name="twitter:image" content="https://suzannehoey.com/assets/portfolio-desktop.png"','href="mailto:business@suzannehoey.com"','"url":"https://suzannehoey.com/"','"email":"mailto:business@suzannehoey.com"')) {
  if (-not $html.Contains($required)) { throw ('Missing or incorrect production identity: ' + $required) }
}
if ([regex]::Matches($html, 'mailto:').Count -ne 2) { throw 'Unexpected email contact reference count' }
if ($html -match '<script\s+src=') { throw 'Public portfolio unexpectedly loads JavaScript' }
if ($html -match '<(script|img)[^>]+src="https?://' -or $html -match '<link[^>]+rel="stylesheet"[^>]+href="https?://') { throw 'Unexpected third-party resource reference' }
if (-not $css.Contains('@media(max-width:640px)')) { throw 'Missing mobile breakpoint' }
if (-not $css.Contains('prefers-reduced-motion')) { throw 'Missing reduced-motion support' }
$open = ($css.ToCharArray() | Where-Object { $_ -eq '{' }).Count
$close = ($css.ToCharArray() | Where-Object { $_ -eq '}' }).Count
if ($open -ne $close) { throw 'CSS braces are unbalanced' }
$jsonText = [regex]::Match($html, '<script type="application/ld\+json">\s*(.*?)\s*</script>', 'Singleline').Groups[1].Value
$null = $jsonText | ConvertFrom-Json
$robots = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'robots.txt')
if ($robots -notmatch '(?im)^Sitemap: https://suzannehoey\.com/sitemap\.xml$') { throw 'robots.txt is missing the production sitemap URL' }
$sitemap = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'sitemap.xml')
if ($sitemap -notmatch '<loc>https://suzannehoey\.com/</loc>') { throw 'sitemap.xml is missing the production URL' }
$null = [xml]$sitemap
git diff --check
if ($LASTEXITCODE -ne 0) { throw 'Git whitespace validation failed' }
Write-Output 'portfolio static validation: PASS'
