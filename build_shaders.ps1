if (-not (Test-Path -Path "shaders/build") ) { 
    mkdir "shaders/build"
}

glslc shaders/shader.vert -o shaders/build/vert.spv
glslc shaders/shader.frag -o shaders/build/frag.spv

