#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Automated disk imaging script
# Version: 0.0.1-2017-06-10
# Required packages: uuidgen, sleuthkit, ewf-tools, hashdeep
# Created by Joshua I. James (joshua.i.james@hallym.ac.kr)
# Legal Informatics and Forensic Science Institute, Hallym University

# TODO:
# Pull imaging settings from case settings

DISKS=$(mktemp /tmp/disk.XXXX)
NDISKS=$(mktemp /tmp/disk.XXXX)
IMGDISK=""

spin[0]="-"
spin[1]="\\"
spin[2]="|"
spin[3]="/"

function clean_up {
    echo "Exiting..."
    rm -r "$DISKS"
    rm -r "$NDISKS"
    exit 1
}

trap clean_up SIGHUP SIGINT SIGTERM


function detectDisks {
    cat /proc/partitions | awk '{print $4}' | tail -n+3 | grep -v [0-9] > "$NDISKS"
}

function imageDisk {
    ewfacquire /dev/"$1"
}

# Get disks
detectDisks
# Initialize disk info
cat "$NDISKS" > "$DISKS"
echo "Detected disks:"
cat "$DISKS"
echo "Do you want to image one of the detected disks? (y/N)"
read imageDisk
if [ "$imageDisk" == "y" ] || [ "$imageDisk" == "Y" ]; then
    echo "Please enter the disk to image"
    read IMGDISK
fi

if [ "$IMGDISK" != "" ]; then
    echo "imaging disk /dev/$IMGDISK"
    imageDisk $IMGDISK
else
    echo "No disks selected, waiting for disk to be plugged in..."
    echo "ctrl+c to exit"
    echo -n "Waiting for disk ${spin[0]}"
    while true; do
        for i in "${spin[@]}"; do
            echo -ne "\b$i"
            sleep 0.5
            detectDisks
            CHANGE=$(diff "$NDISKS" "$DISKS" | grep "<" | sed 's/< //')
            if [ "$CHANGE" != "" ]; then
                for line in "$CHANGE"; do
                    echo ""
                    echo "Detected disk /dev/$line"
                    imageDisk $line
                done
            fi
            cat "$NDISKS" > "$DISKS"
        done
     done
fi
