#!/bin/bash

sudo systemctl start docker.service

mkdir -p ~/timeoff
cp -v ~/application/Dockerfile ~/timeoff
cd ~/timeoff
sudo docker build --tag timeoff:latest .
sudo docker run -d -p 3000:3000 --name alpine_timeoff timeoff
