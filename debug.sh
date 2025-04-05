#!/bin/bash

# Stop any existing containers
echo "Stopping any existing evs-processor containers..."
docker stop evs-processor-container 2>/dev/null
docker rm evs-processor-container 2>/dev/null

# Build the Docker image
echo "Building Docker image..."
docker build -t evs-processor .

# Run the container with debugging enabled
echo "Starting container with debug mode..."
docker run -d -p 8080:8080 --name evs-processor-container evs-processor

# Wait for container to start
echo "Waiting for container to start..."
sleep 5

# Test package loading
echo "Testing R package loading..."
docker exec -it evs-processor-container Rscript package_test.R

# Check if all files are in place
echo "Checking file locations and permissions..."
docker exec -it evs-processor-container ls -la /app

# Test health endpoint
echo "Testing health endpoint..."
curl -s http://localhost:8080/health | jq .

# Test debug endpoint
echo "Testing debug endpoint..."
curl -s http://localhost:8080/debug | jq .

# Show container logs
echo "Container logs:"
docker logs evs-processor-container

echo "Debug complete. Container is running at http://localhost:8080"
echo "You can enter the container with: docker exec -it evs-processor-container /bin/bash"