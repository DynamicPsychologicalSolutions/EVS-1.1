.libPaths(c(.libPaths(), "/usr/local/lib/R/site-library"))
repos <- "https://cloud.r-project.org/"
packages <- c("pdftools", "magick", "cluster", "factoextra", "dendextend", "grid", "gridExtra", "dplyr", "ggplot2", "ppcor", "reshape2", "png")
for (pkg in packages) {
  if (!require(pkg, character.only = TRUE)) {
    install.packages(pkg)
    library(pkg, character.only = TRUE)
  }
}

# Retrieve command line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  cat("Error: Missing arguments\n")
  cat("Usage: Rscript process_pdf.R input_file output_file\n")
  quit(status = 1)
}

pdf_path <- args[1]

# Validate PDF file exists
if (!file.exists(pdf_path)) {
    stop(paste("File not found:", pdf_path))
}

#

text <- pdf_text(pdf_path)
text_name <- basename(pdf_path)


# PULL OBJECTIVE DATA
#
#

page <- text[4]

# Split into lines
lines <- strsplit(page, "\n")[[1]]

# Split each line into numbers
matrix_data <- lapply(lines, function(line) {
  as.numeric(unlist(strsplit(line, "\\s+")))  # Split by spaces and convert to numeric
})

# Remove empty rows or malformed lines
matrix_data <- Filter(function(row) !all(is.na(row)), matrix_data)

# Convert to a matrix
matrix <- do.call(rbind, matrix_data)

# Remove the first column, and rows 1 and 12
cleaned_matrix_obj <- matrix[-c(1, 12), -1]

# Add headers
new_headers <- c("Fsen", "Fmat", "Fadl", "Fjuv", "Fpjv", "Fsmc", "Finf", "Msen", "Mmat", "Madl", "Mjuv", "Mpjv", "Msmc", "Minf")
colnames(cleaned_matrix_obj) <- new_headers

identify_and_report_outliers <- function(matrix, threshold = 2.575) {
  # Calculate column means and standard deviations
  column_means <- apply(matrix, 2, mean, na.rm = TRUE)
  column_sds <- apply(matrix, 2, sd, na.rm = TRUE)
  
  # Compute Z-scores manually
  z_scores <- matrix(NA, nrow = nrow(matrix), ncol = ncol(matrix))
  for (col in 1:ncol(matrix)) {
    z_scores[, col] <- (matrix[, col] - column_means[col]) / column_sds[col]
  }
  
  # Identify outliers where |Z| > threshold
  outlier_matrix <- abs(z_scores) > threshold
  
  # Prepare a list to store results
  outlier_results <- list()
  
  # Loop through each column and row to find and report outliers
  for (col in 1:ncol(matrix)) {
    for (row in 1:nrow(matrix)) {
      if (outlier_matrix[row, col]) {
        # Calculate p-value for the Z-score
        z_value <- z_scores[row, col]
        p_value <- (1 - pnorm(abs(z_value)))  # Two-tailed p-value
        
        # Retrieve the original value
        original_value <- matrix[row, col]
        
        # Store the results
        outlier_results <- append(outlier_results, list(
          list(
            Row = row,
            Column = colnames(matrix)[col],
            Original_Value = original_value,
            Z_Value = z_value,
            p_Value = p_value
          )
        ))
      }
    }
  }
  
  # Return the results as a data frame without row names
  results_df <- do.call(rbind, lapply(outlier_results, as.data.frame, row.names = NULL))
  return(results_df)
}

# Apply the function to your cleaned matrix
outlier_report <- identify_and_report_outliers(cleaned_matrix_obj, threshold = 2.575)

# Print the outlier report
#View(outlier_report)


# Function to replace outliers with NA
remove_outliers <- function(matrix, threshold = 2.575) {
  # Calculate column means and standard deviations
  column_means <- apply(matrix, 2, mean, na.rm = TRUE)
  column_sds <- apply(matrix, 2, sd, na.rm = TRUE)
  
  # Compute Z-scores manually
  z_scores <- matrix(NA, nrow = nrow(matrix), ncol = ncol(matrix))
  for (col in 1:ncol(matrix)) {
    z_scores[, col] <- (matrix[, col] - column_means[col]) / column_sds[col]
  }
  
  # Identify outliers where |Z| > threshold
  outlier_matrix <- abs(z_scores) > threshold
  
  # Replace outlier cells with NA
  matrix[outlier_matrix] <- NA
  
  return(matrix)
}

# Apply the function to remove outliers
cleaned_matrix_no_outliers <- remove_outliers(cleaned_matrix_obj, threshold = 2.575)

# Sort each column of the matrix independently
sorted_matrix <- apply(cleaned_matrix_no_outliers, 2, function(column) {
  sort(column, na.last = TRUE)  # Sort, placing NAs at the end
})

# Convert back to a matrix with the same dimensions
obj_matrix <- matrix(cleaned_matrix_no_outliers, nrow = nrow(cleaned_matrix_no_outliers), ncol = ncol(cleaned_matrix_no_outliers))

# Retain the column names from the original matrix
colnames(obj_matrix) <- colnames(cleaned_matrix_no_outliers)

# View the sorted matrix
#View(obj_matrix)

#
#
# PULL SUBJECTIVE DATA
#
#

page <- text[5]

# Split into lines
lines <- strsplit(page, "\n")[[1]]

# Split each line into numbers
matrix_data <- lapply(lines, function(line) {
  as.numeric(unlist(strsplit(line, "\\s+")))  # Split by spaces and convert to numeric
})

# Remove empty rows or malformed lines
matrix_data <- Filter(function(row) !all(is.na(row)), matrix_data)

