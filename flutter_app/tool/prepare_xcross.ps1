$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$checkout = Join-Path $projectRoot 'build/xcross-tool'
$patches = @('xcross-2.0.6-plan-reader.patch', 'xcross-2.0.6-ios-bundle.patch', 'xcross-2.0.6-preserve-certificates.patch', 'xcross-2.0.6-windows-swift-jobs.patch')
$expectedCommit = 'c28c6bc4a5a3e64888a1303ede777be49f34390b'

if (!(Test-Path -LiteralPath $checkout)) {
    & git clone --depth 1 --branch v2.0.6 https://github.com/arxdeus/xcross.git $checkout
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch the pinned xcross source.' }
}
Push-Location -LiteralPath $checkout
try {
    $commit = & git rev-parse HEAD
    if ($commit -ne $expectedCommit) { throw 'The local tool checkout is not the pinned xcross version.' }
    foreach ($patchName in $patches) {
        $patch = Join-Path $PSScriptRoot $patchName
        # Check reverse first: insertion-only patches can otherwise apply twice.
        & git apply --unidiff-zero --reverse --check $patch 2>$null
        if ($LASTEXITCODE -eq 0) { continue }
        & git apply --unidiff-zero --check $patch 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'The local tool has unexpected changes; inspect it before continuing.' }
        & git apply --unidiff-zero $patch
        if ($LASTEXITCODE -ne 0) { throw "The xcross patch failed: $patchName" }
    }
    & dart pub get
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve xcross development dependencies.' }
    & dart build cli --target packages/xcross/bin/xcross.dart --output ../xcross-local
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the local xcross tool.' }
} finally { Pop-Location }

Write-Output (Join-Path $projectRoot 'build/xcross-local/bundle/bin/xcross.exe')
