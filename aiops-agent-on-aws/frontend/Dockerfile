FROM python:3.9-slim

WORKDIR /app

# Copy requirements and install
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy the Streamlit app code
COPY app.py ./

# Expose the port Streamlit runs on
EXPOSE 8501

# Healthcheck to ensure the app is running correctly
HEALTHCHECK CMD streamlit hello

# Command to run the Streamlit app
ENTRYPOINT ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]