# Convert to a matrix
matrix <- do.call(rbind, matrix_data)

# Remove the first column, and rows 1 and 12
cleaned_matrix_sub <- matrix[-c(1, 12, 13), -1]

# Add headers
new_headers <- c("Fsen", "Fmat", "Fadl", "Fjuv", "Fpjv", "Fsmc", "Finf", "Msen", "Mmat", "Madl", "Mjuv", "Mpjv", "Msmc", "Minf")
colnames(cleaned_matrix_sub) <- new_headers

# Sort each column of the matrix independently
sorted_matrix <- apply(cleaned_matrix_sub, 2, function(column) {
  sort(column, na.last = TRUE)  # Sort, placing NAs at the end
})

# Convert back to a matrix with the same dimensions
sub_matrix <- matrix(cleaned_matrix_sub, nrow = nrow(cleaned_matrix_sub), ncol = ncol(cleaned_matrix_sub))

# Retain the column names from the original matrix
colnames(sub_matrix) <- colnames(cleaned_matrix_sub)

  

# View the sorted matrix
#View(sub_matrix)



#
#
# PARSE DATA FOR CHARTS
#
#

#
# OBJECTIVE DATA
#

# Transpose the dataset so columns (groups) become rows
data1t <- t(obj_matrix)

# Preprocess the data
# Scale the data if necessary
data_scaled <- scale(data1t)

# Define distance methods to iterate over
distance_methods <- c("manhattan", "euclidean")

# Initialize variables to store silhouette widths for both methods
sil_width_manhattan <- numeric(12)
sil_width_euclidean <- numeric(12)

# First, for "manhattan"
dist_matrix_manhattan <- dist(data_scaled, method = "manhattan")
hclust_res_manhattan <- hclust(dist_matrix_manhattan, method = "average")
for (k in 2:13) {
  pam_fit <- pam(dist_matrix_manhattan, diss = TRUE, k = k)
  sil_width_manhattan[k - 1] <- pam_fit$silinfo$avg.width
}
optimal_k_manhattan <- which.max(sil_width_manhattan) + 1
optimal_sil_width_manhattan <- round(sil_width_manhattan[optimal_k_manhattan - 1], 2)

# Then, for "euclidean"
dist_matrix_euclidean <- dist(data_scaled, method = "euclidean")
hclust_res_euclidean <- hclust(dist_matrix_euclidean, method = "average")
for (k in 2:13) {
  pam_fit <- pam(dist_matrix_euclidean, diss = TRUE, k = k)
  sil_width_euclidean[k - 1] <- pam_fit$silinfo$avg.width
}
optimal_k_euclidean <- which.max(sil_width_euclidean) + 1
optimal_sil_width_euclidean <- round(sil_width_euclidean[optimal_k_euclidean - 1], 2)

# Compare the silhouette widths and select the model with the higher value
if (optimal_sil_width_manhattan >= optimal_sil_width_euclidean) {
  cat("Using 'Manhattan' distance method with optimal k:", optimal_k_manhattan, "\n")
  obj_optimal_k <- optimal_k_manhattan
  obj_sil_width <- sil_width_manhattan
  obj_hclust_res <- hclust_res_manhattan
  obj_dist_matrix <- dist(data_scaled, method = "manhattan")
  method <- "manhattan"
} else {
  cat("Using 'Euclidean' distance method with optimal k:", optimal_k_euclidean, "\n")
  obj_optimal_k <- optimal_k_euclidean
  obj_sil_width <- sil_width_euclidean
  obj_hclust_res <- hclust_res_euclidean
  obj_dist_matrix <- dist(data_scaled, method = "euclidean")
  method < - "euclidean"
}
  obj_optimal_k <- which.max(obj_sil_width) + 1
  
  cat("Optimal number of clusters for", method, ":", obj_optimal_k, "\n")
  
  # Print the average silhouette width for the optimal number of clusters
  cat("Average silhouette width for optimal number of clusters:", obj_sil_width[obj_optimal_k - 1], "\n")

  # Perform PAM clustering with the optimal number of clusters
  obj_pam_fit_optimal <- pam(obj_dist_matrix, diss = TRUE, k = obj_optimal_k)
  
  # Calculate average silhouette width for each cluster
  obj_silhouette_stats <- summary(silhouette(obj_pam_fit_optimal))
  obj_cluster_avg_sil_widths <- obj_silhouette_stats$clus.avg.widths
  
  # Get cluster assignments
  obj_clusters <- cutree(obj_hclust_res, k = obj_optimal_k)
  
  # Count observations in each cluster
  obj_cluster_sizes <- table(obj_clusters)

#
# SUBJECTIVE DATA
#

# Transpose the dataset so columns (groups) become rows
data2t <- t(sub_matrix)

# Preprocess the data
# Scale the data if necessary
data_scaled <- scale(data2t)

# Define distance methods to iterate over
distance_methods <- c("manhattan", "euclidean")

# Initialize variables to store silhouette widths for both methods
sil_width_manhattan <- numeric(12)
sil_width_euclidean <- numeric(12)

# First, for "manhattan"
dist_matrix_manhattan <- dist(data_scaled, method = "manhattan")
hclust_res_manhattan <- hclust(dist_matrix_manhattan, method = "average")
for (k in 2:13) {
  pam_fit <- pam(dist_matrix_manhattan, diss = TRUE, k = k)
  sil_width_manhattan[k - 1] <- pam_fit$silinfo$avg.width
}
optimal_k_manhattan <- which.max(sil_width_manhattan) + 1
optimal_sil_width_manhattan <- round(sil_width_manhattan[optimal_k_manhattan - 1], 2)

