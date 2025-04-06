from flask import Flask, request, send_file, jsonify, render_template_string, make_response
import os
import logging
import time
from flask_cors import CORS
from functools import wraps

# Create the Flask app
app = Flask(__name__)

# Enable CORS for all routes
CORS(app, supports_credentials=True)

# Simple authentication
def check_auth(username, password):
    """Check if a username/password combination is valid."""
    # Replace with your actual credentials
    return username == 'admin' and password == 'DarkBlue570'

def authenticate():
    """Send a 401 response that prompts the user to authenticate."""
    return make_response(
        'Could not verify your access level for that URL.\n'
        'You have to login with proper credentials', 401,
        {'WWW-Authenticate': 'Basic realm="Login Required"'})

def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or not check_auth(auth.username, auth.password):
            return authenticate()
        return f(*args, **kwargs)
    return decorated

# Your existing PDF processing route
@app.route('/process-pdf', methods=['POST'])
def process_pdf():
    # Your existing PDF processing code here
    # ...
    pass

# Add the file explorer route
@app.route('/secret-files')
@requires_auth
def file_explorer():
    """A simple file explorer to browse and download files."""
    # Set the base directory where processed PDFs are stored
    base_dir = os.path.join(os.getcwd(), 'processed_pdfs')  # Change this to your actual storage directory
    
    # Create the directory if it doesn't exist
    if not os.path.exists(base_dir):
        os.makedirs(base_dir)
    
    # Get the requested directory path, default to base directory
    path = request.args.get('path', '')
    current_dir = os.path.normpath(os.path.join(base_dir, path))
    
    # Security check to prevent directory traversal
    if not current_dir.startswith(base_dir):
        return "Access denied: Directory traversal attempt", 403
    
    # Get files and directories
    files = []
    dirs = []
    
    try:
        for item in os.listdir(current_dir):
            item_path = os.path.join(current_dir, item)
            if os.path.isfile(item_path):
                # Get file stats
                stats = os.stat(item_path)
                size_kb = stats.st_size / 1024
                mod_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stats.st_mtime))
                
                # Only include PDF files
                if item.lower().endswith('.pdf'):
                    files.append({
                        'name': item,
                        'size': f"{size_kb:.1f} KB",
                        'modified': mod_time,
                        'path': os.path.join(path, item) if path else item
                    })
            elif os.path.isdir(item_path):
                dirs.append({
                    'name': item,
                    'path': os.path.join(path, item) if path else item
                })
    except Exception as e:
        return f"Error accessing directory: {str(e)}", 500
    
    # Generate breadcrumb navigation
    breadcrumbs = []
    if path:
        parts = path.split(os.sep)
        for i in range(len(parts)):
            crumb_path = os.sep.join(parts[:i+1])
            breadcrumbs.append({
                'name': parts[i],
                'path': crumb_path
            })
    
    # HTML template for the file explorer
    html_template = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Processed PDF Files</title>
        <meta name="robots" content="noindex, nofollow">
        <style>
            body {
                font-family: Arial, sans-serif;
                margin: 0;
                padding: 20px;
                background-color: #f4f4f4;
            }
            .container {
                max-width: 1000px;
                margin: 0 auto;
                background-color: white;
                padding: 20px;
                border-radius: 5px;
                box-shadow: 0 2px 5px rgba(0,0,0,0.1);
            }
            h1 {
                margin-top: 0;
                color: #333;
                border-bottom: 1px solid #ddd;
                padding-bottom: 10px;
            }
            .breadcrumb {
                margin-bottom: 20px;
                background-color: #f8f9fa;
                padding: 10px;
                border-radius: 4px;
            }
            .breadcrumb a {
                color: #007bff;
                text-decoration: none;
            }
            .breadcrumb a:hover {
                text-decoration: underline;
            }
            table {
                width: 100%;
                border-collapse: collapse;
                margin-top: 20px;
            }
            th, td {
                padding: 12px 15px;
                text-align: left;
                border-bottom: 1px solid #ddd;
            }
            th {
                background-color: #f2f2f2;
                font-weight: bold;
            }
            tr:hover {
                background-color: #f5f5f5;
            }
            a {
                color: #007bff;
                text-decoration: none;
            }
            a:hover {
                text-decoration: underline;
            }
            .folder-icon, .file-icon {
                margin-right: 5px;
            }
            .folder-icon:before {
                content: "📁";
            }
            .file-icon:before {
                content: "📄";
            }
            .back-link {
                display: inline-block;
                margin-bottom: 15px;
                font-weight: bold;
            }
            .pdf-icon:before {
                content: "📃";
                color: #e74c3c;
            }
            .download-btn {
                background-color: #C80000;
                color: white;
                padding: 5px 10px;
                border: none;
                border-radius: 4px;
                cursor: pointer;
                font-size: 14px;
                display: inline-block;
            }
            .download-btn:hover {
                background-color: #a70000;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Processed PDF Files</h1>
            
            <div class="breadcrumb">
                <a href="?path=">Home</a>
                {% for crumb in breadcrumbs %}
                    / <a href="?path={{ crumb.path }}">{{ crumb.name }}</a>
                {% endfor %}
            </div>
            
            {% if path %}
                <a href="?path={% if breadcrumbs|length > 1 %}{{ breadcrumbs[-2].path }}{% else %}{% endif %}" class="back-link">⬅️ Go Back</a>
            {% endif %}
            
            <table>
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Size</th>
                        <th>Modified</th>
                        <th>Action</th>
                    </tr>
                </thead>
                <tbody>
                    {% for dir in dirs %}
                        <tr>
                            <td>
                                <span class="folder-icon"></span>
                                <a href="?path={{ dir.path }}">{{ dir.name }}</a>
                            </td>
                            <td>-</td>
                            <td>-</td>
                            <td>-</td>
                        </tr>
                    {% endfor %}
                    
                    {% for file in files %}
                        <tr>
                            <td>
                                <span class="pdf-icon"></span>
                                {{ file.name }}
                            </td>
                            <td>{{ file.size }}</td>
                            <td>{{ file.modified }}</td>
                            <td>
                                <a href="/secret-download?file={{ file.path }}" class="download-btn">Download</a>
                            </td>
                        </tr>
                    {% endfor %}
                    
                    {% if not dirs and not files %}
                        <tr>
                            <td colspan="4" style="text-align: center; padding: 20px;">
                                No files found in this directory.
                            </td>
                        </tr>
                    {% endif %}
                </tbody>
            </table>
        </div>
    </body>
    </html>
    """
    
    return render_template_string(
        html_template, 
        files=files, 
        dirs=dirs, 
        path=path, 
        breadcrumbs=breadcrumbs
    )

@app.route('/secret-download')
@requires_auth
def download_file():
    """Download a file from the server."""
    # Get the file path
    file_path = request.args.get('file', '')
    if not file_path:
        return "No file specified", 400
    
    # Set the base directory where processed PDFs are stored
    base_dir = os.path.join(os.getcwd(), 'processed_pdfs')  # Change this to your actual storage directory
    
    # Security check to prevent directory traversal
    full_path = os.path.normpath(os.path.join(base_dir, file_path))
    
    if not full_path.startswith(base_dir):
        return "Access denied: Directory traversal attempt", 403
    
    if not os.path.isfile(full_path):
        return "File not found", 404
    
    # Return the file
    return send_file(
        full_path,
        as_attachment=True,
        download_name=os.path.basename(full_path)
    )

# Add a JSON API endpoint for programmatic access if needed
@app.route('/api/secret-files')
@requires_auth
def list_files_api():
    """API endpoint to get a list of PDF files."""
    base_dir = os.path.join(os.getcwd(), 'processed_pdfs')  # Change this to your actual storage directory
    path = request.args.get('path', '')
    current_dir = os.path.normpath(os.path.join(base_dir, path))
    
    # Security check
    if not current_dir.startswith(base_dir):
        return jsonify({"error": "Access denied: Directory traversal attempt"}), 403
    
    files = []
    dirs = []
    
    try:
        for item in os.listdir(current_dir):
            item_path = os.path.join(current_dir, item)
            if os.path.isfile(item_path) and item.lower().endswith('.pdf'):
                stats = os.stat(item_path)
                size_kb = stats.st_size / 1024
                mod_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stats.st_mtime))
                
                files.append({
                    'name': item,
                    'size': f"{size_kb:.1f} KB",
                    'modified': mod_time,
                    'path': os.path.join(path, item) if path else item,
                    'download_url': f"/secret-download?file={os.path.join(path, item) if path else item}"
                })
            elif os.path.isdir(item_path):
                dirs.append({
                    'name': item,
                    'path': os.path.join(path, item) if path else item
                })
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    
    return jsonify({
        "files": files,
        "directories": dirs,
        "current_path": path
    })

# Make sure the app runs if this file is executed directly
if __name__ == '__main__':
    # Set up logging
    logging.basicConfig(level=logging.INFO)
    # Run the app - use environment variable PORT if available (for Cloud Run)
    app.run(debug=True, host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
