# ============================================================================
# CLEANUP - LIKE A NEW R SESSION
# ============================================================================

cat("╔═══════════════════════════════════════════════════════════════════╗\n")
cat("║          CLEANUP AND CLEAN SESSION STARTUP                        ║\n")
cat("╚═══════════════════════════════════════════════════════════════════╝\n\n")

cat("1. Detaching packages...\n")
# Detach sparklyr and its dependencies if loaded
packages_to_detach <- c("sparklyr", "jsonlite", "dplyr", "dbplyr")
for (pkg in packages_to_detach) {
  pkg_name <- paste0("package:", pkg)
  if (pkg_name %in% search()) {
    detach(pkg_name, unload = TRUE, character.only = TRUE)
    cat("  ✓", pkg, "detached\n")
  }
}

cat("\n2. Environment cleanup...\n")
# Remove existing variables (except base functions)
rm(list = setdiff(ls(envir = .GlobalEnv), c("KNOX_USERNAME", "KNOX_PASSWORD", "KNOX_MASTER_URL")))
cat("  ✓ Variables removed\n")

cat("\n3. Garbage collector cleanup...\n")
gc(verbose = FALSE)
cat("  ✓ Memory cleaned\n")

cat("\n4. Reloading packages...\n")
library(sparklyr)
library(jsonlite)
cat("  ✓ Packages loaded with clean state\n\n")

cat("═══════════════════════════════════════════════════════════════════\n\n")

# ============================================================================
# CONFIGURATION LOADING
# ============================================================================

cat("Loading configuration...\n")
config_file <- "knox_config.R"

if (!file.exists(config_file)) {
  stop(
    "Configuration file '", config_file, "' not found!\n\n",
    "Create the knox_config.R file with:\n",
    "  KNOX_USERNAME <- 'your_username'\n",
    "  KNOX_PASSWORD <- 'your_password'\n",
    "  KNOX_MASTER_URL <- 'https://...'\n"
  )
}

source(config_file)
cat("  ✓ Configuration loaded from", config_file, "\n")
cat("  ✓ Username:", KNOX_USERNAME, "\n")
cat("  ✓ URL:", KNOX_MASTER_URL, "\n")

# Check if JAR path is configured
if (exists("SPARKLYR_JAR_PATH") && !is.null(SPARKLYR_JAR_PATH) && SPARKLYR_JAR_PATH != "") {
  cat("  ✓ JAR Path:", SPARKLYR_JAR_PATH, "\n")
} else {
  cat("\n")
  cat("╔═══════════════════════════════════════════════════════════════════╗\n")
  cat("║                    ⚠ JAR PATH NOT CONFIGURED ⚠                   ║\n")
  cat("╚═══════════════════════════════════════════════════════════════════╝\n")
  cat("\n")
  cat("sparklyr REQUIRES a JAR file to work with Livy.\n")
  cat("Your cluster has no Internet access, so you must install it manually.\n\n")
  cat("See INSTALL_JAR_INSTRUCTIONS.md for detailed steps:\n")
  cat("1. Download sparklyr-3.0-2.12.jar from GitHub (on a machine with Internet)\n")
  cat("2. Copy it to your cluster (HDFS or local filesystem)\n")
  cat("3. Add to knox_config.R:\n")
  cat("   SPARKLYR_JAR_PATH <- 'hdfs:///path/to/sparklyr-3.0-2.12.jar'\n\n")
  stop("Configuration incomplete: SPARKLYR_JAR_PATH not set")
}

