#!/bin/bash

# Define base stream URL and the source file for streaming
BASE_URL="rtmp://ssh -i "Harsh.pem" ubuntu@3.6.87.106:80/live-record/test"
SOURCE_FILE="PNJB-000199-PBPTZ.flv"

# Number of streams to create
STREAM_COUNT=500

# Loop through and create 500 fake streams
for i in $(seq 1 $STREAM_COUNT)
do
  # Construct stream key for each stream
  STREAM_KEY="sagar_$i"
  
  # Start ffmpeg streaming in the background
  ffmpeg -stream_loop -1 -re -i $SOURCE_FILE -vcodec copy -acodec copy -f flv "$BASE_URL/$STREAM_KEY" &
  
  # Optional: Add a sleep to avoid overwhelming the server
  sleep 0.1
done

# Wait for all background processes to finish (optional)
wait
