# src/anomaly_detector/Dockerfile

# 1. Start from the official AWS Lambda base image for Python 3.9.
# This image includes the Lambda Runtime Interface Client, which is required to run your code on Lambda.
FROM public.ecr.aws/lambda/python:3.9

# 2. Copy the requirements file into the image's task root.
# We do this step first to leverage Docker's layer caching. The dependencies won't be re-installed
# on every build unless the requirements.txt file itself changes, making builds faster.
COPY requirements.txt ${LAMBDA_TASK_ROOT}/

# 3. Install the Python dependencies specified in the requirements file.
RUN pip install --no-cache-dir -r requirements.txt

# 4. Copy the function code (app.py) and the trained ML model (model.joblib)
# into the root of the Lambda task directory, where they can be found by the handler.
COPY app.py ${LAMBDA_TASK_ROOT}/
COPY model.joblib ${LAMBDA_TASK_ROOT}/

# 5. Set the command that the Lambda service will run when your function is invoked.
# The format is "file_name.handler_function_name".
CMD [ "app.lambda_handler" ]