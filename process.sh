#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Main case processing script
# Version: 0.0.2-2017-06-10
# Required packages: uuidgen, sleuthkit, ewf-tools, hashdeep
# Created by Joshua I. James (joshua.i.james@hallym.ac.kr)
# Legal Informatics and Forensic Science Institute, Hallym University


# TODO:
# Include case settings detection
# Detect all images in a directory recursively

INPATH=$1
OUTPATH=$2

# Check Env
if [ "$INPATH" == "" ]; then
    echo "Please enter the full path and file name of the disk image"
    read -e INPATH
fi
if [ ! -f "$INPATH" ]; then
    echo "Error: Disk image is not a file"
    exit 2
fi
if [ "$OUTPATH" == "" ]; then
    echo "Please enter the full path to the output directory"
    read -e OUTPATH
fi
if [ -d "$OUTPATH" ]; then
    echo "The output directory exists. Delete this directory (cannot be undone)? (y/N)"
    read OUTCONF
    if [ "$OUTCONF" == "y" ] || [ "$OUTCONF" == "Y" ]; then
        rm -r "$OUTPATH"
    else
        echo "Output directory must be empty"
        exit 2
    fi
fi
if [ ! -d "$OUTPATH" ]; then
    echo "Create folder $OUTPATH? (y/N)"
    read OUTCONF
    if [ "$OUTCONF" == "y" ] || [ "$OUTCONF" == "Y" ]; then
        install -d "$OUTPATH"
    else
        exit 2
    fi
fi
o=$(echo "$OUTPATH" | sed 's/\/$//')
OUTPATH=$o

echo "Outpath set to $OUTPATH"
# End check Env

# Variables
LOG="$OUTPATH/log.txt"

install -d $OUTPATH
FN=$(basename $INPATH)

NOW=$(date)
echo "Begin processing at $NOW" | tee -a "$LOG"
echo "Input image set to: $INPATH" | tee -a "$LOG"
echo "Output path set to: $OUTPATH" | tee -a "$LOG"
# Find image type
ITYPE=$(img_stat "$INPATH" | grep Type | awk '{print $3}')
echo "Image type detected: $ITYPE" | tee -a "$LOG"

NOW=$(date)
VSTAT=""
case "$ITYPE" in
    ewf)
        echo "$NOW: Started verifying image, continuing..." | tee -a "$LOG"
        #ewfverify "$INPATH" | grep MD5 | tee -a "$LOG" &
        ewfverify -q "$INPATH" | tee -a "$LOG" &
        #VSTAT=$?
        ;;
    raw)
       echo "$NOW: Started verifying image, continuing..." | tee -a "$LOG"
       hashdeep "$INPATH" | tee -a "$LOG" &
       ;;
    *)
        echo "$NOW: Only ewf supported currently... exiting"
        exit 2
        ;;
esac

#if [ $VSTAT -eq 0 ]; then
#    echo "$INPATH verified successful" | tee -a "$LOG"
#else
#    echo "Image not verified!" | tee -a "$LOG"
    # Ask to continue
#    exit 2
#fi

# Mount image locally - might use later
#install -d /mnt/$FN
#install -d /mnt/$FN.disk
#ewfmount $INPATH /mnt/$FN 2>/dev/null
#mount -o ro,loop /mnt/$FN/ewf1 /mnt/$FN.disk

NOW=$(date)
echo "$NOW: Creating case structure" | tee -a "$LOG"
# Extract based on EnScript
# Make case structure
install -d $OUTPATH/01.REG
install -d $OUTPATH/02.WEB
install -d $OUTPATH/03.DOC
install -d $OUTPATH/04.MAIL
install -d $OUTPATH/05.COMPRESSED
install -d $OUTPATH/06.PHONE
install -d $OUTPATH/07.DATABASE
install -d $OUTPATH/08.IMAGE
install -d $OUTPATH/09.WIN_LOG
install -d $OUTPATH/10.FILESYS
install -d $OUTPATH/11.ETC

install -d $OUTPATH/xTemp
install -d $OUTPATH/xTSK

