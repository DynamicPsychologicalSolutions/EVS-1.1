FROM rocker/r-ver:4.2.0

# Install system dependencies required for R packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpoppler-cpp-dev \
    libmagick++-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    cmake \
    python3 \
    python3-pip \
    r-cran-jsonlite \
    r-cran-pdftools \
    r-cran-ggplot2 \
    imagemagick \
    ghostscript \
    # Dependencies for factoextra and FactoMineR
    libudunits2-dev \
    libgdal-dev \
    libgeos-dev \
    libproj-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure ImageMagick policy to allow PDF operations
RUN sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' /etc/ImageMagick-6/policy.xml

# Install base packages first (no dependencies yet)
RUN R -e "install.packages(c('usethis'), repos='https://cran.rstudio.com/')"
RUN R -e "install.packages(c('devtools'), repos='https://cran.rstudio.com/')"

# Install base packages first (no dependencies yet)
RUN R -e "install.packages(c('cluster', 'stats', 'tools'), repos='https://cran.rstudio.com/')"

# Install remaining packages
RUN R -e "install.packages(c('pdftools', 'magick', 'dendextend', 'grid', 'gridExtra', 'dplyr', 'ggplot2', 'ppcor', 'reshape2', 'png'), repos='https://cran.rstudio.com/', dependencies=TRUE)"

# Install FactoMineR (must be installed before factoextra)
RUN R -e "install.packages('FactoMineR', repos='https://cran.rstudio.com/', dependencies=TRUE)"

# Now install factoextra with all dependencies
RUN R -e "install.packages('factoextra', repos='https://cran.rstudio.com/', dependencies=TRUE)"

# Create app directory
WORKDIR /app


# Copy the R script and other files
COPY process_pdf.R /app/
COPY server.py /app/
COPY requirements.txt /app/
COPY EVS_Base_1.1.pdf /app/

# Make sure the R script is executable
RUN chmod +x /app/process_pdf.R

# Install Python requirements
RUN pip3 install -r requirements.txt

# Create uploads directory
RUN mkdir -p /app/uploads

# Expose port for Cloud Run
EXPOSE 8080

# Start the server
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "server:app"]
