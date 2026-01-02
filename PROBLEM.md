# Problem Analysis: sparklyr with Knox Gateway and Livy

This document provides a detailed technical analysis of the issues preventing standard sparklyr from working with Apache Livy through Knox Gateway on air-gapped Cloudera clusters.

---

## 🔍 Environment Context

**Target Environment:**
- Cloudera CDP 7.1.9+
- Apache Spark 3.0+
- Apache Livy (Livy for Spark3)
- Knox Gateway (reverse proxy with SSL/TLS)
- Air-gapped cluster (no Internet access)

**Client Environment:**
- R 3.6+
- sparklyr 1.8+
- Standard httr, dplyr, jsonlite packages

---

## ❌ Problem 1: httr Library Incompatibility with Knox

### Symptom
```r
sc <- spark_connect(
  master = "https://knox-host:port/gateway/.../livy",
  method = "livy"
)
# Error: '!is.null(sessions$sessions)' is not TRUE
```

### Root Cause Analysis

When sparklyr calls `httr::GET()` to communicate with Livy through Knox Gateway:

```r
# Standard sparklyr code
sessions <- httr::GET(
  paste(master, "sessions", sep = "/"),
  httr::authenticate(username, password)
)
content <- httr::content(sessions, as = "parsed")
# content is empty list() instead of session data
```

**Why it fails:**
1. Knox Gateway uses SSL/TLS with potentially self-signed certificates
2. Knox acts as a reverse proxy, adding custom headers
3. httr's default SSL verification and header handling conflicts with Knox
4. The response body is empty despite HTTP 200 status code

**Verification with curl:**
```bash
# System curl works fine
curl -k -u 'username:password' \
  'https://knox-host:port/gateway/.../livy/sessions'

# Returns: {"from":0,"total":0,"sessions":[]}
```

### Why System curl Works

- `curl` handles Knox's SSL certificates correctly with `-k` flag
- `curl` doesn't apply httr's additional processing layers
- Direct HTTP/HTTPS protocol handling without R's abstractions

---

## ❌ Problem 2: Missing proxyUser Configuration

### Symptom
```
Session state: dead
YARN logs show: "User: livy is not allowed to impersonate your_username"
Or: "Permission denied: user=livy, access=WRITE, inode=/user/your_username"
```

### Root Cause Analysis

**Default Livy Behavior:**
When creating a Spark session without `proxyUser`, Livy submits the YARN application as the 'livy' service account.

**Session creation without proxyUser:**
```json
{
  "kind": "spark",
  "conf": {
    "spark.driver.memory": "4G"
  }
  // Missing: "proxyUser": "actual_user"
}
```

**Results in:**
- YARN application runs as `livy` user
- Cannot access HDFS `/user/your_username/` directories
- Cannot read Hive tables owned by `your_username`
- Permission denied errors in Spark executors

**What sparklyr should send:**
```json
{
  "kind": "spark",
  "proxyUser": "your_username",  // ← Required!
  "conf": {
    "spark.driver.memory": "4G"
  }
}
```

### Why proxyUser is Required

Knox Gateway authenticates users and passes the username to Livy. However, sparklyr doesn't automatically include this username in the `proxyUser` field when creating sessions.

**Livy's proxyUser mechanism:**
1. Receives authenticated username from Knox
2. Checks if 'livy' user is allowed to impersonate `proxyUser`
3. Submits YARN application as `proxyUser` instead of 'livy'
4. Spark session runs with correct permissions

---

## ❌ Problem 3: JAR Download Failure in Air-Gapped Environments

### Symptom
```
Session state: dead
Logs show: 
  "spark-submit start failed"
  "ClassNotFoundException: sparklyr.Backend"
```

### Root Cause Analysis

**sparklyr's JAR Download Logic:**

When connecting to Livy, sparklyr attempts to download its JAR file from GitHub:

