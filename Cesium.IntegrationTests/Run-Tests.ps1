param (
    [switch] $NoBuild,

    $SourceRoot = "$PSScriptRoot\..",
    $OutDir = "$PSScriptRoot\bin",
    $TestCaseDir = "$PSScriptRoot"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function buildCompiler() {
    Write-Host 'Building the Cesium.Compiler project.'
    dotnet build Cesium.Compiler/Cesium.Compiler.csproj
    if (!$?) {
        throw "Couldn't build the compiler: dotnet build returned $LASTEXITCODE."
    }
}

function buildFileWithClExe($inputFile, $outputFile) {
    Write-Host "Compiling $inputFile with cl.exe."
    cl.exe /nologo $inputFile "/Fe$outputFile"
    if (!$?) {
        Write-Host "Error: cl.exe returned exit code $LASTEXITCODE."
        return $false
    }

    return $true
}

function buildFileWithCesium($inputFile, $outputFile) {
    Write-Host "Compiling $inputFile with Cesium."
    dotnet run --no-build --project "$SourceRoot/Cesium.Compiler" -- $inputFile $outputFile
    if (!$?) {
        Write-Host "Error: Cesium.Compiler returned exit code $LASTEXITCODE."
        return $false
    }

    return $true
}

function validateTestCase($testCase) {
    $clExeBinOutput = "$outDir\out_cl.exe"
    $cesiumBinOutput = "$outDir\out_cs.exe"

    $clExeRunLog = "$outDir\out_cl.log"
    $cesiumRunLog = "$outDir\out_cs.log"

    $expectedExitCode = 42

    if (!(buildFileWithClExe $testCase $clExeBinOutput)) {
        return $false
    }

    & $clExeBinOutput | Out-File -Encoding utf8 $clExeRunLog
    if ($LASTEXITCODE -ne $expectedExitCode) {
        Write-Host "Binary $clExeBinOutput returned code $LASTEXITCODE, but $expectedExitCode was expected."
        return $false
    }

    if (!(buildFileWithCesium $testCase $cesiumBinOutput)) {
        return $false
    }

    & $cesiumBinOutput | Out-File -Encoding utf8 $cesiumRunLog
    if ($LASTEXITCODE -ne $expectedExitCode) {
        Write-Host "Binary $cesiumBinOutput returned code $LASTEXITCODE, but $expectedExitCode was expected."
        return $false
    }

    $clExeOutput = Get-Content -LiteralPath $clExeRunLog -Raw
    $cesiumOutput = Get-Content -LiteralPath $cesiumRunLog -Raw
    if ($clExeOutput -ne $cesiumOutput) {
        Write-Host "Output for $testCase differs between cl.exe- and Cesium-compiled programs."
        Write-Host "cl.exe ($testCase):`n$clExeOutput`n"
        Write-Host "Cesium ($testCase):`n$cesiumOutput"
        return $false
    }

    $true
}

$allTestCases = Get-ChildItem "$TestCaseDir\*.c"
Write-Host "Running tests for $($allTestCases.Count) cases."

if (!$NoBuild) {
    buildCompiler
}

New-Item $OutDir -Type Directory -ErrorAction Ignore

$failedTests = @()
foreach ($testCase in $allTestCases) {
    if (validateTestCase $testCase) {
        Write-Host "$($testCase): ok."
    } else {
        Write-Host "$($testCase): failed."
        $failedTests += $testCase
    }
}

if ($failedTests.Count -gt 0) {
    $testNames = $failedTests -join "`n"
    throw "Errors in the following $($failedTests.Count) tests: $testNames"
}