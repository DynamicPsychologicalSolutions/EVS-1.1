from flask import Flask, request, send_file, jsonify, render_template, render_template_string, make_response
import subprocess
import os
import tempfile
import logging
import uuid
import time
from flask_cors import CORS
from google.cloud import storage
import datetime

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__, static_folder='.')

# Configure CORS properly for your Squarespace domain
CORS(app, resources={
    r"/*": {
        "origins": ["https://www.dynamicpsych.net", "https://dynamicpsych.net", "http://www.dynamicpsych.net", "http://dynamicpsych.net"],
        "methods": ["POST", "GET", "OPTIONS"],
        "allow_headers": ["Content-Type", "Authorization"]
    }
})

# GCS configuration
BUCKET_NAME = "evs-storage"  # Replace with your actual bucket name
storage_client = storage.Client()

# Initialize the bucket
def get_bucket():
    try:
        bucket = storage_client.get_bucket(BUCKET_NAME)
        return bucket
    except Exception as e:
        logger.error(f"Error accessing bucket: {str(e)}")
        return None

@app.route("/", methods=["GET"])
def index():
    """Serve the index.html file."""
    return send_file('index.html')

@app.route("/health", methods=["GET"])
def health_check():
    """Endpoint for health checks."""
    return jsonify({"status": "healthy", "timestamp": time.time()})

@app.route("/debug", methods=["GET"])
def debug_info():
    """Provide debug information."""
    # List files in the current directory
    files = os.listdir()
    # Check if the base PDF exists
    base_pdf_exists = os.path.exists("EVS_Base_1.1.pdf")
    # Check if process_pdf.R exists and is executable
    r_script_exists = os.path.exists("process_pdf.R")
    r_script_executable = os.access("process_pdf.R", os.X_OK) if r_script_exists else False
    
    return jsonify({
        "files": files,
        "base_pdf_exists": base_pdf_exists,
        "r_script_exists": r_script_exists,
        "r_script_executable": r_script_executable,
        "working_directory": os.getcwd()
    })

# Helper function to upload a file to GCS
def upload_file_to_gcs(file_path, destination_blob_name, content_type="application/pdf"):
    """Uploads a file to the bucket."""
    try:
        # Get bucket
        bucket = get_bucket()
        if not bucket:
            logger.error("Failed to access GCS bucket")
            return False
            
        # Create blob object
        blob = bucket.blob(destination_blob_name)
        
        # Upload file
        blob.upload_from_filename(file_path, content_type=content_type)
        logger.info(f"File {file_path} uploaded to {destination_blob_name}")
        return True
    except Exception as e:
        logger.error(f"Error uploading to GCS: {str(e)}")
        return False

