import os
import streamlit as st
import boto3
import pandas as pd
from datetime import datetime
import time
from decimal import Decimal

# --- Page Configuration ---
st.set_page_config(
    page_title="AIOps Monitoring Dashboard",
    page_icon="🤖",
    layout="wide",
)

# --- AWS Configuration ---
# App Runner injects these standard environment variables
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
# We will pass this env var via Terraform
DYNAMODB_TABLE_NAME = os.environ.get("DYNAMODB_TABLE_NAME")

# --- Functions ---
@st.cache_data(ttl=60) # Cache data for 60 seconds
def get_dynamodb_table():
    """Initializes and returns the DynamoDB table object."""
    if not DYNAMODB_TABLE_NAME:
        return None
    dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
    return dynamodb.Table(DYNAMODB_TABLE_NAME)

@st.cache_data(ttl=30)
def fetch_anomalies(_table):
    """Fetches all anomalies from the DynamoDB table."""
    try:
        response = _table.scan()
        items = response.get('Items', [])
        # Handle pagination if necessary for very large datasets
        while 'LastEvaluatedKey' in response:
            response = _table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            items.extend(response.get('Items', []))
        return items
    except Exception as e:
        st.error(f"Error connecting to DynamoDB: {e}")
        return []

def style_critical(row):
    """Applies a background color to rows that are critical."""
    return ['background-color: #ffebee'] * len(row) if row.is_critical else [''] * len(row)

# --- UI Layout ---
st.title("🤖 AIOps Monitoring Dashboard")

# Check for table configuration
table = get_dynamodb_table()
if not table:
    st.error("FATAL: `DYNAMODB_TABLE_NAME` environment variable is not set.")
    st.stop()

# Create a placeholder for live updates
placeholder = st.empty()

# --- Main Application Logic ---
while True:
    anomalies = fetch_anomalies(table)

    with placeholder.container():
        if not anomalies:
            st.warning("No anomaly events detected yet. The system is monitoring...")
        else:
            # --- Data Processing ---
            df = pd.DataFrame(anomalies)

            # Convert Decimal to float and format columns
            for col in ['value']:
                if col in df.columns:
                    df[col] = df[col].apply(lambda x: float(x) if isinstance(x, Decimal) else x)
            
            df['timestamp'] = pd.to_datetime(df['timestamp']).dt.tz_localize(None)
            df = df.sort_values(by="timestamp", ascending=False)
            
            # --- Metrics ---
            total_events = len(df)
            critical_events = df['is_critical'].sum()

            kpi1, kpi2, kpi3 = st.columns(3)
            kpi1.metric(label="Total Events Detected", value=total_events)
            kpi2.metric(label="Critical Events (RCA Confirmed)", value=int(critical_events), delta=int(critical_events), delta_color="inverse")
            kpi3.metric(label="Last Event Time (UTC)", value=df['timestamp'].max().strftime("%H:%M:%S"))

            # --- Display DataFrame ---
            st.subheader("Live Event Log")
            
            # Reorder columns for better readability
            display_columns = ['timestamp', 'instance_id', 'metric', 'value', 'is_critical', 'rca_findings']
            df_display = df[[col for col in display_columns if col in df.columns]]
            
            # Format value column
            if 'value' in df_display.columns:
                 df_display['value'] = df_display['value'].map('{:,.2f}'.format)


            st.dataframe(
                df_display.style.apply(style_critical, axis=1),
                use_container_width=True,
                hide_index=True
            )

    time.sleep(15) # Refresh interval in seconds