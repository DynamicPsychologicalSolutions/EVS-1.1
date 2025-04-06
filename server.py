from flask import Flask, request, send_file, jsonify, render_template, make_response, redirect
import subprocess
import os
import tempfile
import logging
import uuid
import time
from flask_cors import CORS
from google.cloud import storage

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

# Configure Google Cloud Storage
BUCKET_NAME = "your-bucket-name"  # Replace with your bucket name
storage_client = storage.Client()
bucket = storage_client.bucket(BUCKET_NAME)

# Function to upload file to GCS
def upload_to_gcs(local_file_path, destination_blob_name):
    """Upload a file to Google Cloud Storage bucket."""
    blob = bucket.blob(destination_blob_name)
    blob.upload_from_filename(local_file_path)
    return blob.public_url

# New endpoint to access processed PDFs
@app.route("/files/<file_id>", methods=["GET"])
def get_processed_file(file_id):
    """
    Serve a processed file from Google Cloud Storage or redirect to its public URL.
    """
    try:
        # Construct the blob name for the processed file
        blob_name = f"processed/{file_id}"
        blob = bucket.blob(blob_name)
        
        # Check if the file exists
        if not blob.exists():
            return jsonify({"error": "File not found"}), 404
        
        # Option 1: Generate a signed URL and redirect the user
        signed_url = blob.generate_signed_url(
            version="v4",
            expiration=datetime.timedelta(minutes=15),
            method="GET"
        )
        return redirect(signed_url)
        
        # Option 2 (Alternative): Stream the file through your server
        # This is more resource-intensive but gives you more control
        """
        temp_file = tempfile.NamedTemporaryFile(delete=False)
        blob.download_to_filename(temp_file.name)
        
        response = make_response(send_file(temp_file.name, mimetype="application/pdf"))
        response.headers["Content-Disposition"] = f'attachment; filename="{file_id}"'
        response.headers["Content-Type"] = "application/pdf"
        response.headers["X-Content-Type-Options"] = "nosniff"
        
        # Add CORS headers
        response.headers["Access-Control-Allow-Origin"] = request.headers.get("Origin", "*")
        
        # Clean up the temp file in the background after the response is sent
        @response.call_on_close
        def cleanup():
            os.unlink(temp_file.name)
            
        return response
        """
    
    except Exception as e:
        logger.exception("Error retrieving file")
        return jsonify({"error": str(e)}), 500

@app.route("/process-pdf", methods=["POST", "OPTIONS"])
def process_pdf():
    """
    Process uploaded PDF using the R script, upload to GCS, and return the processed PDF.
    """
    # Handle preflight OPTIONS request explicitly
    if request.method == "OPTIONS":
        response = make_response()
        response.headers.add("Access-Control-Allow-Origin", "*")
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
        
        # Create a unique ID for the file
        unique_id = str(uuid.uuid4())
        
        # Create temporary directory for processing
        with tempfile.TemporaryDirectory() as temp_dir:
            # Save input file
            input_path = os.path.join(temp_dir, original_filename)
            file.save(input_path)
            
            # Upload original file to GCS
            upload_to_gcs(input_path, f"uploads/{unique_id}/{original_filename}")
            
            # Expected output filename
            expected_output_filename = f"EVS {original_filename} Report.pdf"
            expected_output_path = os.path.join(temp_dir, expected_output_filename)
            
            # Process the PDF with R script
            process = subprocess.run(
                ["Rscript", "--verbose", "process_pdf.R", input_path, expected_output_path],
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
            
            # Check if output file exists
            if not os.path.exists(expected_output_path):
                logger.error(f"Output file not found at {expected_output_path}")
                return jsonify({"error": "Output file not generated"}), 500
            
            # Upload processed file to GCS
            gcs_output_path = f"processed/{unique_id}_{expected_output_filename}"
            public_url = upload_to_gcs(expected_output_path, gcs_output_path)
            
            logger.info(f"Processed file uploaded to GCS: {gcs_output_path}")
            
            # Return the file content
            response = make_response(send_file(expected_output_path, mimetype="application/pdf"))
            response.headers["Content-Disposition"] = f'attachment; filename="{expected_output_filename}"'
            response.headers["Content-Type"] = "application/pdf"
            response.headers["X-Content-Type-Options"] = "nosniff"
            
            # Add file location metadata
            response.headers["X-File-ID"] = unique_id
            response.headers["X-GCS-Path"] = gcs_output_path
            
            # Add CORS headers
            response.headers["Access-Control-Allow-Origin"] = request.headers.get("Origin", "*")
            response.headers["Access-Control-Allow-Credentials"] = "true"
            response.headers["Access-Control-Expose-Headers"] = "X-File-ID, X-GCS-Path"
            
            return response
    
    except Exception as e:
        logger.exception("An error occurred during processing")
        return jsonify({"error": str(e)}), 500

@app.route("/", methods=["GET"])
def index():
    """Serve the index.html file."""
    return send_file('index.html')

@app.route("/health", methods=["GET"])
def health_check():
    """Endpoint for health checks."""
    return jsonify({"status": "healthy", "timestamp": time.time()})

if __name__ == "__main__":
    # Run the Flask app when executed directly
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
