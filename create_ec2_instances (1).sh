#!/bin/bash

# Variables
INSTANCE_TYPE="t2.micro" # Free-tier eligible instance type
REGION="us-west-1" # AWS region for Mumbai
IMAGE_ID="ami-0ecaad63ed3668fca" # Ubuntu Server 22.04 LTS AMI ID for Mumbai (64-bit x86)
KEY_NAME="vivek-key" # Desired key name
SECURITY_GROUP_NAME="my-security-group" # Desired security group name
NUM_INSTANCES=3 # Number of instances to create

# Create the key pair if it does not exist
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" &> /dev/null; then
    echo "Creating new key pair: $KEY_NAME"
    aws ec2 create-key-pair --key-name "$KEY_NAME" --region "$REGION" --query 'KeyMaterial' --output text > ~/Downloads/"$KEY_NAME.pem"
    chmod 400 ~/Downloads/"$KEY_NAME.pem"
    echo "Key pair created and saved to ~/Downloads/$KEY_NAME.pem"
    
    # Wait for key pair to propagate
    echo "Waiting for key pair to propagate in AWS..."
    sleep 5 # Give it some time to propagate
else
    echo "Key pair '$KEY_NAME' already exists, skipping creation."
fi

# Create security group if it doesn't exist
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filter Name=group-name,Values="$SECURITY_GROUP_NAME" --query "SecurityGroups[0].GroupId" --output text --region "$REGION")
if [ "$SECURITY_GROUP_ID" == "None" ]; then
    echo "Creating new security group: $SECURITY_GROUP_NAME"
    SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name "$SECURITY_GROUP_NAME" --description "Security group for SSH" --query 'GroupId' --output text --region "$REGION")
    aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$REGION"
    echo "Security group $SECURITY_GROUP_NAME created with SSH access."
else
    echo "Security group $SECURITY_GROUP_NAME already exists, using $SECURITY_GROUP_ID."
fi

# Get default subnet
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=default-for-az,Values=true" --query "Subnets[0].SubnetId" --output text --region "$REGION")
echo "Using default subnet: $SUBNET_ID"

# Loop to create multiple EC2 instances
for i in $(seq 1 "$NUM_INSTANCES"); do
    INSTANCE_NAME="MyInstance$i"
    INSTANCE_ID=$(aws ec2 run-instances \
      --image-id "$IMAGE_ID" \
      --count 1 \
      --instance-type "$INSTANCE_TYPE" \
      --key-name "$KEY_NAME" \
      --security-group-ids "$SECURITY_GROUP_ID" \
      --subnet-id "$SUBNET_ID" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
      --query "Instances[0].InstanceId" \
      --output text --region "$REGION")

    if [ -z "$INSTANCE_ID" ]; then
        echo "Error: Failed to create instance $INSTANCE_NAME. Exiting."
        exit 1
    fi

    echo "Instance $INSTANCE_NAME created with Instance ID: $INSTANCE_ID"
done

# Wait for instances to be running
echo "Waiting for instances to be in running state..."
aws ec2 wait instance-running --instance-ids $(aws ec2 describe-instances --filters "Name=tag:Name,Values=MyInstance*" --query "Reservations[*].Instances[*].InstanceId" --output text --region "$REGION")
echo "Instances are now running."

# Get public IP addresses of the instances
echo "Fetching public IPs of instances..."
aws ec2 describe-instances --filters "Name=tag:Name,Values=MyInstance*" --query "Reservations[*].Instances[*].[InstanceId,PublicIpAddress]" --output table --region "$REGION"

echo "All instances are created successfully and SSH-ready."
echo "You can access them using the following SSH command:"
for PUBLIC_IP in $(aws ec2 describe-instances --filters "Name=tag:Name,Values=MyInstance*" --query "Reservations[*].Instances[*].PublicIpAddress" --output text --region "$REGION"); do
    echo "ssh -i ~/Downloads/$KEY_NAME.pem ubuntu@$PUBLIC_IP"
done