# Then, for "euclidean"
dist_matrix_euclidean <- dist(data_scaled, method = "euclidean")
hclust_res_euclidean <- hclust(dist_matrix_euclidean, method = "average")
for (k in 2:13) {
  pam_fit <- pam(dist_matrix_euclidean, diss = TRUE, k = k)
  sil_width_euclidean[k - 1] <- pam_fit$silinfo$avg.width
}
optimal_k_euclidean <- which.max(sil_width_euclidean) + 1
optimal_sil_width_euclidean <- round(sil_width_euclidean[optimal_k_euclidean - 1], 2)

# Compare the silhouette widths and select the model with the higher value
if (optimal_sil_width_manhattan >= optimal_sil_width_euclidean) {
  cat("Using 'Manhattan' distance method with optimal k:", optimal_k_manhattan, "\n")
  sub_optimal_k <- optimal_k_manhattan
  sub_sil_width <- sil_width_manhattan
  sub_hclust_res <- hclust_res_manhattan
  sub_dist_matrix <- dist(data_scaled, method = "manhattan")
  method <- "manhattan"
} else {
  cat("Using 'Euclidean' distance method with optimal k:", optimal_k_euclidean, "\n")
  sub_optimal_k <- optimal_k_euclidean
  sub_sil_width <- sil_width_euclidean
  sub_hclust_res <- hclust_res_euclidean
  sub_dist_matrix <- dist(data_scaled, method = "euclidean")
  method < - "euclidean"

}
  sub_optimal_k <- which.max(sub_sil_width) + 1
  
  cat("Optimal number of clusters for", method, ":", sub_optimal_k, "\n")
  
  # Print the average silhouette width for the optimal number of clusters
  cat("Average silhouette width for optimal number of clusters:", sub_sil_width[sub_optimal_k - 1], "\n")

  # Perform PAM clustering with the optimal number of clusters
  sub_pam_fit_optimal <- pam(sub_dist_matrix, diss = TRUE, k = sub_optimal_k)
  
  # Calculate average silhouette width for each cluster
  sub_silhouette_stats <- summary(silhouette(sub_pam_fit_optimal))
  sub_cluster_avg_sil_widths <- sub_silhouette_stats$clus.avg.widths
  
  # Get cluster assignments
  sub_clusters <- cutree(sub_hclust_res, k = sub_optimal_k)
  
  # Count observations in each cluster
  sub_cluster_sizes <- table(sub_clusters)

#
#
# BEGIN OUTPUT
#
#



# OPENING TEXT
#
# Define PNG filename and dimensions
 
png("intro_page.png", width = 6.5*300, height = 6.5*300, res = 250)



# Add a blank page for introductory text
plot.new()
par(mar = c(5, 5, 5, 5))  # Adjust margins for space

