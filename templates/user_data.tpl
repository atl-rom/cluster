#!/bin/bash
echo "Alo president2e" > index.html
nohup busybox httpd -f -p 8080 &