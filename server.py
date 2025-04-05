from flask import Flask, request, send_file, jsonify, render_template, make_response
import subprocess
import os
import tempfile
import logging
import uuid
import time
from flask_cors import CORS

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__, static_folder='.')
CORS(app)  # Enable CORS for all routes

CORS(app, resources={
    r"/*": {
        "origins": "https://your-website.com",  # Replace with your website URL
        "methods": ["POST", "GET", "OPTIONS"],
        "allow_headers": ["Content-Type", "Authorization"]
    }
})

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

@app.route("/process-pdf", methods=["POST"])
def process_pdf():
    """
    Process uploaded PDF using the R script and return the processed PDF.
    Expects a multipart/form-data request with a 'file' field.
    """
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
        
        # Create a response with the file
        # Create a response with the file
        response = make_response(send_file(expected_output_path, mimetype="application/pdf"))
        response.headers["Content-Disposition"] = f'attachment; filename="{expected_output_filename}"'
        response.headers["Content-Type"] = "application/pdf"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response
    
    except Exception as e:
        logger.exception("An error occurred during processing")
        return jsonify({"error": str(e)}), 500
    
    finally:
        # Don't clean up files - retain them in the container
        pass  # Remove the cleanup code to keep files

if __name__ == "__main__":
    # Run the Flask app when executed directly
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
