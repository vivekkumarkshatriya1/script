#!/bin/bash

# Define variables
ACCESS_KEY="xyz"
SECRET_KEY="xyz"
BUCKET_NAME="vivekvmukti"
MOUNT_DIR="/home/ubuntu/s3bucket"
S3_REGION="ap-south-1"  # S3 region is now ap-south-1 (Mumbai)

# Install necessary packages
echo "Updating packages and installing s3fs..."
if command -v apt-get &>/dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y s3fs
else
    echo "Unsupported package manager. Exiting."
    exit 1
fi

# Configure AWS credentials for s3fs
echo "Configuring AWS credentials..."
echo "$ACCESS_KEY:$SECRET_KEY" > ~/.passwd-s3fs
chmod 600 ~/.passwd-s3fs

# Create the mount directory if it doesn't exist
echo "Creating mount directory at $MOUNT_DIR..."
sudo mkdir -p $MOUNT_DIR

# Mount the S3 bucket
echo "Mounting S3 bucket $BUCKET_NAME to $MOUNT_DIR..."
sudo s3fs $BUCKET_NAME $MOUNT_DIR -o passwd_file=~/.passwd-s3fs -o allow_other -o url=https://s3.$S3_REGION.amazonaws.com -o use_path_request_style

# Check if the mount was successful
if mount | grep "$MOUNT_DIR" > /dev/null; then
    echo "S3 bucket mounted successfully at $MOUNT_DIR!"
else
    echo "Failed to mount S3 bucket."
    exit 1
fi

# Add to /etc/fstab for persistence on reboot
echo "Adding S3 bucket to /etc/fstab for automatic mounting after reboot..."
echo "s3fs#$BUCKET_NAME $MOUNT_DIR fuse _netdev,passwd_file=/home/ubuntu/.passwd-s3fs,allow_other,use_path_request_style,url=https://s3.$S3_REGION.amazonaws.com 0 0" | sudo tee -a /etc/fstab

echo "Setup complete!"