# Insert introductory text
text(-0.1, 1.1, paste("
The following report is based on data contained in", text_name), cex = 0.95, pos = 4, xpd = TRUE)

# Now apply the outlier function to your cleaned matrix
outlier_report <- identify_and_report_outliers(cleaned_matrix_obj, threshold = 2.575)

# Count the number of outliers
total_outliers <- nrow(outlier_report)

# Create the appropriate text for outliers
if (is.null(total_outliers)) {
  outlier_text <- "No outliers were identified."
} else if (total_outliers == 1) {
  outlier_text <- "One outlier was identified."
} else {
  outlier_text <- paste(total_outliers, "outliers were identified.")
}

if (is.null(total_outliers)) {
  valid_text <- " "
} else if (total_outliers > 2) {
  valid_text <- "Given the number of outliers, the current profile may not be valid.
Interpret with significant caution."
} else {
  valid_text <- "The current profile is not invalidated due to outliers."
}

# Insert the number of outliers identified
text(-0.1, 1.0, outlier_text, cex = 1, pos = 4, xpd = TRUE)
text(-0.1, 0.95, valid_text, cex = 1, pos = 4, xpd = TRUE)

if (!is.null(total_outliers) && total_outliers > 0) {
  table_text <- "The following table shows information on the detected outlier(s)."
} else {
  table_text <- " "
}
text(-0.1, 0.8, table_text, cex = 1, pos = 4, xpd = TRUE)

# TABLE INSERTION
# Draw the table below the text
# Move the viewport down to make space for the table
pushViewport(viewport(layout = grid.layout(3, 1, heights = unit(c(3, 7), "null"))))
# Add the outlier table to the second section
grid.table(outlier_report, rows = NULL, vp = viewport(x = 0.375, y = 0.6, width = 0.8, height = 0.8))

# Close the PNG device to save the file
dev.off()

#
#
# START CHARTS
#
#


#
# BAR GRAPH 1
#

# Assuming obj_matrix and sub_matrix are data frames or matrices with 14 columns
# Step 1: Calculate subjective data values
sub_col_means <- colMeans(sub_matrix, na.rm = TRUE)
sub_mean_of_means <- mean(sub_col_means)
sub_sd_of_means <- sd(sub_col_means)
sub_z_scores <- (sub_col_means - sub_mean_of_means) / sub_sd_of_means

# Step 2: Calculate objective data values
for (i in seq_len(ncol(obj_matrix))) {
   obj_matrix[is.na(obj_matrix[, i]), i] <- mean(obj_matrix[, i], na.rm = TRUE)
 }
obj_matrix_percent <- obj_matrix / sum(obj_matrix) * 100
obj_col_percent_sums <- colSums(obj_matrix_percent)
obj_mean_percent_sums <- mean(obj_col_percent_sums)
obj_sd_percent_sums <- sd(obj_col_percent_sums)
obj_z_scores <- (obj_col_percent_sums - obj_mean_percent_sums) / obj_sd_percent_sums

# Step 3: Create a combined data frame for plotting
columns <- paste0("Column_", 1:14) # Names for columns
data <- data.frame(
  Column = rep(columns, 2),
  Z_Score = c(obj_z_scores, sub_z_scores),
  Dataset = rep(c("Objective", "Subjective"), each = 14)
)

# Replace default column names with new headers
new_headers <- c("Senior Female (Fsen)", "Mature Female (Fmat)", "Adult Female (Fadl)", "Juvenile Female (Fjuv)", "Pre-Juvenile Female (Fpjv)   .", "Small Child Female (Fsmc)", "Infant Female (Finf)",
                 "Senior Male (Msen)", "Mature Male (Mmat)", "Adult Male (Madl)", "Juvenile Male (Mjuv)", "Pre-Juvenile Male (Mpjv)", "Small Child Male (Msmc)", "Infant Male (Minf)"
)

# Update the data frame with new column headers
data$Column <- rep(new_headers, 2)

# Ensure the bars are sorted in the order of new_headers
data$Column <- factor(data$Column, levels = new_headers)

# Step 4: Add extra space between "Finf" and "Msen"
# Create a modified version of the x-axis labels to include extra space
x_labels <- c(
  "Senior Female (Fsen)", "Mature Female (Fmat)", "Adult Female (Fadl)", "Juvenile Female (Fjuv)", "Pre-Juvenile Female (Fpjv)   .", "Small Child Female (Fsmc)", "Infant Female (Finf)", 
  "",  # Add an empty label for spacing
  "Senior Male (Msen)", "Mature Male (Mmat)", "Adult Male (Madl)", "Juvenile Male (Mjuv)", "Pre-Juvenile Male (Mpjv)", "Small Child Male (Msmc)", "Infant Male (Minf)"
)

# Step 1: Replace default column names with new headers, adding a spacer
new_headers <- c("Senior Female (Fsen)", "Mature Female (Fmat)", "Adult Female (Fadl)", "Juvenile Female (Fjuv)", "Pre-Juvenile Female (Fpjv)   .", "Small Child Female (Fsmc)", "Infant Female (Finf)",
                 " ", "Senior Male (Msen)", "Mature Male (Mmat)", "Adult Male (Madl)", "Juvenile Male (Mjuv)", "Pre-Juvenile Male (Mpjv)", "Small Child Male (Msmc)", "Infant Male (Minf)"
)

# Step 2: Add a dummy row to data for the spacer
spacer_row <- data.frame(
  Column = " ", 
  Z_Score = NA,          # No Z-score for spacer
  Dataset = 1           # No dataset for spacer
)
data <- rbind(data, spacer_row)

# Step 3: Update the factor levels for the Column variable to include the spacer
data$Column <- factor(data$Column, levels = new_headers)

# Step 4: Plot the bar graph with proper spacing
## window(width = 7.5, height = 7.5)

# Find the maximum Z-score in the dataset
max_z_score <- max(data$Z_Score, na.rm = TRUE)

# Define the thresholds
thresholds <- c(1.65, 2.33, 3.09)

# Add horizontal lines and annotations conditionally
bar_z <- ggplot(data, aes(x = Column, y = Z_Score, fill = Dataset)) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.9), na.rm = TRUE) +
  labs(
    title = "Viewing Time and Self-Report Results",
    x = "Age/Gender Groups",
    y = "Z-Score"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    axis.text.x = element_text(angle = 45, hjust = 0, size = 8),  # Keep labels at the top, rotated
    axis.title.x = element_text(vjust = 100),  # Optional: Adjust x-axis title position
    axis.ticks.x = element_blank(),  # Optional: Remove ticks on the x-axis if desired
    axis.line.x = element_blank(),  # Optional: Remove line under x-axis for a cleaner look
    panel.grid.major.x = element_blank(),  # Optional: remove gridlines on the x-axis
    plot.margin = margin(t = 5, b = 10, r = 35),  # Add space at the top and bottom
    legend.position = "bottom",  # Move legend to the bottom
    legend.title = element_blank()  # Remove the legend title ("Dataset")
  ) +
  scale_fill_manual(
    values = c("Objective" = "blue", "Subjective" = "gray"), 
    labels = c("Objective Response", "Self-Report")  # Change key labels
  ) +
  scale_x_discrete(position = "top") +  # Moves the x-axis and its labels to the top
  scale_y_continuous(expand = c(0, 0), limits = c(min(data$Z_Score) - 1, max(data$Z_Score) + 1)) +  # Adjust y-axis limits
  # Conditionally add horizontal lines if the max z-score exceeds the thresholds
  geom_hline(data = data.frame(yintercept = thresholds[thresholds <= max_z_score]), 
             aes(yintercept = yintercept), 
             linetype = "dashed", color = "red", size = 0.5) +  # Add horizontal lines
  # Conditionally add annotations if the corresponding line exists
  {if (1.65 <= max_z_score) 
    annotate("text", x = 1.25, y = 1.65 + 0.1, label = "p = 0.05", color = "red", size = 3, fontface = "italic")
  } +
  {if (2.33 <= max_z_score) 
    annotate("text", x = 1.25, y = 2.33 + 0.1, label = "p = 0.01", color = "red", size = 3, fontface = "italic")
  } +
  {if (3.09 <= max_z_score) 
    annotate("text", x = 1.25, y = 3.09 + 0.1, label = "p = 0.001", color = "red", size = 3, fontface = "italic")
  }
ggsave("bar_z.png", bar_z, width = 7.5, height = 8, dpi = 250)

#
# BAR GRAPH 2
#

