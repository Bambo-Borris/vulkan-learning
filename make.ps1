param (
    [string]$arg0,
    [string]$arg1,
    [string]$arg2
)

if (-not (Test-Path -Path "build") ) { 
    mkdir "build"
}

$commonFlags = @(
    '-warnings-as-errors',
    '-show-timings',
    '-strict-style'
    '-vet'
)

$debugFlags = @( 
    '-o:none'
)

$relwithdebinfoFlags = @(
    '-debug'
    '-o:speed',
    '-no-bounds-check'
    '-no-type-assert'
)

$releaseFlags = @(
    '-o:speed',
    '-no-bounds-check'
    '-no-type-assert'
)

if ($arg0 -eq "release") {
    odin build "src/" @commonFlags @releaseFlags -out:"build\vulkan.exe" -build-mode:exe -subsystem:windows
} else { 
    odin build "src/" @commonFlags @debugFlags -out:"build\vulkan.exe" -build-mode:exe -debug 
}

if ($lastExitCode -ne 0){ 
    Write-Output "Build failed"
    Exit
} else {
    Write-Output "Build succeeded"
}

if ($arg1 -eq "run" -Or $arg0 -eq "run") { 
    ./build/vulkan.exe
} 
    

