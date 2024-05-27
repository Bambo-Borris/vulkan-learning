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

# Build logic based on arguments
if [ "$arg0" == "nce" ]; then
    if [ "$arg1" == "release" ]; then
        odin build "src/nce" "${commonFlags[@]}" "${releaseFlags[@]}" -out:"build/nce.a" -build-mode:shared 
    else
        odin build "src/nce" "${commonFlags[@]}" "${debugFlags[@]}" -out:"build/nce.a" -build-mode:shared
    fi
elif [ "$arg0" == "redshift" ]; then
    if [ "$arg1" == "release" ]; then
        odin build "src/redshift" "${commonFlags[@]}" "${releaseFlags[@]}" -out:"build/redshift-assault" -build-mode:exe
    else
        odin build "src/redshift" "${commonFlags[@]}" "${debugFlags[@]}" -out:"build/redshift-assault" -build-mode:exe -debug 
    fi
    
    if [ $? -eq 1 ]; then
        echo "Build command failed!"
        exit 1
    fi

    # If 'run' is specified as the second or third argument, run the executable
    if [ "$arg2" == "run" ] || [ "$arg1" == "run" ]; then
        ./build/redshift-assault
    elif [ "$arg2" == "runmove" ] || [ "$arg1" == "runmove" ]; then
        ./build/redshift-assault MOVEMENT
    fi
elif [ "$arg0" == "ohw" ]; then
    if [ "$arg1" == "release" ]; then
        odin build "src/ohw" "${commonFlags[@]}" "${releaseFlags[@]}" -out:"build/ohw" -build-mode:exe
    else
        odin build "src/ohw" "${commonFlags[@]}" "${debugFlags[@]}" -out:"build/ohw" -build-mode:exe -debug 
    fi
    
    if [ $? -eq 1 ]; then
        echo "Build command failed!"
        exit 1
    fi

    # If 'run' is specified as the second or third argument, run the executable
    if [ "$arg2" == "run" ] || [ "$arg1" == "run" ]; then
        ./build/ohw
    fi
    # elif [ "$arg2" == "runmove" ] || [ "$arg1" == "runmove" ]; then
    #     ./build/redshift-assault MOVEMENT
    # fi
fi