cat("\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

# ============================================================================
# CURL FUNCTION WITH DEBUG
# ============================================================================


livy_curl_request <- function(url, username, password, method = "GET", body = NULL, debug = FALSE) {
  auth <- paste0(username, ":", password)
  
  # Create temp file for auth if needed (extra safety)
  if (method == "GET") {
    cmd <- sprintf("curl -s -k -u '%s' '%s'", 
                   gsub("'", "'\\''", auth), url)
    result <- system(cmd, intern = TRUE, ignore.stderr = FALSE)
  } else {
    # For POST/DELETE, always use temp file
    body_file <- tempfile(fileext = ".json")
    
    if (is.null(body) || body == "" || body == "{}") {
      body_to_write <- "{}"
    } else {
      body_to_write <- body
    }
    
    # Write with explicit encoding
    writeLines(body_to_write, body_file, useBytes = FALSE)
    
    if (method == "POST") {
      cmd <- sprintf(
        "curl -s -k -u '%s' -X POST -H 'Content-Type: application/json' --data-binary @%s '%s'",
        gsub("'", "'\\''", auth), body_file, url
      )
    } else if (method == "DELETE") {
      cmd <- sprintf("curl -s -k -u '%s' -X DELETE '%s'", 
                     gsub("'", "'\\''", auth), url)
    }
    
    if (debug) {
      cat("Body size:", nchar(body_to_write), "bytes\n")
      cat("Command:", cmd, "\n\n")
    }
    
    result <- tryCatch({
      system(cmd, intern = TRUE, ignore.stderr = FALSE)
    }, finally = {
      if (file.exists(body_file)) unlink(body_file)
    })
  }
  
  # Parse response (same as before)
  if (length(result) == 0 || all(result == "")) {
    return(list())
  }
  
  tryCatch({
    jsonlite::fromJSON(paste(result, collapse = "\n"))
  }, error = function(e) {
    warning("JSON parse error: ", e$message)
    list()
  })
}

# ============================================================================
# PATCH WITH DETAILED DEBUG + JARS FIX
# ============================================================================

cat("Applying patch...\n")

livy_get_json <- function(url, config) {
  livy_curl_request(url, config$sparklyr.connect.livy.username, 
                    config$sparklyr.connect.livy.password, "GET")
}

# JARS FIX: Use manually installed JAR instead of downloading from GitHub
livy_connection_jars <- function(config, version, scala_version) {
  # Return the manually configured JAR path instead of trying to download from GitHub
  if (exists("SPARKLYR_JAR_PATH", envir = .GlobalEnv) && 
      !is.null(SPARKLYR_JAR_PATH) && 
      SPARKLYR_JAR_PATH != "") {
    return(SPARKLYR_JAR_PATH)
  }
  return(NULL)
}

livy_create_session <- function(master, config) {
  data <- list(
    kind = jsonlite::unbox("spark"),
    conf = sparklyr:::livy_config_get(master, config)
  )
  
  session_params <- connection_config(
    list(master = master, config = config),
    prefix = "livy.", not_prefix = "livy.session."
  )
  
  # Add proxyUser (unless explicitly disabled)
  if (is.null(session_params$proxyUser)) {
    # Check if user wants to disable automatic proxyUser
    if (!exists("DISABLE_PROXYUSER", envir = .GlobalEnv) || !DISABLE_PROXYUSER) {
      session_params$proxyUser <- jsonlite::unbox(config$sparklyr.connect.livy.username)
      cat("→ Using proxyUser:", config$sparklyr.connect.livy.username, "\n")
    } else {
      cat("→ proxyUser disabled (DISABLE_PROXYUSER=TRUE)\n")
    }
  }
  
  # DO NOT remove JARs - we want to use the manually configured JAR
  # session_params$jars <- NULL  # REMOVED - keep the JAR!
  
  if (length(session_params) > 0) {
    data <- append(data, session_params)
  }
  
  cat("\n=== SESSION CREATION - BODY JSON ===\n")
  body_json <- toJSON(data, pretty = TRUE)
  cat(body_json, "\n\n")
  
  content <- livy_curl_request(
    paste(master, "sessions", sep = "/"),
    config$sparklyr.connect.livy.username,
    config$sparklyr.connect.livy.password,
    "POST", body_json, debug = TRUE
  )
  
  cat("=== SESSION CREATION RESPONSE ===\n")
  print(str(content))
  cat("\n")
  
  if (is.null(content$id) || is.null(content$state) || content$kind != "spark") {
    stop("Livy session creation failed")
  }
  
  content
}

livy_destroy_session <- function(sc) {
  livy_curl_request(
    paste(sc$master, "sessions", sc$sessionId, sep = "/"),
    sc$config$sparklyr.connect.livy.username,
    sc$config$sparklyr.connect.livy.password,
    "DELETE"
  )
  NULL
}

livy_get_session <- function(sc) {
  session <- livy_curl_request(
    paste(sc$master, "sessions", sc$sessionId, sep = "/"),
    sc$config$sparklyr.connect.livy.username,
    sc$config$sparklyr.connect.livy.password,
    "GET"
  )
  
  if (is.null(session$state)) stop("Session state not found")
  if (session$id != sc$sessionId) stop("Invalid session ID")
  
  # ALWAYS display full information
  cat("\n=== SESSION STATE:", session$state, "===\n")
  cat("ID:", session$id, "\n")
  cat("Kind:", session$kind, "\n")
  if (!is.null(session$proxyUser)) cat("ProxyUser:", session$proxyUser, "\n")
  if (!is.null(session$owner)) cat("Owner:", session$owner, "\n")
  
  if (session$state %in% c("dead", "error", "killed", "shutting_down")) {
    cat("\n╔═══════════════════════════════════════════════════════════════════╗\n")
    cat("║                       SESSION IN ERROR                            ║\n")
    cat("╚═══════════════════════════════════════════════════════════════════╝\n\n")
    
    # Complete JSON dump
    cat("=== COMPLETE SESSION JSON ===\n")
    cat(toJSON(session, pretty = TRUE, auto_unbox = FALSE), "\n\n")
    
    # Logs
    if (!is.null(session$log) && length(session$log) > 0) {
      cat("=== ALL LOGS (", length(session$log), " lines) ===\n", sep = "")
      for (i in seq_along(session$log)) {
        cat(sprintf("[%04d] %s\n", i, session$log[i]))
      }
      cat("\n")
    } else {
      cat("⚠ No logs available in session\n\n")
    }
    
    # Appinfo
    if (!is.null(session$appInfo)) {
      cat("=== APP INFO ===\n")
      print(session$appInfo)
      cat("\n")
    }
    
    # Appid
    if (!is.null(session$appId)) {
      cat("App ID:", session$appId, "\n")
      cat("You can view YARN logs with:\n")
      cat("  yarn logs -applicationId", session$appId, "\n\n")
    }
  }
  
  session
}

livy_post_statement <- function(sc, code) {
  sparklyr:::livy_log_operation(sc, code)
  
  # Create the statement
  statementResponse <- livy_curl_request(
    paste(sc$master, "sessions", sc$sessionId, "statements", sep = "/"),
    sc$config$sparklyr.connect.livy.username,
    sc$config$sparklyr.connect.livy.password,
    "POST", toJSON(list(code = jsonlite::unbox(code)))
  )
  
  if (is.null(statementResponse$id)) stop("Post statement failed")
  
  # Wait for statement to complete
  waitTimeout <- 30 * 60  # 30 minutes
  pollInterval <- 5
  commandStart <- Sys.time()
  sleepTime <- 0.001
  
  while ((statementResponse$state == "running" || statementResponse$state == "waiting" ||
    (statementResponse$state == "available" && is.null(statementResponse$output))) &&
    Sys.time() < commandStart + waitTimeout) {
    
    statementResponse <- livy_get_statement(sc, statementResponse$id)
    Sys.sleep(sleepTime)
    sleepTime <- min(pollInterval, sleepTime * 2)
  }
  
  if (statementResponse$state != "available") {
    stop("Failed to execute Livy statement with state ", statementResponse$state)
  }
  
  if (is.null(statementResponse$output)) {
    stop("Statement output is NULL")
  }
  
  if (statementResponse$output$status == "error") {
    stop(
      "Failed to execute Livy statement with error: ",
      if (is.null(statementResponse$output$evalue)) {
        jsonlite::toJSON(statementResponse)
      } else {
        statementResponse$output$evalue
      },
      "\nTraceback: ",
      paste(statementResponse$output$traceback, collapse = "")
    )
  }
  
  data <- statementResponse$output$data
  
  if (!is.null(data) && "text/plain" == names(data)[[1]]) {
    sparklyr:::livy_log_operation(sc, "\n")
    sparklyr:::livy_log_operation(sc, data[[1]])
    sparklyr:::livy_log_operation(sc, "\n")
  }
  
  data
}

livy_get_statement <- function(sc, statementId) {
  statement <- livy_curl_request(
    paste(sc$master, "sessions", sc$sessionId, "statements", statementId, sep = "/"),
    sc$config$sparklyr.connect.livy.username,
    sc$config$sparklyr.connect.livy.password,
    "GET"
  )
  
  # Only log if there's an error
  if (!is.null(statement$state) && statement$state == "error") {
    cat("\n=== STATEMENT ERROR ===\n")
    if (!is.null(statement$output)) {
      cat("Error:", statement$output$evalue, "\n")
      if (!is.null(statement$output$traceback)) {
        cat("Traceback:\n")
        cat(paste(statement$output$traceback, collapse = "\n"), "\n")
      }
    }
  }
  
  statement
}

assignInNamespace("livy_get_json", livy_get_json, ns = "sparklyr")
assignInNamespace("livy_connection_jars", livy_connection_jars, ns = "sparklyr")
assignInNamespace("livy_create_session", livy_create_session, ns = "sparklyr")
assignInNamespace("livy_destroy_session", livy_destroy_session, ns = "sparklyr")
assignInNamespace("livy_get_session", livy_get_session, ns = "sparklyr")
assignInNamespace("livy_post_statement", livy_post_statement, ns = "sparklyr")
assignInNamespace("livy_get_statement", livy_get_statement, ns = "sparklyr")

cat("✓ Patch applied (with JARs disabled)\n\n")

# ============================================================================
# CONFIGURATION
# ============================================================================

config <- spark_config()
config$sparklyr.connect.livy.username <- KNOX_USERNAME
config$sparklyr.connect.livy.password <- KNOX_PASSWORD

# Timeout de connexion
if (exists("SPARK_CONNECT_TIMEOUT") && !is.null(SPARK_CONNECT_TIMEOUT)) {
  config$sparklyr.connect.timeout <- SPARK_CONNECT_TIMEOUT
} else {
  config$sparklyr.connect.timeout <- 300
}

# Configuration Spark depuis knox_config.R
# NOTE: Pour Livy, ne pas utiliser le préfixe 'livy.' mais 'livy.session.'
if (exists("SPARK_DRIVER_MEMORY") && !is.null(SPARK_DRIVER_MEMORY)) {
  config$spark.driver.memory <- SPARK_DRIVER_MEMORY
  config$`livy.session.driverMemory` <- SPARK_DRIVER_MEMORY
}

if (exists("SPARK_EXECUTOR_MEMORY") && !is.null(SPARK_EXECUTOR_MEMORY)) {
  config$spark.executor.memory <- SPARK_EXECUTOR_MEMORY
  config$`livy.session.executorMemory` <- SPARK_EXECUTOR_MEMORY
}

if (exists("SPARK_NUM_EXECUTORS") && !is.null(SPARK_NUM_EXECUTORS)) {
  config$spark.executor.instances <- as.integer(SPARK_NUM_EXECUTORS)
  config$`livy.session.numExecutors` <- as.integer(SPARK_NUM_EXECUTORS)
}

if (exists("SPARK_EXECUTOR_CORES") && !is.null(SPARK_EXECUTOR_CORES)) {
  config$spark.executor.cores <- as.integer(SPARK_EXECUTOR_CORES)
  config$`livy.session.executorCores` <- as.integer(SPARK_EXECUTOR_CORES)
}

if (exists("SPARK_QUEUE") && !is.null(SPARK_QUEUE)) {
  config$spark.yarn.queue <- SPARK_QUEUE
  config$`livy.session.queue` <- SPARK_QUEUE
}

# Use manually installed JAR instead of trying to download from GitHub
if (exists("SPARKLYR_JAR_PATH") && !is.null(SPARKLYR_JAR_PATH) && SPARKLYR_JAR_PATH != "") {
  config$sparklyr.shell.jars <- SPARKLYR_JAR_PATH
  config$`livy.session.jars` <- SPARKLYR_JAR_PATH
  
  cat("Configuration Spark:\n")
  cat("  → JAR:", SPARKLYR_JAR_PATH, "\n")
  if (exists("SPARK_DRIVER_MEMORY")) cat("  → Driver Memory:", SPARK_DRIVER_MEMORY, "\n")
  if (exists("SPARK_EXECUTOR_MEMORY")) cat("  → Executor Memory:", SPARK_EXECUTOR_MEMORY, "\n")
  if (exists("SPARK_NUM_EXECUTORS")) cat("  → Num Executors:", SPARK_NUM_EXECUTORS, "\n")
  if (exists("SPARK_EXECUTOR_CORES")) cat("  → Executor Cores:", SPARK_EXECUTOR_CORES, "\n")
  if (exists("SPARK_QUEUE")) cat("  → YARN Queue:", SPARK_QUEUE, "\n")
  cat("\n")
} else {
  # This should not happen because we check earlier, but just in case
  config$sparklyr.livy.jar <- NULL
  config$livy.jars <- NULL
  config$sparklyr.connect.jars.default <- NULL
  config$sparklyr.shell.jars <- NULL
  cat("Configuration:\n")
  cat("  → WARNING: No JAR configured - connection will likely fail\n\n")
}

# ============================================================================
# CONNECTION
# ============================================================================

cat("Attempting connection...\n")

tryCatch({
  sc <- spark_connect(
    master = KNOX_MASTER_URL,
    method = "livy",
    version = "3.3",
    config = config
  )
  
  cat("\n✓✓✓ SUCCESS ✓✓✓\n")
  cat("Session ID:", sc$sessionId, "\n")
  
}, error = function(e) {
  cat("\n╔═══════════════════════════════════════════════════════════════════╗\n")
  cat("║                    CONNECTION FAILED                              ║\n")
  cat("╚═══════════════════════════════════════════════════════════════════╝\n\n")
  
  cat("Error:", e$message, "\n\n")
  
  cat("The complete session logs have been displayed above.\n")
  cat("Look for lines starting with 'Exception' or 'Error' in the logs.\n\n")
  
  cat("Possible actions:\n")
  cat("1. Check the exact error in the complete logs above\n")
  cat("2. If you see an 'appId', retrieve the complete YARN logs:\n")
  cat("   yarn logs -applicationId <appId>\n")
  cat("3. Check your user permissions on YARN\n")
  cat("4. Check the proxyUser configuration in Livy\n")
  cat("5. Check the available resources on the YARN cluster\n")
})
