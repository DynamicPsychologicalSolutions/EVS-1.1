#!/bin/bash
set -e  # Exit on error

echo "===== Starting EVS PDF Processor Setup ====="

# Make sure Docker is installed
if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker is not installed. Please install Docker to continue."
  exit 1
fi

# Make sure the current directory contains all necessary files
echo "Checking for required files..."
required_files=("process_pdf.R" "server.py" "requirements.txt" "EVS_base_1.1.pdf" "index.html")

for file in "${required_files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "ERROR: Required file not found: $file"
    echo "Please make sure all required files are in the current directory."
    exit 1
  fi
done

echo "All required files found."

# Make the R script executable
chmod +x process_pdf.R
chmod +x test_libraries.R

# Stop and remove any existing container
echo "Cleaning up any existing containers..."
docker stop evs-processor-container 2>/dev/null || true
docker rm evs-processor-container 2>/dev/null || true

# Build the Docker image with no cache to ensure fresh package installation
echo "Building Docker image... (this may take several minutes)"
echo "This step will install all required R packages including factoextra."
docker build --no-cache -t evs-processor .

# Check if the build was successful
if [ $? -ne 0 ]; then
  echo "ERROR: Docker build failed. Please check the error messages above."
  exit 1
fi

# Run the container
echo "Starting the container..."
docker run -d -p 8080:8080 --name evs-processor-container evs-processor

# Check if the container started successfully
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to start the container. Please check the error messages above."
  exit 1
fi

# Wait for the container to start
echo "Waiting for the server to start..."
sleep 5

# Test the health endpoint
echo "Testing the server health..."
health_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health)

if [ "$health_status" -eq 200 ]; then
  echo "SUCCESS: Server is running!"
  
  # Test R library loading
  echo "Testing R library loading inside the container..."
  docker exec -it evs-processor-container Rscript test_libraries.R
  
  echo "You can now access the EVS PDF processor at: http://localhost:8080"
  echo ""
  echo "Useful commands:"
  echo "  - View server logs: docker logs evs-processor-container"
  echo "  - Stop the server: docker stop evs-processor-container"
  echo "  - Start the server again: docker start evs-processor-container"
  echo "  - Remove the container: docker rm evs-processor-container"
else
  echo "ERROR: Server is not responding correctly. Something went wrong."
  echo "View logs with: docker logs evs-processor-container"
  exit 1
fi

echo "===== Setup Complete ====="