# Assuming obj_matrix and sub_matrix are data frames or matrices with 14 columns
# Step 1: Calculate subjective data values
sub_matrix_var <- var(as.vector(sub_matrix))
sub_col_var <- apply(sub_matrix, 2, var)
sub_f_scores <- (sub_col_var / sub_matrix_var)

# Step 2: Calculate objective data values
obj_matrix_var <- var(as.vector(obj_matrix))
obj_col_var <- apply(obj_matrix, 2, var)
obj_f_scores <- (obj_col_var / obj_matrix_var)


# Step 3: Create a combined data frame for plotting
columns <- paste0("Column_", 1:14) # Names for columns
data <- data.frame(
  Column = rep(columns, 2),
  F_Value = c(obj_f_scores, sub_f_scores),
  Dataset = rep(c("Objective", "Subjective"), each = 14)
)

# Replace default column names with new headers
new_headers <- c("Senior Female (Fsen)", "Mature Female (Fmat)", "Adult Female (Fadl)", "Juvenile Female (Fjuv)", "Pre-Juvenile Female (Fpjv)   .", "Small Child Female (Fsmc)", "Infant Female (Finf)",
                 "Senior Male (Msen)", "Mature Male (Mmat)", "Adult Male (Madl)", "Juvenile Male (Mjuv)", "Pre-Juvenile Male (Mpjv)", "Small Child Male (Msmc)", "Infant Male (Minf)"
)

# Update the data frame with new column headers
data$Column <- rep(new_headers, 2)

# Ensure the bars are sorted in the order of new_headers
data$Column <- factor(data$Column, levels = new_headers)

# Step 4: Add extra space between "Finf" and "Msen"
# Create a modified version of the x-axis labels to include extra space
x_labels <- c(
  "",  # Add an empty label for spacing
  "Senior Female (Fsen)", "Mature Female (Fmat)", "Adult Female (Fadl)", "Juvenile Female (Fjuv)", "Pre-Juvenile Female (Fpjv)   .", "Small Child Female (Fsmc)", "Infant Female (Finf)", 
  "",  # Add an empty label for spacing
  "Senior Male (Msen)", "Mature Male (Mmat)", "Adult Male (Madl)", "Juvenile Male (Mjuv)", "Pre-Juvenile Male (Mpjv)", "Small Child Male (Msmc)", "Infant Male (Minf)"
)

# Step 1: Replace default column names with new headers, adding a spacer
new_headers <- c(" ", "Senior Female (Fsen)", "Mature Female (Fmat)", "Adult Female (Fadl)", "Juvenile Female (Fjuv)", "Pre-Juvenile Female (Fpjv)", "Small Child Female (Fsmc)", "Infant Female (Finf)",
                 " ", "Senior Male (Msen)", "Mature Male (Mmat)", "Adult Male (Madl)", "Juvenile Male (Mjuv)", "Pre-Juvenile Male (Mpjv)", "Small Child Male (Msmc)", "Infant Male (Minf)"
)

# Step 2: Add a dummy row to data for the spacer
spacer_row <- data.frame(
  Column = " ", 
  F_Value = NA,          # No Z-score for spacer
  Dataset = 1           # No dataset for spacer
)
data <- rbind(data, spacer_row)

# Step 3: Update the factor levels for the Column variable to include the spacer
#data$Column <- factor(data$Column, levels = new_headers)

# Step 4: Plot the bar graph with proper spacing
## window(width = 7.5, height = 7.5)

# Find the maximum f-score in the dataset
max_f_value <- max(data$F_Value, na.rm = TRUE)

# Define the thresholds
thresholds <- c(1.948, 2.54, 3.5)

bar_f <- ggplot(data, aes(y = Column, x = F_Value, fill = Dataset)) +
geom_bar(stat = "identity", position = position_dodge2(reverse = TRUE, padding = 0.1), na.rm = TRUE)+

  labs(
    title = "Within-Group Variance Outlier(s) Between Categories",
    y = "Age/Gender Groups",  # Now y-axis represents groups
    x = "F Value"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = -5, face = "bold", size = 16),
    axis.text.y = element_text(size = 8),  # Adjust label size
    axis.title.y = element_text(vjust = 1),  
    panel.grid.major.y = element_blank(),  # Remove y-gridlines
    legend.position = "bottom",  # Keep legend at the bottom
    legend.title = element_blank()
  ) +
  scale_fill_manual(
    values = c("Objective" = "darkred", "Subjective" = "gray"), 
    labels = c("Objective Response", "Self-Report")
  ) +
  scale_y_discrete(limits = rev(new_headers)) +  # Reverse order for proper display
  geom_vline(data = data.frame(xintercept = thresholds[thresholds <= max_f_value]), 
             aes(xintercept = xintercept), 
             linetype = "dashed", color = "red", size = 0.5) +  
  geom_vline(data = data.frame(xintercept = 1.948), 
             aes(xintercept = xintercept), 
             linetype = "dashed", color = "red", size = 0.5) +  
  coord_cartesian(xlim = c(0, max(max(data$F_Value, na.rm = TRUE), 2.15))) +
  {if (0 <= max_f_value) 
    annotate("text", y = 16, x = 1.948 + 0.175, label = "p = 0.05", color = "red", size = 3, fontface = "italic")
  } +
  {if (2.54 <= max_f_value) 
    annotate("text", y = 16, x = 2.54 + 0.2, label = "p = 0.01", color = "red", size = 3, fontface = "italic")
  } +
  {if (3.34 <= max_f_value) 
    annotate("text", y = 16, x = 3.34 + 0.2, label = "p = 0.001", color = "red", size = 3, fontface = "italic")
  }
