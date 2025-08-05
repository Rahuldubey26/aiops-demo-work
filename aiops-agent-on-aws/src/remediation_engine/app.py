import os
import json
import boto3

ec2 = boto3.client('ec2')

def reboot_instance(instance_id):
    """Reboots a given EC2 instance."""
    print(f"Attempting to reboot instance: {instance_id}")
    try:
        ec2.reboot_instances(InstanceIds=[instance_id])
        print(f"Successfully initiated reboot for {instance_id}")
        return True
    except Exception as e:
        print(f"Error rebooting instance {instance_id}: {e}")
        return False

def lambda_handler(event, context):
    message = json.loads(event['Records'][0]['Sns']['Message'])
    remediation_info = message.get('remediation_target')
    
    if not remediation_info:
        print("No remediation target found in the message.")
        return {'statusCode': 400, 'body': 'Bad message format'}

    target_type = remediation_info.get('type')
    target_id = remediation_info.get('id')
    action = remediation_info.get('action')

    print(f"Received remediation request: Action '{action}' on {target_type} '{target_id}'")

    if target_type == 'EC2_INSTANCE' and action == 'REBOOT':
        reboot_instance(target_id)
    else:
        print(f"Unsupported remediation action '{action}' for type '{target_type}'. No action taken.")

    return {'statusCode': 200, 'body': 'Remediation attempted.'}