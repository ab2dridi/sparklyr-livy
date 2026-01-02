# ==============================================================================
# SPARKLYR JAR INSTALLATION VIA WEBHDFS
# ==============================================================================
# This script downloads and installs the sparklyr JAR on HDFS via WebHDFS
# WebHDFS uses the same Knox credentials as the Livy connection

library(jsonlite)

cat("╔══════════════════════════════════════════════════════════════════╗\n")
cat("║          SPARKLYR JAR INSTALLATION VIA WEBHDFS                  ║\n")
cat("╚══════════════════════════════════════════════════════════════════╝\n\n")

# ==============================================================================
# 1. LOAD CONFIGURATION
# ==============================================================================

cat("═══ 1. LOAD CONFIGURATION ═══\n\n")

config_file <- "knox_config.R"
if (!file.exists(config_file)) {
  stop(
    "Configuration file '", config_file, "' not found!\n\n",
    "Create the knox_config.R file with:\n",
    "  KNOX_USERNAME <- 'your_username'\n",
    "  KNOX_PASSWORD <- 'your_password'\n",
    "  KNOX_WEBHDFS_URL <- 'https://knox_hostname:knox_port/gateway/cdp-proxy-api/webhdfs/v1'\n"
  )
}

source(config_file)

# Checks
if (!exists("KNOX_USERNAME") || !exists("KNOX_PASSWORD")) {
  stop("KNOX_USERNAME and KNOX_PASSWORD must be defined in knox_config.R")
}

if (!exists("KNOX_WEBHDFS_URL")) {
  stop("KNOX_WEBHDFS_URL must be defined in knox_config.R\n",
       "Example: KNOX_WEBHDFS_URL <- 'https://hostname:port/gateway/cdp-proxy-api/webhdfs/v1'")
}

cat("✓ Configuration loaded\n")
cat("  Username:", KNOX_USERNAME, "\n")
cat("  WebHDFS URL:", KNOX_WEBHDFS_URL, "\n\n")

# ==============================================================================
# 2. JAR PARAMETERS
# ==============================================================================

cat("═══ 2. JAR PARAMETERS ═══\n\n")

# Detect Spark version from the Livy URL or use default
spark_version <- "3.0"  # Default for CDP 7.1.9
scala_version <- "2.12"

# Try to detect from KNOX_MASTER_URL if it contains version info
if (exists("KNOX_MASTER_URL") && grepl("spark3", KNOX_MASTER_URL, ignore.case = TRUE)) {
  spark_version <- "3.0"
  cat("✓ Detected Spark 3.x from URL\n")
} else if (exists("KNOX_MASTER_URL") && grepl("spark2", KNOX_MASTER_URL, ignore.case = TRUE)) {
  spark_version <- "2.4"
  cat("✓ Detected Spark 2.x from URL\n")
} else {
  cat("! Using default Spark version:", spark_version, "\n")
}

jar_filename <- paste0("sparklyr-", spark_version, "-", scala_version, ".jar")
cat("  JAR filename:", jar_filename, "\n")

# HDFS target directory
hdfs_target_dir <- paste0("/user/", KNOX_USERNAME, "/sparklyr")
cat("  Target HDFS directory:", hdfs_target_dir, "\n")

hdfs_jar_path <- paste0("hdfs://", hdfs_target_dir, "/", jar_filename)
cat("  Full HDFS path:", hdfs_jar_path, "\n\n")

# ==============================================================================
# 3. FIND LOCAL JAR
# ==============================================================================

cat("═══ 3. FIND LOCAL JAR ═══\n\n")

# Try to find the JAR in the local sparklyr installation
sparklyr_path <- system.file(package = "sparklyr")
local_jar_path <- file.path(sparklyr_path, "java", jar_filename)

if (file.exists(local_jar_path)) {
  cat("✓ JAR found in sparklyr installation:\n")
  cat("  ", local_jar_path, "\n")
  jar_source <- local_jar_path
} else {
  cat("✗ JAR not found in sparklyr installation\n")
  cat("  Searching in:", sparklyr_path, "/java/\n")
  
  # List available JARs
  java_dir <- file.path(sparklyr_path, "java")
  if (dir.exists(java_dir)) {
    available_jars <- list.files(java_dir, pattern = "\\.jar$", recursive = FALSE)
    if (length(available_jars) > 0) {
      cat("  Available JARs:\n")
      for (jar in available_jars) {
        cat("    -", jar, "\n")
      }
    }
  }
  
  # Try alternative: download from GitHub if no JAR found
  cat("\n  Attempting to download from GitHub...\n")
  temp_jar <- tempfile(fileext = ".jar")
  github_url <- paste0(
    "https://github.com/sparklyr/sparklyr/releases/download/v1.8.5/",
    jar_filename
  )
  
  tryCatch({
    download.file(github_url, temp_jar, method = "curl", quiet = FALSE)
    if (file.exists(temp_jar) && file.size(temp_jar) > 1000) {
      cat("✓ JAR downloaded from GitHub\n")
      jar_source <- temp_jar
    } else {
      stop("Downloaded file is empty or invalid")
    }
  }, error = function(e) {
    stop(
      "Failed to find or download JAR!\n",
      "  - Not found in sparklyr installation: ", local_jar_path, "\n",
      "  - Failed to download from: ", github_url, "\n",
      "  Error: ", conditionMessage(e), "\n\n",
      "Please:\n",
      "  1. Check your sparklyr installation\n",
      "  2. Or manually download the JAR and specify its path\n",
      "  3. Or install sparklyr version that includes this JAR\n"
    )
  })
}

