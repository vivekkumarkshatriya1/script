#!/bin/bash

# Variables
INSTANCE_TYPE="t2.micro" # Free-tier eligible instance type
REGION="ap-south-1" # AWS region (modify if needed)
IMAGE_ID="ami-08c40ec9ead489470" # Ubuntu 22.04 LTS AMI ID for us-east-1 (replace for other regions)
KEY_NAME="vivek-key" # Replace with desired key name
SECURITY_GROUP_NAME="my-security-group" # Replace with desired security group name
SUBNET_ID="" # Optional: Leave empty to use default VPC
NUM_INSTANCES=3 # Number of instances to create

# Function to check if key pair exists in AWS
check_key_pair() {
    aws ec2 describe-key-pairs --key-names $KEY_NAME --region $REGION &> /dev/null
    return $?
}

# Create the key pair if it does not exist
if ! check_key_pair; then
    echo "Creating new key pair: $KEY_NAME"
    aws ec2 create-key-pair --key-name $KEY_NAME --region $REGION --query 'KeyMaterial' --output text > ~/Downloads/$KEY_NAME.pem
    chmod 400 ~/Downloads/$KEY_NAME.pem
    echo "Key pair created and saved to ~/Downloads/$KEY_NAME.pem"

    # Wait for key pair to propagate
    echo "Waiting for key pair to propagate in AWS..."
    sleep 10

    # Verify if the key pair now exists
    if ! check_key_pair; then
        echo "Error: Key pair '$KEY_NAME' not found after creation. Exiting."
        exit 1
    else
        echo "Key pair '$KEY_NAME' successfully verified."
    fi
else
    echo "Key pair '$KEY_NAME' already exists, skipping creation."
fi

# Check if security group exists
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filter Name=group-name,Values=$SECURITY_GROUP_NAME --query "SecurityGroups[0].GroupId" --output text --region $REGION)
if [ "$SECURITY_GROUP_ID" == "None" ]; then
    echo "Creating new security group: $SECURITY_GROUP_NAME"
    SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name $SECURITY_GROUP_NAME --description "Security group for SSH" --query 'GroupId' --output text --region $REGION)
    
    # Add SSH rule to security group
    aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION
    echo "Security group $SECURITY_GROUP_NAME created with SSH access."
else
    echo "Security group $SECURITY_GROUP_NAME already exists, using $SECURITY_GROUP_ID."
fi

# Get default subnet if SUBNET_ID is not provided
if [ -z "$SUBNET_ID" ]; then
    SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=default-for-az,Values=true" --query "Subnets[0].SubnetId" --output text --region $REGION)
    echo "Using default subnet: $SUBNET_ID"
fi

# Loop to create multiple EC2 instances
INSTANCE_IDS=()
for i in $(seq 1 $NUM_INSTANCES); do
    INSTANCE_NAME="MyInstance$i"
    INSTANCE_ID=$(aws ec2 run-instances \
      --image-id $IMAGE_ID \
      --count 1 \
      --instance-type $INSTANCE_TYPE \
      --key-name $KEY_NAME \
      --security-group-ids $SECURITY_GROUP_ID \
      --subnet-id $SUBNET_ID \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
      --query "Instances[0].InstanceId" \
      --output text --region $REGION)

    # Check if instance was successfully created
    if [ -z "$INSTANCE_ID" ]; then
        echo "Error: Failed to create instance $INSTANCE_NAME. Exiting."
        exit 1
    fi

    INSTANCE_IDS+=($INSTANCE_ID)
    echo "Instance $INSTANCE_NAME created with Instance ID: $INSTANCE_ID"
done

# Wait for instances to be running
echo "Waiting for instances to be in running state..."
aws ec2 wait instance-running --instance-ids ${INSTANCE_IDS[@]} --region $REGION
echo "Instances are now running."

# Get and display the public IP addresses of the new instances
echo "Fetching public IPs of instances..."
aws ec2 describe-instances --instance-ids ${INSTANCE_IDS[@]} --query "Reservations[*].Instances[*].[InstanceId,PublicIpAddress]" --output table --region $REGION

echo "All instances are created successfully and SSH-ready."
echo "You can access them using the following SSH command:"
echo "ssh -i ~/Downloads/$KEY_NAME.pem ubuntu@<Public-IP>"

