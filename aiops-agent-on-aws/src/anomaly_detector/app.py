# aiops-agent-on-aws/src/anomaly_detector/app.py

import os
import json
import boto3
import joblib
import numpy as np
from datetime import datetime, timedelta

# Initialize clients
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')
ec2 = boto3.client('ec2')

# Environment variables
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
MODEL_PATH = os.environ['MODEL_PATH']
RESOURCE_TAG_KEY = os.environ.get('RESOURCE_TAG_KEY', 'Monitored')
RESOURCE_TAG_VALUE = os.environ.get('RESOURCE_TAG_VALUE', 'true')

# Load the pre-trained model
try:
    model = joblib.load(MODEL_PATH)
except FileNotFoundError:
    print(f"Warning: Model file not found at {MODEL_PATH}. Anomaly detection will be skipped.")
    model = None

def get_monitored_instances():
    """Gets all EC2 instances with the specified monitoring tag."""
    paginator = ec2.get_paginator('describe_instances')
    pages = paginator.paginate(
        Filters=[
            {'Name': f'tag:{RESOURCE_TAG_KEY}', 'Values': [RESOURCE_TAG_VALUE]},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
    )
    instance_ids = []
    for page in pages:
        for reservation in page['Reservations']:
            for instance in reservation['Instances']:
                instance_ids.append(instance['InstanceId'])
    return instance_ids

def get_cpu_utilization(instance_id, period_minutes=5, window_minutes=30):
    """Fetches CPU utilization metrics for a given instance."""
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(minutes=window_minutes)
    
    response = cloudwatch.get_metric_data(
        MetricDataQueries=[
            {
                'Id': 'm1',
                'MetricStat': {
                    'Metric': {
                        'Namespace': 'AWS/EC2',
                        'MetricName': 'CPUUtilization',
                        'Dimensions': [{'Name': 'InstanceId', 'Value': instance_id}]
                    },
                    'Period': period_minutes * 60,
                    'Stat': 'Average',
                },
                'ReturnData': True,
            },
        ],
        StartTime=start_time,
        EndTime=end_time,
        ScanBy='TimestampDescending'
    )
    return response['MetricDataResults'][0]['Timestamps'], response['MetricDataResults'][0]['Values']

def lambda_handler(event, context):
    if not model:
        print("Model is not loaded. Exiting.")
        return {'statusCode': 500, 'body': 'Model not loaded'}

    instance_ids = get_monitored_instances()
    print(f"Found {len(instance_ids)} monitored instances: {instance_ids}")

    for instance_id in instance_ids:
        timestamps, values = get_cpu_utilization(instance_id)
        
        if not values:
            print(f"No CPU metric data for instance {instance_id}")
            continue

        # Use the latest metric point for anomaly detection
        latest_value = values[0]
        latest_timestamp = timestamps[0].isoformat()
        
        # Reshape data for scikit-learn model
        data_point = np.array([latest_value]).reshape(-1, 1)
        prediction = model.predict(data_point)
        
        # -1 indicates an anomaly
        if prediction[0] == -1:
            print(f"ANOMALY DETECTED for instance {instance_id}: CPU is {latest_value:.2f}%")
            
            message = {
                'instance_id': instance_id,
                'metric': 'CPUUtilization',
                'value': latest_value,
                'timestamp': latest_timestamp,
                'anomaly_type': 'High CPU Utilization'
            }
            
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Message=json.dumps(message),
                Subject=f"Anomaly Detected on {instance_id}"
            )

    return {'statusCode': 200, 'body': 'Detection cycle complete.'}