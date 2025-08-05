# aiops-agent-on-aws/scripts/train_model.py
import boto3
import joblib
import numpy as np
from datetime import datetime, timedelta
from sklearn.ensemble import IsolationForest
from tqdm import tqdm
import argparse

def get_historical_cpu_data(instance_id, days=14):
    """Fetches up to 14 days of historical CPU data for training."""
    cloudwatch = boto3.client('cloudwatch')
    print(f"Fetching historical CPU data for instance {instance_id} for the last {days} days...")
    
    metrics = cloudwatch.get_metric_data(
        MetricDataQueries=[
            {
                'Id': 'm1',
                'MetricStat': {
                    'Metric': {
                        'Namespace': 'AWS/EC2',
                        'MetricName': 'CPUUtilization',
                        'Dimensions': [{'Name': 'InstanceId', 'Value': instance_id}]
                    },
                    'Period': 300, # 5-minute intervals
                    'Stat': 'Average',
                },
                'ReturnData': True,
            },
        ],
        StartTime=datetime.utcnow() - timedelta(days=days),
        EndTime=datetime.utcnow(),
        ScanBy='TimestampAscending'
    )
    
    return metrics['MetricDataResults'][0]['Values']

def main(instance_id, output_path):
    """Main training function."""
    # 1. Fetch data
    # In a real system, you would aggregate data from multiple stable instances.
    # Here, we use one instance for simplicity.
    cpu_data = get_historical_cpu_data(instance_id)

    if len(cpu_data) < 100:
        print("Not enough data points to train a reliable model. Exiting.")
        return

    print(f"Fetched {len(cpu_data)} data points.")
    
    # 2. Train model
    # IsolationForest is good for this as it doesn't assume a normal distribution.
    # `contamination` is the expected proportion of anomalies in the training data.
    # 'auto' is a good starting point. Adjust if you have too many/few alerts.
    model = IsolationForest(n_estimators=100, contamination='auto', random_state=42)
    
    print("Training Isolation Forest model...")
    # Reshape data for the model
    training_data = np.array(cpu_data).reshape(-1, 1)
    model.fit(training_data)
    
    print("Model training complete.")
    
    # 3. Save model
    joblib.dump(model, output_path)
    print(f"Model saved to {output_path}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Train Anomaly Detection Model")
    parser.add_argument("--instance-id", required=True, help="EC2 instance ID to pull training data from")
    parser.add_argument("--output-path", default="../src/anomaly_detector/model.joblib", help="Path to save the trained model")
    args = parser.parse_args()
    
    main(args.instance_id, args.output_path)