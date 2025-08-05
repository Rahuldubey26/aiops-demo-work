# scripts/create_dummy_model.py
import joblib
import numpy as np
from sklearn.ensemble import IsolationForest
import os

print("--- Creating a dummy AIOps model ---")

# 1. Create some simple, fake data
# This simulates what the real script would get from CloudWatch
dummy_data = np.array([0.5, 0.6, 0.4, 0.55, 0.62, 0.58]).reshape(-1, 1)
print(f"Created fake data with {len(dummy_data)} points.")

# 2. Create and train a basic Isolation Forest model
model = IsolationForest(n_estimators=10, random_state=42)
model.fit(dummy_data)
print("Dummy model trained successfully.")

# 3. Define the output path for the model
# It must be saved to ../src/anomaly_detector/model.joblib
output_path = os.path.join("..", "src", "anomaly_detector", "model.joblib")
output_dir = os.path.dirname(output_path)

# Ensure the destination directory exists
if not os.path.exists(output_dir):
    os.makedirs(output_dir)
    print(f"Created directory: {output_dir}")

# 4. Save the trained model to the correct location
joblib.dump(model, output_path)
print(f"\nSUCCESS: Model saved to {output_path}")
print("\nYou can now commit the 'model.joblib' file.")