```r
# sparklyr internal code (livy_connection_jars)
jar_url <- sprintf(
  "https://github.com/sparklyr/sparklyr/releases/download/%s/sparklyr-%s-%s.jar",
  version, spark_version, scala_version
)
# Example: https://github.com/sparklyr/sparklyr/releases/download/v1.8.5/sparklyr-3.0-2.12.jar?raw=true
```

**Session creation with GitHub JAR:**
```json
{
  "kind": "spark",
  "jars": [
    "https://github.com/sparklyr/sparklyr/releases/download/v1.8.5/sparklyr-3.0-2.12.jar?raw=true"
  ]
}
```

**What happens in air-gapped cluster:**
1. Livy receives session creation request with GitHub JAR URL
2. YARN ResourceManager tries to download JAR from GitHub
3. No Internet access → Download fails
4. spark-submit fails to start
5. Session state becomes "dead"

**Full error logs:**
```
User class threw exception: java.io.IOException: 
Failed to download https://github.com/.../sparklyr-3.0-2.12.jar
Connection timeout
```

### Why Manual JAR Installation is Required

In air-gapped environments:
- Cluster nodes cannot reach external Internet
- Must pre-install JARs on HDFS or local filesystem
- Livy can access HDFS paths: `hdfs:///user/username/sparklyr-3.0-2.12.jar`
- Or local filesystem paths: `file:///opt/jars/sparklyr-3.0-2.12.jar`

---

## 🔧 Solutions Applied

### Solution 1: Replace httr with System curl

**Approach:** Bypass httr completely by using system curl commands.

```r
livy_curl_request <- function(url, username, password, method = "GET", body = NULL) {
  auth <- paste0(username, ":", password)
  auth_escaped <- gsub("'", "'\\''", auth)
  
  if (method == "GET") {
    cmd <- sprintf("curl -s -k -u '%s' '%s'", auth_escaped, url)
  } else if (method == "POST") {
    body_escaped <- gsub("'", "'\\''", body)
    cmd <- sprintf(
      "curl -s -k -u '%s' -X POST -H 'Content-Type: application/json' -d '%s' '%s'",
      auth_escaped, body_escaped, url
    )
  } else if (method == "DELETE") {
    cmd <- sprintf("curl -s -k -u '%s' -X DELETE '%s'", auth_escaped, url)
  }
  
  result <- system(cmd, intern = TRUE)
  parsed <- jsonlite::fromJSON(paste(result, collapse = "\n"))
  return(parsed)
}
```

**Key flags:**
- `-s`: Silent mode (no progress bar)
- `-k`: Insecure (ignore SSL certificate validation)
- `-u`: Basic authentication
- `-X POST/DELETE`: HTTP method
- `-H`: Headers
- `-d`: POST data

**Patched function:**
```r
livy_get_json <- function(url, config) {
  livy_curl_request(
    url, 
    config$sparklyr.connect.livy.username, 
    config$sparklyr.connect.livy.password, 
    "GET"
  )
}

# Replace in sparklyr namespace
assignInNamespace("livy_get_json", livy_get_json, ns = "sparklyr")
```

### Solution 2: Automatic proxyUser Configuration

**Approach:** Automatically inject proxyUser into session creation requests.

```r
livy_create_session <- function(master, config) {
  data <- list(
    kind = jsonlite::unbox("spark"),
    conf = sparklyr:::livy_config_get(master, config)
  )
  
  session_params <- connection_config(
    list(master = master, config = config),
    prefix = "livy.", 
    not_prefix = "livy.session."
  )
  
  # Automatic proxyUser injection
  if (is.null(session_params$proxyUser)) {
    session_params$proxyUser <- jsonlite::unbox(
      config$sparklyr.connect.livy.username
    )
  }
  
  if (length(session_params) > 0) {
    data <- append(data, session_params)
  }
  
  # Create session with proxyUser
  content <- livy_curl_request(
    paste(master, "sessions", sep = "/"),
    config$sparklyr.connect.livy.username,
    config$sparklyr.connect.livy.password,
    "POST", 
    toJSON(data)
  )
  
  return(content)
}

assignInNamespace("livy_create_session", livy_create_session, ns = "sparklyr")
```

