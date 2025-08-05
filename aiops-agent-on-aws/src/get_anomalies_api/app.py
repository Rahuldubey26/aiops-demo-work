import os
import json
import boto3
from decimal import Decimal

# Custom JSON encoder to handle DynamoDB's Decimal type
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

dynamodb = boto3.resource('dynamodb')
DYNAMODB_TABLE_NAME = os.environ['DYNAMODB_TABLE_NAME']
table = dynamodb.Table(DYNAMODB_TABLE_NAME)

def lambda_handler(event, context):
    try:
        # Scan the table to get all anomalies
        response = table.scan()
        items = response.get('Items', [])
        
        # Sort by timestamp descending
        sorted_items = sorted(items, key=lambda x: x['timestamp'], reverse=True)

        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*', # WARNING: Restrict in production
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'GET,OPTIONS'
            },
            'body': json.dumps(sorted_items, cls=DecimalEncoder)
        }
    except Exception as e:
        print(f"Error fetching anomalies: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Could not fetch anomalies'})
        }