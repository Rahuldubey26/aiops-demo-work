import os
import json
import boto3
import uuid
from datetime import datetime, timedelta

# Initialize clients
logs = boto3.client('logs')
sns = boto3.client('sns')
dynamodb = boto3.resource('dynamodb')

# Environment variables
CRITICAL_SNS_TOPIC_ARN = os.environ['CRITICAL_SNS_TOPIC_ARN']
DYNAMODB_TABLE_NAME = os.environ['DYNAMODB_TABLE_NAME']
table = dynamodb.Table(DYNAMODB_TABLE_NAME)

# Keywords to search for in logs, indicating a potential root cause
ERROR_KEYWORDS = ['error', 'failed', 'critical', 'exception', 'timeout', 'denied']

def find_log_stream_for_instance(instance_id):
    """A simplified method to find a log group. Assumes a convention."""
    # In a real-world scenario, you might use instance tags or a more robust naming convention.
    # This example assumes a log group is named based on the instance ID.
    # For Amazon Linux, logs are often in /var/log/messages, configured to ship to a log group.
    # This part requires you to have the CloudWatch Agent set up on your EC2.
    # For now, we'll assume a placeholder log group name.
    return f"/{instance_id}/var/log/messages"

def analyze_logs(instance_id, anomaly_timestamp, window_minutes=5):
    """Searches CloudWatch Logs for error keywords around the time of an anomaly."""
    log_group_name = find_log_stream_for_instance(instance_id)
    
    end_time = int(anomaly_timestamp.timestamp() * 1000)
    start_time = int((anomaly_timestamp - timedelta(minutes=window_minutes)).timestamp() * 1000)

    try:
        response = logs.filter_log_events(
            logGroupName=log_group_name,
            startTime=start_time,
            endTime=end_time,
            filterPattern='?'.join(ERROR_KEYWORDS) # ? makes it an OR search
        )
        
        findings = [event['message'] for event in response['events']]
        return findings

    except logs.exceptions.ResourceNotFoundException:
        print(f"Log group '{log_group_name}' not found for instance {instance_id}.")
        return []
    except Exception as e:
        print(f"Error querying logs for {instance_id}: {e}")
        return []

def lambda_handler(event, context):
    message_body = json.loads(event['Records'][0]['Sns']['Message'])
    
    instance_id = message_body['instance_id']
    anomaly_timestamp_str = message_body['timestamp']
    anomaly_timestamp = datetime.fromisoformat(anomaly_timestamp_str)
    
    print(f"Analyzing logs for anomaly on instance {instance_id} at {anomaly_timestamp_str}")
    
    log_findings = analyze_logs(instance_id, anomaly_timestamp)
    
    # --- Noise Reduction and RCA ---
    # If we found relevant log entries, we consider the alert critical.
    # Otherwise, it might be a transient spike (noise), so we don't escalate.
    is_critical = len(log_findings) > 0
    
    # Store all detected anomalies in DynamoDB for the frontend
    anomaly_id = str(uuid.uuid4())
    item_to_store = {
        'id': anomaly_id,
        'instance_id': instance_id,
        'timestamp': anomaly_timestamp_str,
        'metric': message_body['metric'],
        'value': str(message_body['value']),
        'is_critical': is_critical,
        'rca_findings': log_findings[:5] # Store up to 5 relevant log lines
    }
    table.put_item(Item=item_to_store)
    
    if is_critical:
        print(f"CRITICAL event confirmed for {instance_id}. Found {len(log_findings)} related log entries. Escalating.")
        
        # Enrich the message with RCA findings before publishing
        critical_message = {
            'original_anomaly': message_body,
            'rca': {
                'analysis': 'Log analysis found potential error indicators.',
                'findings': log_findings[:5]
            },
            'remediation_target': {
                'type': 'EC2_INSTANCE',
                'id': instance_id,
                'action': 'REBOOT' # This can be made more dynamic
            }
        }
        
        sns.publish(
            TopicArn=CRITICAL_SNS_TOPIC_ARN,
            Message=json.dumps(critical_message),
            Subject=f"CRITICAL Alert: {message_body['anomaly_type']} on {instance_id}"
        )
    else:
        print(f"Event for {instance_id} not critical. No relevant logs found. Suppressing escalation.")
        
    return {'statusCode': 200, 'body': 'Analysis complete.'}