ggsave("bar_f.png", bar_f, width = 7.5, height = 8, dpi = 250)


#
# OBJECTIVE SILHOUETTE
#


png("obj_sil.png", width = 6.5*300, height = 6.5*300, res = 250)

# Set the margin parameters to reduce the top margin
par(mar = c(6, 4, 3, 2))  # Bottom, left, top, right

# Determine the y-axis limits
y_min <- 0.0
y_max <- max(obj_sil_width) * 1.05  # Add some padding above the maximum observed value

# Determine the optimal silhouette width
obj_optimal_sil_width <- round(obj_sil_width[obj_optimal_k - 1], 2)


plot(2:13, obj_sil_width, type = "b", pch = 19, frame = FALSE,
     xlab = "Number of clusters tested",
     ylab = "Average silhouette width",
     main = paste("Silhouette Method for Optimal Clusters - Objective Measurement", sep = ""),
     ylim = c(y_min, y_max)) # Set the y-axis limits

abline(v = obj_optimal_k, col = "red", lty = 2)
abline(h = 0.25, col = "black", lty = 1) # Add horizontal line at y = 0.25
abline(h = 0.5, col = "black", lty = 1) # Add horizontal line at y = 0.50
abline(h = 0.7, col = "black", lty = 1) # Add horizontal line at y = 0.70  


# Add the first subtitle
mtext(side = 3, line = 0, at = mean(par("usr")[1:2]), 
      text = paste("Optimal Average Silhouette Width:", obj_optimal_sil_width), cex = 0.8)

# Determine the subtitle based on the optimal silhouette width
if (obj_optimal_sil_width < 0.25) {
  subtitle <- "INVALID"
} else if (obj_optimal_sil_width >= 0.25 & obj_optimal_sil_width < 0.5) {
  subtitle <- "Weak"
} else if (obj_optimal_sil_width >= 0.5 & obj_optimal_sil_width < 0.7) {
  subtitle <- "Moderate"
} else if (obj_optimal_sil_width >= 0.7) {
  subtitle <- "Strong"
}

# Add the second subtitle based on the optimal silhouette width
mtext(side = 1, line = 4, at = mean(par("usr")[1:2]), 
      text = paste("Model Strength:", subtitle), cex = 0.8)

dev.off()

#
# OBJECTIVE DENDROGRAM
#

png("obj_dend.png", width = 6.5*300, height = 6.5*300, res = 250)

# Continue with further analysis and visualization based on the selected model
cat("Optimal Silhouette Width:", round(max(obj_sil_width), 2), "\n")


# Plot and dendrogram code continues as before
plot(obj_hclust_res, 
     main = paste(obj_optimal_k, " Cluster Dendrogram - Objective Measurement", sep = ""), 
     xlab = "", 
     ylab = "Height")

rect.hclust(obj_hclust_res, k = obj_optimal_k, border = 2:5)

# Add silhouette width and cluster size for each cluster (bottom)
for (i in 1:obj_optimal_k) {
  cluster_label <- paste("Cluster", i, ": Avg Sil Width:", 
                         round(obj_cluster_avg_sil_widths[i], 2),  # Use obj_cluster_avg_sil_widths
                         ", Size:", obj_cluster_sizes[i])
  mtext(side = 1, line = i + 0, at = mean(par("usr")[1:2]), 
        text = cluster_label, cex = 0.8)
}

dev.off()

#
# SUBJECTIVE SILHOUTETTE
# 


png("sub_sil.png", width = 6.5*300, height = 6.5*300, res = 250)


# Set the margin parameters to reduce the top margin
par(mar = c(6, 4, 3, 2))  # Bottom, left, top, right

# Determine the y-axis limits
y_min <- 0.0
y_max <- max(sub_sil_width) * 1.05  # Add some padding above the maximum observed value

# Determine the optimal silhouette width
sub_optimal_sil_width <- round(sub_sil_width[sub_optimal_k - 1], 2)



plot(2:13, sub_sil_width, type = "b", pch = 19, frame = FALSE,
     xlab = "Number of clusters tested",
     ylab = "Average silhouette width",
     main = paste("Silhouette Method for Optimal Clusters - Self-Report", sep = ""),
     ylim = c(y_min, y_max)) # Set the y-axis limits

abline(v = sub_optimal_k, col = "red", lty = 2)
abline(h = 0.25, col = "black", lty = 1) # Add horizontal line at y = 0.25
abline(h = 0.5, col = "black", lty = 1) # Add horizontal line at y = 0.50
abline(h = 0.7, col = "black", lty = 1) # Add horizontal line at y = 0.70  

# Add the first subtitle
mtext(side = 3, line = 0, at = mean(par("usr")[1:2]), 
      text = paste("Optimal Average Silhouette Width:", sub_optimal_sil_width), cex = 0.8)

# Determine the subtitle based on the optimal silhouette width
if (sub_optimal_sil_width < 0.25) {
  subtitle <- "INVALID"
} else if (sub_optimal_sil_width >= 0.25 & sub_optimal_sil_width < 0.5) {
  subtitle <- "Weak"
} else if (sub_optimal_sil_width >= 0.5 & sub_optimal_sil_width < 0.7) {
  subtitle <- "Moderate"
} else if (sub_optimal_sil_width >= 0.7) {
  subtitle <- "Strong"
}

# Add the second subtitle based on the optimal silhouette width
mtext(side = 1, line = 4, at = mean(par("usr")[1:2]), 
      text = paste("Model Strength:", subtitle), cex = 0.8)

dev.off()

#
# SUBJECTIVE DENDROGRAM
#

png("sub_dend.png", width = 6.5*300, height = 6.5*300, res = 250)


