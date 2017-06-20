#!/bin/bash

if [ ! "$(jps | grep Elasticsearch)" ]; then
    #echo "I: Elasticsearch already running"
#else
    echo "I: Elasticsearch not running"
    exit 1
fi
curl -XPOST 'localhost:9200/exhibit/_search?q="$1"'