cat("  JAR size:", round(file.size(jar_source) / 1024 / 1024, 2), "MB\n\n")

# ==============================================================================
# 4. CREATE HDFS DIRECTORY
# ==============================================================================

cat("═══ 4. CREATE HDFS DIRECTORY ═══\n\n")

# Create directory via WebHDFS (MKDIRS operation)
webhdfs_create_dir_url <- paste0(
  KNOX_WEBHDFS_URL,
  hdfs_target_dir,
  "?op=MKDIRS"
)

create_dir_cmd <- sprintf(
  'curl -k -u "%s:%s" -X PUT "%s"',
  KNOX_USERNAME,
  KNOX_PASSWORD,
  webhdfs_create_dir_url
)

cat("Creating directory on HDFS...\n")
create_result <- system(create_dir_cmd, intern = TRUE)

tryCatch({
  result_json <- fromJSON(paste(create_result, collapse = ""))
  if (!is.null(result_json$boolean) && result_json$boolean == TRUE) {
    cat("✓ Directory created or already exists\n\n")
  } else {
    cat("! Warning: Unexpected response from MKDIRS:\n")
    cat(paste(create_result, collapse = "\n"), "\n\n")
  }
}, error = function(e) {
  cat("! Warning: Could not parse MKDIRS response\n")
  cat("  Response:", paste(create_result, collapse = "\n"), "\n\n")
})

# ==============================================================================
# 5. UPLOAD JAR TO HDFS
# ==============================================================================

cat("═══ 5. UPLOAD JAR TO HDFS ═══\n\n")

# Step 1: Get redirect location (CREATE operation)
webhdfs_upload_url <- paste0(
  KNOX_WEBHDFS_URL,
  hdfs_target_dir, "/", jar_filename,
  "?op=CREATE&overwrite=true"
)

cat("Getting upload location...\n")
get_location_cmd <- sprintf(
  'curl -k -i -u "%s:%s" -X PUT "%s" 2>&1 | grep -i "^Location:" | cut -d" " -f2 | tr -d "\\r\\n"',
  KNOX_USERNAME,
  KNOX_PASSWORD,
  webhdfs_upload_url
)

upload_location <- system(get_location_cmd, intern = TRUE)

if (length(upload_location) == 0 || upload_location == "") {
  stop(
    "Failed to get upload location from WebHDFS!\n",
    "  URL used: ", webhdfs_upload_url, "\n",
    "  Please check:\n",
    "    - KNOX_WEBHDFS_URL is correct\n",
    "    - Knox credentials are valid\n",
    "    - WebHDFS service is accessible through Knox\n"
  )
}

cat("✓ Upload location obtained\n")
cat("  Location:", upload_location, "\n\n")

# Step 2: Upload file to the redirect location
cat("Uploading JAR (this may take a few moments)...\n")
upload_cmd <- sprintf(
  'curl -k -u "%s:%s" -X PUT -T "%s" "%s"',
  KNOX_USERNAME,
  KNOX_PASSWORD,
  jar_source,
  upload_location
)

upload_result <- system(upload_cmd, intern = TRUE)
upload_exit_code <- attr(upload_result, "status")

if (is.null(upload_exit_code) || upload_exit_code == 0) {
  cat("✓ JAR successfully uploaded to HDFS\n")
  cat("  HDFS path:", hdfs_jar_path, "\n\n")
} else {
  stop(
    "JAR upload failed!\n",
    "  Exit code: ", upload_exit_code, "\n",
    "  Response: ", paste(upload_result, collapse = "\n"), "\n"
  )
}

# ==============================================================================
# 6. UPDATE CONFIGURATION FILE
# ==============================================================================

cat("═══ 6. UPDATE CONFIGURATION FILE ═══\n\n")

# Update knox_config.R with the JAR path
config_content <- readLines(config_file)

# Find and update SPARKLYR_JAR_PATH line
jar_path_pattern <- "^SPARKLYR_JAR_PATH\\s*<-"
jar_path_line_idx <- grep(jar_path_pattern, config_content)

if (length(jar_path_line_idx) > 0) {
  # Update existing line
  config_content[jar_path_line_idx[1]] <- sprintf('SPARKLYR_JAR_PATH <- "%s"', hdfs_jar_path)
  cat("✓ Updated existing SPARKLYR_JAR_PATH in", config_file, "\n")
} else {
  # Add new line at the end
  config_content <- c(
    config_content,
    "",
    "# SPARKLYR JAR PATH (configured by setup_jar.R)",
    sprintf('SPARKLYR_JAR_PATH <- "%s"', hdfs_jar_path)
  )
  cat("✓ Added SPARKLYR_JAR_PATH to", config_file, "\n")
}

# Write updated configuration
writeLines(config_content, config_file)

cat("  JAR path saved:", hdfs_jar_path, "\n\n")

# ==============================================================================
# COMPLETION
# ==============================================================================

cat("╔══════════════════════════════════════════════════════════════════╗\n")
cat("║                    INSTALLATION COMPLETE                         ║\n")
cat("╚══════════════════════════════════════════════════════════════════╝\n\n")

cat("Next steps:\n")
cat("  1. Verify JAR path in knox_config.R\n")
cat("  2. Connect to Spark: source('sparklyr_connection.R')\n")
cat("  3. Test with examples: source('examples/basic_examples.R')\n\n")

cat("✓ JAR installed at:", hdfs_jar_path, "\n\n")

# Cleanup temporary file if used
if (exists("temp_jar") && file.exists(temp_jar)) {
  unlink(temp_jar)
}
