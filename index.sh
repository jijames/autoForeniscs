#!/bin/bash

#if [[ $EUID -ne 0 ]]; then
#   echo "This script must be run as root" 1>&2
#   exit 1
#fi

# Automated disk extraction and indexing script
# Version: 0.0.1-2017-06-10
# Required packages: uuidgen, sleuthkit, ewf-tools, hashdeep, Tika, elasticsearch, parallel
# Created by Joshua I. James (joshua.i.james@hallym.ac.kr)
# Legal Informatics and Forensic Science Institute, Hallym University

# TODO:
# Pull imaging settings from case settings

if [ ! -f "./tika-app.jar" ]; then
    echo "Tika not found. Downloading..."
    wget http://apache.mirror.cdnetworks.com/tika/tika-app-1.15.jar -O tika-app.jar
fi
if [ ! -f "./elasticsearch-5.4.1/bin/elasticsearch" ]; then
     echo "Elasticsearch not found. Downloading..."
     wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-5.4.1.tar.gz
     tar -xf elasticsearch-5.4.1.tar.gz
     rm -r elasticsearch-5.4.1.tar.gz
     sudo chown -R elasticsearch:elasticsearch elasticsearch-5.4.1
     sudo chmod -R 777 elasticsearch-5.4.1
fi

TEMP=$(mktemp /tmp/temp.XXXXXX)

function clean_up {
    echo "Exiting..."
    rm -r "$TEMP" &>/dev/null
    rm -r /tmp/SEARCH.* &>/dev/null
    exit 1
}

trap clean_up SIGHUP SIGINT SIGTERM

echo "What is the exhibit number (computer number) being indexed?"
read EXNUM

echo "Please enter the directory to index..."
read -e SRCDIR
if [ -d "$SRCDIR" ]; then
    echo "Source directory found"
else
    echo "Source directory does not exist"
    exit 1
fi

echo "Please enter the content extraction directory (should be as large as the disk image)"
read -e OUTDIR
if [ -d "$OUTDIR" ]; then
    echo "Output directory found - make sure this directory is empty"
else
    echo "Output directory does not exist, create now (y/N)"
    read CHECK
    if [ "$CHECK" == "y" ] || [ "$CHECK" =="Y" ]; then
        install -d "$OUTDIR"
    else
        echo "No output directory. Exiting..."
        exit 1
    fi
fi

if [ "$(jps | grep Elasticsearch)" ]; then
    echo "I: Elasticsearch already running"
else
    echo "I: Starting elasticsearch"]
    elasticsearch-5.4.1/bin/elasticsearch &> /dev/null &
fi

echo "Starting text extraction and OCR..."
java -jar tika-app.jar -J -i "$SRCDIR" -o "$OUTDIR" 2>/dev/null

echo "Checking if elasticsearch has stated, exit with ctrl-c"
X="100"
while [ "$X" != "0" ]; do
    sleep 0.5
    curl localhost:9200 &> /dev/null
    X="$?"
done
echo "Detected elasticsearch, sending extracted text for indexing"
if [ "$EXNUM" == "" ]; then
    EXNUM=$(shuf -i1000-9999 -n1)
fi

function addFileSearch {
    echo "Adding file: $1"
    T=$(mktemp /tmp/SEARCH.XXXXXXXX)
    cat "$1" | sed 's/^\[//' | sed 's/]$//' | sed 's/},{/,/g' > "$T"
    N=$(basename "$1")
    curl -XPOST "localhost:9200/exhibits/$2/$N" -H 'Content-Type: application/json' --data-binary "@$T" 2>/dev/null
    rm -r "$T"
}
export -f addFileSearch

# NOT PARALLEL
#for f in $(find "$OUTDIR" -type f); do
    # Format output for elasticsearch indexing
    #cat "$f" | sed 's/^\[//' | sed 's/]$//' | sed 's/},{/,/g' > "$TEMP"
    #N=$(basename "$f")
    #echo "Adding file to index: $N"
    #sem -j10 curl -XPOST "localhost:9200/exhibits/$EXNUM/$N" -H 'Content-Type: application/json' --data-binary @$TEMP
#done

find "$OUTDIR" -type f | parallel --env addFileSearch --jobs 500% addFileSearch {} "$EXNUM"
echo "Done"

clean_up