# Continue with further analysis and visualization based on the selected model
cat("Optimal Silhouette Width:", round(max(sub_sil_width), 2), "\n")

# Plot and dendrogram code continues as before
plot(sub_hclust_res, 
     main = paste(sub_optimal_k, " Cluster Dendrogram - Self-Report", sep = ""), 
     xlab = "", 
     ylab = "Height")

rect.hclust(sub_hclust_res, k = sub_optimal_k, border = 2:5)

# Add silhouette width and cluster size for each cluster (bottom)
for (i in 1:sub_optimal_k) {
  cluster_label <- paste("Cluster", i, ": Avg Sil Width:", 
                         round(sub_cluster_avg_sil_widths[i], 2), 
                         ", Size:", sub_cluster_sizes[i])
  mtext(side = 1, line = i + 0, at = mean(par("usr")[1:2]), 
        text = cluster_label, cex = 0.8)
}

dev.off()

#
# TANGLEGRAM
#

# Scale the data if necessary
data1s <- scale(data1t)
data2s <- scale(data2t)


# Compute the correct subjective distance matrix
if (optimal_sil_width_manhattan >= optimal_sil_width_euclidean) {
  dist1 <- dist(data1s, method = "manhattan")
} else {
  dist1 <- dist(data1s, method = "euclidean")
}

# Compute the correct subjective distance matrix
if (optimal_sil_width_manhattan >= optimal_sil_width_euclidean) {
  dist2 <- dist(data2s, method = "manhattan")
} else {
  dist2 <- dist(data2s, method = "euclidean")
}

# Perform hierarchical clustering
hc1 <- hclust(dist1, method = 'average')
hc2 <- hclust(dist2, method = 'average')

# Create dendrograms
dend1 <- as.dendrogram(hc1)
dend2 <- as.dendrogram(hc2)

# Ensure labels are character type
labels(dend1) <- as.character(labels(dend1))
labels(dend2) <- as.character(labels(dend2))

# Align and plot two dendrograms side by side
aligned_dend <- dendlist(dend1, dend2) %>%
  untangle(method = "step1side") 

# Function to compute partial correlation and p-value between two matrices
# Extract number of observations (rows) and groups (columns)
n <- nrow(cleaned_matrix_sub)
k <- ncol(cleaned_matrix_sub)

# Assign column names if not already set
colnames(cleaned_matrix_sub) <- colnames(cleaned_matrix_no_outliers) <- paste0("Group", 1:k)

# Convert matrices to long format
df1 <- melt(cleaned_matrix_sub, varnames = c("Observation", "Group"), value.name = "Value1")
df2 <- melt(cleaned_matrix_no_outliers, varnames = c("Observation", "Group"), value.name = "Value2")

# Merge data by Observation and Group
df <- merge(df1, df2, by = c("Observation", "Group"))

# Convert Group from factor to numeric
df$Group <- as.numeric(as.factor(df$Group))

df <- na.omit(df)

# Compute partial correlation using Kendall's method
pcor <- pcor.test(df$Value1, df$Value2, df$Group, method = "kendall")

print(pcor$estimate)
print(pcor$p.value)


# Compute Baker's gamma coefficient
bakers_gamma <- cor_bakers_gamma(dend1, dend2)

png("tangle.png", width = 6.5*300, height = 7.5*300, res = 250)


# Plot the tanglegram
tg <- tanglegram(aligned_dend,
                 highlight_distinct_edges = FALSE,
                 common_subtrees_color_lines = TRUE,
                 common_subtrees_color_branches = FALSE)



# Check if tanglegram plot is valid
if (is.null(tg)) {
  stop("Tanglegram plot could not be generated.")
}


# Annotate tanglegram with Baker's gamma coefficient
mtext(paste("Hierarchical Cluster Dendrogram Correlation"),
      side = 3, line = 2, adj = 0.45, cex = 1.25, font = 2)

mtext(paste("Self-Report"),
      side = 3, line = 0.75, adj = 0.9, cex = 0.9)
mtext(paste("Objective Measurement"),
      side = 3, line = 0.75, adj = -0.05, cex = 0.9)

# Annotate tanglegram with Baker's gamma coefficient
mtext(paste("Baker's Gamma:", round(bakers_gamma, 3)),
      side = 1, line = 1, adj = 0.45, cex = 1)

mtext(paste("Partial Kendall's tau:", round(pcor$estimate, 3), 
            ", p =", round(pcor$p.value, 3)),
      side = 1, line = 2, adj = 0.45, cex = 0.7)

dev.off()

#
# END CHART GENERATION
#
#
# BEGIN PDF COMPILE
#
#

pdf_subset("EVS_Base_1.1.pdf", pages = 1:3, output = "Page_0.pdf")

# Extract the page
pdf_subset("EVS_Base_1.1.pdf", pages = 4, output = "temp_page1.pdf")

# Convert PDF to image to avoid font issues
temp_image <- "temp_page.png"
pdf_convert("temp_page1.pdf", 
            dpi = 250,  # Higher DPI for better quality
            format = "png", 
            filenames = temp_image)

# Read the converted image and the bar image
page <- image_read(temp_image)
overlay <- image_read("intro_page.png")

# Composite the images
result <- image_composite(page, overlay, offset = "+75+250")

# Save the result as PDF
image_write(result, "Page_1.pdf", format = "pdf")

# Optional: Clean up temporary files
file.remove("temp_page1.pdf", temp_image)

#
#
#

# Extract the page
pdf_subset("EVS_Base_1.1.pdf", pages = 5, output = "temp_page2.pdf")

