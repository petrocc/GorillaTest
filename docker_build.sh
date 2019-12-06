#!/bin/bash

sudo systemctl start docker.service 

mkdir -p ~/timeoff
cp -v ~/application/Dockerfile ~/timeoff
cd ~timeoff 
docker build --tag timeoff:latest .
docker run -d -p 3000:3000 --name alpine_timeoff timeoff