NOW=$(date)
echo "$NOW: Start recovering data with TSK_recover to $OUTPATH/xTSK" | tee -a "$LOG"
tsk_recover $INPATH $OUTPATH/xTSK 2>&1>/dev/null &

# Function to check the artifact category
CATEGORY=""
function checkCat {
    # Check the category of the matching file
    for cats in $(ls categories/*); do
        echo "$1|" | grep -i -f $cats &>/dev/null
        if [ $? -eq 0 ]; then
            CATEGORY=$(basename $cats)
            echo "Detected category is $CATEGORY"
            break
        fi
    done
}

# Function for basic carving with icat
function icat_carve {
  # Offset sent as $1
  # Extract interesting files to their correct folder
  for file in $(cat $1); do
    FNAME=$(echo $file | awk -F"|" '{print $2}')
    BNAME=$(basename $FNAME)
    INODE=$(echo $file | awk -F"|" '{print $3}')
    checkCat $FNAME
    # Carve with sleuthkit
    RAND=$(uuidgen | tail -c 6)
    if [ $2 ]; then
        icat -R -o $2 $INPATH $INODE > "$OUTPATH/$CATEGORY/$RAND-$INODE-$BNAME"
    else
        icat -R $INPATH $INODE > "$OUTPATH/$CATEGORY/$RAND-$INODE-$BNAME"
    fi
  done
}

NOW=$(date)
echo "$NOW: Searching disk for files in 'artifacts.list'" | tee -a "$LOG"

NOW=$(date)
mmls $INPATH &>/dev/null
if [ "$?" == "1" ]; then
    echo "$NOW: The disk appears to be a logical partition" | tee -a "$LOG"
    tmpArtifacts=$(mktemp $OUTPATH/xTemp/temp.XXXXXXXXXX)
    NOW=$(date)
    echo "$NOW: Saving interesting files in $tmpArtifacts" | tee -a "$LOG"
    fls -rp -m / $INPATH 2>/dev/null | sed 's/ (deleted)//' | grep -i -f categories/artifacts.list | sed 's/ /_/g' >> $tmpArtifacts
    icat_carve $tmpArtifacts
else
    echo "$NOW: The disk appears to be a physical image" | tee -a "$LOG"
    for offset in $(mmls $INPATH | tail -n +6 | awk '{print $3}'); do
         tmpArtifacts=$(mktemp $OUTPATH/xTemp/$offset.XXXXXXXXXX)
         NOW=$(date)
         echo "$NOW: Saving interesting files in $tmpArtifacts" | tee -a "$LOG"
         fls -rp -m / $INPATH -o $offset 2>/dev/null | sed 's/ (deleted)//' | grep -i -f categories/artifacts.list | sed 's/ /_/g' >> $tmpArtifacts
         icat_carve $tmpArtifacts $offset
    done
fi


# Wait for TSK recover to finish
if [ $(pgrep -x tsk_recover) ]; then
    while [ true ]; do
        if [ "$(pgrep -x tsk_recover)" == "" ]; then
           NOW=$(date)
           echo "$NOW: TSK_recover has finished" | tee -a "$LOG"
           break
        else
           echo "Waiting for tsk_recover to finish"
           sleep 5
        fi
    done
fi

# Hash everything
NOW=$(date)
echo "$NOW: Hashing all extracted files to hashes.list" | tee -a "$LOG"
hashdeep -r "$OUTPATH" > "$OUTPATH/hashes.list"

# Wait for other processes to quit
if [ $(pgrep -x ewfverify) ] || [ $(pgrep -x hashdeep) ]; then
    while [ true ]; do
        if [ "$(pgrep -x ewfverify)" == "" ] && [ "$(pgrep -x hashdeep)" == "" ]; then
           NOW=$(date)
           echo "$NOW: All hashing has finished" | tee -a "$LOG"
           break
        else
           echo "Waiting for hashing to finish"
           sleep 5
        fi
    done
fi

NOW=$(date)
echo "$NOW: All processing completed" | tee -a "$LOG"

chown -R jekyll "$OUTPATH"
chmod -R 774 "$OUTPATH"
