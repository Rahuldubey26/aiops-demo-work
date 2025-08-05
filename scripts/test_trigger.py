import subprocess
import argparse
import boto3

def get_instance_ip(instance_id, region):
    ec2 = boto3.client('ec2', region_name=region)
    response = ec2.describe_instances(InstanceIds=[instance_id])
    return response['Reservations'][0]['Instances'][0]['PublicIpAddress']

def main(instance_id, region, key_file):
    """
    Connects to the EC2 instance via SSH and runs a command to spike the CPU.
    This requires the 'stress' utility to be installed on the EC2 instance.
    You can install it by SSHing in and running: `sudo amazon-linux-extras install epel -y && sudo yum install stress -y`
    """
    try:
        ip_address = get_instance_ip(instance_id, region)
        print(f"Found public IP: {ip_address}")
        
        ssh_user = "ec2-user"
        ssh_command = f"ssh -i {key_file} -o StrictHostKeyChecking=no {ssh_user}@{ip_address}"
        
        # This command will max out 1 CPU core for 10 minutes (2x 5-min detection cycles)
        stress_command = "'stress --cpu 1 --timeout 600'"
        
        full_command = f"{ssh_command} {stress_command}"
        
        print(f"Running command to spike CPU: {full_command}")
        subprocess.run(full_command, shell=True, check=True)
        print("CPU stress test initiated successfully on the instance.")
        
    except Exception as e:
        print(f"An error occurred: {e}")
        print("Please ensure:")
        print("1. Your AWS credentials and region are correct.")
        print("2. The instance ID is correct and the instance is running.")
        print(f"3. You have SSH access to the instance using the key file: {key_file}")
        print("4. The 'stress' utility is installed on the EC2 instance.")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Trigger High CPU on Target EC2")
    parser.add_argument("--instance-id", required=True, help="ID of the EC2 instance")
    parser.add_argument("--region", required=True, help="AWS Region of the instance")
    parser.add_argument("--key-file", required=True, help="Path to the SSH private key (.pem) for the instance")
    args = parser.parse_args()
    
    main(args.instance_id, args.region, args.key_file)