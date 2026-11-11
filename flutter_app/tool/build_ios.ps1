param(
    [string]$Xcross = 'xcross',
    [ValidateSet('debug', 'profile', 'release')][string]$Mode = 'debug',
    [switch]$Deploy
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$previousPath = $env:PATH
$previousSdkRoot = $env:SDKROOT
$previousBuildName = $env:XCROSS_BUILD_NAME
$previousBuildNumber = $env:XCROSS_BUILD_NUMBER
$overrideFile = Join-Path $projectRoot 'pubspec_overrides.yaml'
if ($Xcross -eq 'xcross') {
    $Xcross = Join-Path $projectRoot 'build/xcross-local/bundle/bin/xcross.exe'
    if (!(Test-Path -LiteralPath $Xcross)) {
        throw 'Run tool/prepare_xcross.ps1 first to prepare iOS icon packaging and device deployment fixes.'
    }
}
if (Test-Path -LiteralPath $overrideFile) {
    throw 'An existing pubspec_overrides.yaml must be reviewed before running this helper.'
}

Push-Location -LiteralPath $projectRoot
try {
    if (!$env:VSCMD_VER) {
        throw 'Run this helper from Developer PowerShell for Visual Studio (x64 host tools).'
    }
    $swiftInstall = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs/Swift'
    $toolchainsRoot = Join-Path $swiftInstall 'Toolchains'
    if (Test-Path -LiteralPath $toolchainsRoot) {
        $toolchain = Get-ChildItem -LiteralPath $toolchainsRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($toolchain) {
            $swiftBin = Join-Path $toolchain.FullName 'usr/bin'
            $manifestApi = Join-Path $toolchain.FullName 'usr/lib/swift/pm/ManifestAPI'
            $env:PATH = $swiftBin + ';' + $manifestApi + ';' + $env:PATH
            $swiftVersion = $toolchain.Name -replace '\+.*$', ''
            $windowsSdk = Join-Path $swiftInstall "Platforms/$swiftVersion/Windows.platform/Developer/SDKs/Windows.sdk"
            if (!$env:SDKROOT -and (Test-Path -LiteralPath $windowsSdk)) { $env:SDKROOT = $windowsSdk }
        }
    }
    # Swift's generated manifest executables also need the host runtime DLLs.
    $runtimeRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs/Swift/Runtimes'
    if (Test-Path -LiteralPath $runtimeRoot) {
        $runtime = Get-ChildItem -LiteralPath $runtimeRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($runtime) {
            $runtimeBin = Join-Path $runtime.FullName 'usr/bin'
            if (Test-Path -LiteralPath $runtimeBin) { $env:PATH = $runtimeBin + ';' + $env:PATH }
        }
    }
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }
    $packageConfig = Get-Content -LiteralPath '.dart_tool/package_config.json' -Raw | ConvertFrom-Json
    $stagingRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'build/xcross-plugin-overrides'))
    if (!$stagingRoot.StartsWith((Join-Path $projectRoot 'build') + [IO.Path]::DirectorySeparatorChar)) {
        throw 'The temporary package directory is outside this project build folder.'
    }
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    $overrides = [Collections.Generic.List[string]]::new()
    $overrides.Add('dependency_overrides:')

    # xcross 2.0.6 copies complete plugin roots under Packages/<plugin>/, but recent
    # plugin manifests expect FlutterFramework beside their nested Swift package.
    # Patch temporary copies only; the shared Pub cache and dependency sources stay intact.
    foreach ($package in $packageConfig.packages) {
        $packageUri = [uri]$package.rootUri
        if ($packageUri.IsAbsoluteUri) {
            if (!$packageUri.IsFile) { continue }
            $sourceRoot = $packageUri.LocalPath.TrimEnd('\', '/')
        } else {
            $sourceRoot = [IO.Path]::GetFullPath((Join-Path (Join-Path $projectRoot '.dart_tool') ([uri]::UnescapeDataString($package.rootUri))))
        }
        # Never stage the application root into its own ignored build directory.
        if ($sourceRoot.TrimEnd('\', '/') -eq $projectRoot.TrimEnd('\', '/')) { continue }
        $manifests = @(Get-ChildItem -LiteralPath $sourceRoot -Filter Package.swift -Recurse -File |
            Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'path:\s*"\.\./FlutterFramework"' })
        if ($manifests.Count -eq 0) { continue }
        $copyRoot = Join-Path $stagingRoot $package.name
        New-Item -ItemType Directory -Path $copyRoot -Force | Out-Null
        Get-ChildItem -LiteralPath $sourceRoot -Force | Copy-Item -Destination $copyRoot -Recurse -Force
        foreach ($manifest in $manifests) {
            $relative = [IO.Path]::GetRelativePath($sourceRoot, $manifest.FullName)
            $target = Join-Path $copyRoot $relative
            $parentParts = ([IO.Path]::GetDirectoryName($relative) -split '[\\/]') | Where-Object { $_ -ne '' }
            $frameworkPath = ('../' * ($parentParts.Count + 1)) + 'FlutterFramework'
            $source = [IO.File]::ReadAllText($target)
            $source = $source.Replace('path: "../FlutterFramework"', 'path: "' + $frameworkPath + '"')
            [IO.File]::WriteAllText($target, $source)
        }
        $overrides.Add('  ' + $package.name + ':')
        $overrides.Add("    path: '" + $copyRoot.Replace('\', '/').Replace("'", "''") + "'")
    }

    if ($overrides.Count -gt 1) {
        [IO.File]::WriteAllLines($overrideFile, $overrides)
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'Temporary iOS package resolution failed.' }
    }
    # Explicit flags take precedence over stale values in generated Xcode settings.
    $appVersion = [regex]::Match([IO.File]::ReadAllText((Join-Path $projectRoot 'pubspec.yaml')), '(?m)^version:\s*([^\s+]+)(?:\+([^\s]+))?\s*$')
    if (!$appVersion.Success) { throw 'Set an app version in pubspec.yaml before building.' }
    $buildName = $appVersion.Groups[1].Value
    $buildNumber = if ($appVersion.Groups[2].Success) { $appVersion.Groups[2].Value } else { '1' }
    if ($Deploy) {
        # The pinned local tool forwards these to its run/build pipeline.
        $env:XCROSS_BUILD_NAME = $buildName
        $env:XCROSS_BUILD_NUMBER = $buildNumber
        & $Xcross flutter run "--$Mode" --no-pub --usb
    } else {
        & $Xcross flutter build "--$Mode" --ipa --no-pub "--build-name=$buildName" "--build-number=$buildNumber"
    }
    if ($LASTEXITCODE -ne 0) { throw 'The xcross iOS build failed. See its diagnostics above.' }
    & python tool/verify_ios_bundle.py build/xcross-ios/escooter_control.app --version $buildName --build $buildNumber
    if ($LASTEXITCODE -ne 0) { throw 'The iOS bundle is missing valid icons or has incorrect version metadata.' }
} finally {
    if (Test-Path -LiteralPath $overrideFile) { Remove-Item -LiteralPath $overrideFile }
    & flutter pub get
    $env:PATH = $previousPath
    $env:SDKROOT = $previousSdkRoot
    $env:XCROSS_BUILD_NAME = $previousBuildName
    $env:XCROSS_BUILD_NUMBER = $previousBuildNumber
    Pop-Location
}