# Convert PDF to image to avoid font issues
temp_image <- "temp_page2.png"
pdf_convert("temp_page2.pdf", 
            dpi = 250,  # Higher DPI for better quality
            format = "png", 
            filenames = temp_image)

# Read the converted image and the bar image
page_image <- image_read(temp_image)
bar_image <- image_read("bar_z.png")

# Composite the images
result <- image_composite(page_image, bar_image, offset = "+150+350")

# Save the result as PDF
image_write(result, "Page_2.pdf", format = "pdf")

# Optional: Clean up temporary files
file.remove("temp_page2.pdf", temp_image)

#
#
#

# Extract the page
pdf_subset("EVS_Base_1.1.pdf", pages = 6, output = "temp_page3.pdf")

# Convert PDF to image to avoid font issues
temp_image <- "temp_page.png"
pdf_convert("temp_page3.pdf", 
            dpi = 250,  # Higher DPI for better quality
            format = "png", 
            filenames = temp_image)

# Read the converted image and the bar image
page <- image_read(temp_image)
overlay <- image_read("bar_f.png")

# Composite the images
result <- image_composite(page, overlay, offset = "+150+350")

# Save the result as PDF
image_write(result, "Page_3.pdf", format = "pdf")

# Optional: Clean up temporary files
file.remove("temp_page3.pdf", temp_image)

#
#
#

# Extract the page
pdf_subset("EVS_Base_1.1.pdf", pages = 7, output = "temp_page4.pdf")

# Convert PDF to image to avoid font issues
temp_image <- "temp_page.png"
pdf_convert("temp_page4.pdf", 
            dpi = 250,  # Higher DPI for better quality
            format = "png", 
            filenames = temp_image)

# Read the converted image and the bar image
page <- image_read(temp_image)
overlay <- image_read("obj_sil.png")

# Composite the images
result <- image_composite(page, overlay, offset = "+100+275")

# Save the result as PDF
image_write(result, "Page_4.pdf", format = "pdf")

# Optional: Clean up temporary files
file.remove("temp_page4.pdf", temp_image)

#
#
#

# Extract the page
pdf_subset("EVS_Base_1.1.pdf", pages = 8, output = "temp_page5.pdf")

# Convert PDF to image to avoid font issues
temp_image <- "temp_page.png"
pdf_convert("temp_page5.pdf", 
            dpi = 250,  # Higher DPI for better quality
            format = "png", 
            filenames = temp_image)

# Read the converted image and the bar image
page <- image_read(temp_image)
overlay <- image_read("obj_dend.png")

# Composite the images
result <- image_composite(page, overlay, offset = "+100+275")

# Save the result as PDF
image_write(result, "Page_5.pdf", format = "pdf")

# Optional: Clean up temporary files
file.remove("temp_page5.pdf", temp_image)

#
#
#

# Extract the page
pdf_subset("EVS_Base_1.1.pdf", pages = 9, output = "temp_page6.pdf")

# Convert PDF to image to avoid font issues
temp_image <- "temp_page.png"
pdf_convert("temp_page6.pdf", 
            dpi = 250,  # Higher DPI for better quality
            format = "png", 
            filenames = temp_image)

# Read the converted image and the bar image
page <- image_read(temp_image)
overlay <- image_read("sub_sil.png")

# Composite the images
result <- image_composite(page, overlay, offset = "+100+275")

# Save the result as PDF
image_write(result, "Page_6.pdf", format = "pdf")

# Optional: Clean up temporary files
file.remove("temp_page6.pdf", temp_image)

#
#
#

# Extract the page
pdf_subset("EVS_Base_1.1.pdf", pages = 10, output = "temp_page7.pdf")

# Convert PDF to image to avoid font issues
temp_image <- "temp_page.png"
pdf_convert("temp_page7.pdf", 
            dpi = 250,  # Higher DPI for better quality
            format = "png", 
            filenames = temp_image)

# Read the converted image and the bar image
page <- image_read(temp_image)
overlay <- image_read("sub_dend.png")

# Composite the images
result <- image_composite(page, overlay, offset = "+100+275")

# Save the result as PDF
image_write(result, "Page_7.pdf", format = "pdf")

# Optional: Clean up temporary files
file.remove("temp_page7.pdf", temp_image)

#
#
#

# Extract the page
pdf_subset("EVS_Base_1.1.pdf", pages = 11, output = "temp_page8.pdf")

# Convert PDF to image to avoid font issues
temp_image <- "temp_page.png"
pdf_convert("temp_page8.pdf", 
            dpi = 250,  # Higher DPI for better quality
            format = "png", 
            filenames = temp_image)

# Read the converted image and the bar image
page <- image_read(temp_image)
overlay <- image_read("tangle.png")

# Composite the images
result <- image_composite(page, overlay, offset = "+100+240")

# Save the result as PDF
image_write(result, "Page_8.pdf", format = "pdf")

# Optional: Clean up temporary files
file.remove("temp_page8.pdf", temp_image)

#
#
#
file.remove("intro_page.png", "bar_z.png", "bar_f.png", "obj_sil.png", "obj_dend.png", "sub_sil.png", "sub_dend.png", "tangle.png")
pdf_combine(c("Page_0.pdf", "Page_1.pdf", "Page_2.pdf", "Page_3.pdf", "Page_4.pdf", "Page_5.pdf", "Page_6.pdf", "Page_7.pdf", "Page_8.pdf"), output = paste("EVS", text_name, "Report.pdf"))
file.remove("Page_0.pdf", "Page_1.pdf", "Page_2.pdf", "Page_3.pdf", "Page_4.pdf", "Page_5.pdf", "Page_6.pdf", "Page_7.pdf", "Page_8.pdf")