**Result:** Sessions now run as the authenticated Knox user.

### Solution 3: Manual JAR on HDFS

**Approach:** Use pre-installed JAR on HDFS instead of GitHub URL.

```r
livy_connection_jars <- function(config, version, scala_version) {
  # Return manually configured JAR path instead of GitHub URL
  if (exists("SPARKLYR_JAR_PATH", envir = .GlobalEnv) && 
      !is.null(SPARKLYR_JAR_PATH) && 
      SPARKLYR_JAR_PATH != "") {
    return(SPARKLYR_JAR_PATH)
  }
  return(NULL)
}

assignInNamespace("livy_connection_jars", livy_connection_jars, ns = "sparklyr")
```

**Configuration:**
```r
# In knox_config.R
SPARKLYR_JAR_PATH <- "hdfs:///user/your_username/sparklyr-3.0-2.12.jar"

config <- spark_config()
config$sparklyr.shell.jars <- SPARKLYR_JAR_PATH
config$`livy.session.jars` <- SPARKLYR_JAR_PATH
```

**Result:** Livy uses HDFS JAR instead of trying to download from GitHub.

---

## 🧪 Testing & Validation

### Verify httr Replacement
```r
# Test direct curl request
url <- "https://knox-host:port/gateway/.../livy/sessions"
result <- livy_curl_request(url, username, password, "GET")
print(result)  # Should show sessions list
```

### Verify proxyUser
```r
# After connection, check session details
session <- livy_get_session(sc)
print(session$proxyUser)  # Should show your username
```

### Verify JAR Location
```bash
# Check HDFS
hdfs dfs -ls /user/your_username/sparklyr-*.jar

# Or via WebHDFS
curl -k -u 'user:pass' \
  'https://knox.../webhdfs/v1/user/your_username/sparklyr-3.0-2.12.jar?op=GETFILESTATUS'
```

---

## 📊 Impact Analysis

### Performance
- ✅ **No impact:** System curl has similar performance to httr
- ✅ **Network:** Same number of HTTP requests
- ✅ **Latency:** Comparable response times

### Compatibility
- ✅ **sparklyr versions:** 1.8.x, 1.9.x tested
- ✅ **Spark versions:** 3.0, 3.3, 3.5, 4.0 tested
- ✅ **R versions:** 3.6, 4.0+ tested
- ⚠️ **Platform:** Requires Unix-like system with curl installed

### Limitations
- ⚠️ **Windows:** Requires curl.exe in PATH or WSL
- ⚠️ **curl dependency:** System curl must be installed
- ⚠️ **Runtime patching:** Uses `assignInNamespace()` (not permanent)

---

## 🔮 Alternative Solutions (Not Implemented)

### 1. Modify httr Configuration
**Approach:** Configure httr to work with Knox.
```r
httr::set_config(httr::config(ssl_verifypeer = FALSE))
```
**Status:** ❌ Tested, still fails with Knox Gateway

### 2. Use Different HTTP Library
**Approach:** Replace httr with curl or httr2.
**Status:** ❌ Would require modifying sparklyr source code

### 3. Knox Configuration Changes
**Approach:** Modify Knox Gateway to be more httr-friendly.
**Status:** ❌ Requires admin access, affects all services

### 4. Direct Livy Access
**Approach:** Bypass Knox, connect directly to Livy.
**Status:** ❌ Not allowed in secure environments

---

## 📝 Conclusion

The combination of three issues (httr/Knox incompatibility, missing proxyUser, JAR download failure) prevents standard sparklyr from working with Knox Gateway on air-gapped Cloudera clusters.

Our solution uses **runtime patching** to:
1. Replace httr with system curl
2. Auto-inject proxyUser
3. Use pre-installed HDFS JARs

This approach requires no changes to sparklyr source code and provides a complete working solution for air-gapped environments.

---

**For implementation details, see [sparklyr_connection.R](sparklyr_connection.R)**