@app.route("/process-pdf", methods=["POST", "OPTIONS"])
def process_pdf():
    """
    Process uploaded PDF using the R script and return the processed PDF.
    Also save both input and output PDFs to Google Cloud Storage.
    """
    # Handle preflight OPTIONS request explicitly
    if request.method == "OPTIONS":
        response = make_response()
        response.headers.add("Access-Control-Allow-Origin", "*")  # During development
        response.headers.add("Access-Control-Allow-Headers", "Content-Type")
        response.headers.add("Access-Control-Allow-Methods", "POST, OPTIONS")
        response.headers.add("Access-Control-Max-Age", "3600")
        return response
        
    try:
        # Check if file was included in request
        if 'file' not in request.files:
            logger.error("No file part in the request")
            return jsonify({"error": "No file part"}), 400
        
        file = request.files['file']
        
        # Check if user submitted an empty file
        if file.filename == '':
            logger.error("No file selected")
            return jsonify({"error": "No file selected"}), 400
        
        # Check file extension
        if not file.filename.lower().endswith('.pdf'):
            logger.error(f"Invalid file type: {file.filename}")
            return jsonify({"error": "Only PDF files are accepted"}), 400
        
        # Get the original filename without path
        original_filename = os.path.basename(file.filename)
        
        # Create a unique ID for the input file to avoid conflicts
        unique_id = str(uuid.uuid4())
        
        # Create storage directory if it doesn't exist
        upload_dir = os.path.join(os.getcwd(), "uploads")
        os.makedirs(upload_dir, exist_ok=True)
        
        # Save original file with unique ID prefix to avoid conflicts
        input_path = os.path.join(upload_dir, f"input_{unique_id}_{original_filename}")
        file.save(input_path)
        
        # Create a copy with just the original filename for R script processing
        # This ensures the R script sees the correct filename
        original_input_path = os.path.join(upload_dir, original_filename)
        with open(input_path, 'rb') as src_file:
            with open(original_input_path, 'wb') as dest_file:
                dest_file.write(src_file.read())
        
        # The expected output format based on your R script pattern
        expected_output_filename = f"EVS {original_filename} Report.pdf"
        
        logger.info(f"Processing file {original_filename}")
        logger.info(f"Expecting output as: {expected_output_filename}")
        
        # Call R script with the original filename path
        logger.info(f"Running R script with command: Rscript process_pdf.R {original_input_path} {expected_output_filename}")
        process = subprocess.run(
            ["Rscript", "--verbose", "process_pdf.R", original_input_path, expected_output_filename],
            capture_output=True,
            text=True
        )
        
        # Log the output from R for debugging
        logger.info(f"R stdout: {process.stdout}")
        if process.stderr:
            logger.error(f"R stderr: {process.stderr}")
        
        # Check if the R script execution was successful
        if process.returncode != 0:
            logger.error(f"R script failed: {process.stderr}")
            return jsonify({
                "error": "PDF processing failed", 
                "details": process.stderr
            }), 500
        
        logger.info(f"R script completed processing")
        
        # Look for the output file
        expected_output_path = os.path.join(os.getcwd(), expected_output_filename)
        
        # Allow some time for the file to be generated
        attempts = 0
        while not os.path.exists(expected_output_path) and attempts < 5:
            time.sleep(1)  # Wait for a second
            attempts += 1
            logger.info(f"Waiting for output file, attempt {attempts}")
        
        # Check if output file exists
        if not os.path.exists(expected_output_path):
            logger.error(f"Output file not found at {expected_output_path}")
            # Try to look for similarly named files
            similar_files = [f for f in os.listdir() if f.startswith("EVS") and f.endswith("Report.pdf")]
            if similar_files:
                logger.info(f"Found similar files: {similar_files}")
                expected_output_path = os.path.join(os.getcwd(), similar_files[0])
                expected_output_filename = os.path.basename(expected_output_path)
            else:
                return jsonify({"error": "Output file not generated"}), 500
        
        logger.info(f"Found output file at {expected_output_path}")
        
        # Upload to Google Cloud Storage
        # Create a timestamp for organizing files
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Save the input file
        input_gcs_path = f"inputs/{timestamp}_{unique_id}/{original_filename}"
        upload_file_to_gcs(original_input_path, input_gcs_path)
        
        # Save the output file
        output_gcs_path = f"outputs/{timestamp}_{unique_id}/{expected_output_filename}"
        upload_file_to_gcs(expected_output_path, output_gcs_path)
        
        # Create metadata for easy reference
        metadata = {
            "timestamp": timestamp,
            "unique_id": unique_id,
            "original_filename": original_filename,
            "processed_filename": expected_output_filename,
            "input_path": input_gcs_path,
            "output_path": output_gcs_path
        }
        
        # Save metadata to GCS for easier indexing
        metadata_path = f"metadata/{timestamp}_{unique_id}_metadata.json"
        metadata_file = os.path.join(tempfile.gettempdir(), f"{unique_id}_metadata.json")
        
        with open(metadata_file, 'w') as f:
            import json
            json.dump(metadata, f)
        
        # Upload metadata to GCS
        upload_file_to_gcs(metadata_file, metadata_path, content_type="application/json")
        
        # Create a response with the file
        response = make_response(send_file(expected_output_path, mimetype="application/pdf"))
        response.headers["Content-Disposition"] = f'attachment; filename="{expected_output_filename}"'
        response.headers["Content-Type"] = "application/pdf"
        response.headers["X-Content-Type-Options"] = "nosniff"
        
        # Add explicit CORS headers to ensure compatibility
        response.headers["Access-Control-Allow-Origin"] = request.headers.get("Origin", "*")
        response.headers["Access-Control-Allow-Credentials"] = "true"
        
        return response
    
    except Exception as e:
        logger.exception("An error occurred during processing")
        return jsonify({"error": str(e)}), 500
    
    finally:
        # Don't clean up files - retain them in the container
        pass  # Remove the cleanup code to keep files

# Rest of your code (file explorer functionality, etc.) remains unchanged
# ...

if __name__ == "__main__":
    # Run the Flask app when executed directly
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))