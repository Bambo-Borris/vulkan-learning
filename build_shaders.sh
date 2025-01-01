#!/bin/bash

if [ ! -d "shaders/build" ]; then
  mkdir shaders/build/ 
fi

glslc shaders/shader.vert -o shaders/build/vert.spv
glslc shaders/shader.frag -o shaders/build/frag.spv
