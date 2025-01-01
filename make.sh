#!/bin/bash

# Assign command-line arguments to variables
arg0="$1"
arg1="$2"
arg2="$3"

# Check if the 'build' directory exists; if not, create it
if [ ! -d "build" ]; then
    mkdir "build"
fi

# Define arrays for common flags, debug flags, and release flags
commonFlags=(
    "-warnings-as-errors"
    "-show-timings"
    "-strict-style"
    "-vet"
    "-use-separate-modules"
)

debugFlags=(
    "-o:none"
)

releaseFlags=(
    "-o:speed"
    "-no-bounds-check"
    "-no-type-assert"
)

if [ "$arg1" == "release" ]; then
    odin build "src/" "${commonFlags[@]}" "${releaseFlags[@]}" -out:"build/vulkan" -build-mode:exe
else
    odin build "src/" "${commonFlags[@]}" "${debugFlags[@]}" -out:"build/vulkan" -build-mode:exe -debug 
fi

if [ $? -eq 1 ]; then
    echo "Build command failed!"
    exit 1
fi

# If 'run' is specified as the second or third argument, run the executable
if [ "$arg1" == "run" ] || [ "$arg0" == "run" ]; then
    ./build/vulkan
fi
