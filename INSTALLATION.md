# Installation Guide

Complete step-by-step guide to install and configure sparklyr-livy for Knox Gateway and Livy connections on air-gapped Cloudera CDP 7.1.9 clusters (Spark 3.3.2).

---

## 📋 Prerequisites Checklist

Before starting, ensure you have:

### R Environment
- [ ] R version 3.6 or higher installed
- [ ] RStudio (optional but recommended)
- [ ] Internet access for initial package installation

### Cluster Access
- [ ] Knox Gateway URL
- [ ] Knox username and password
- [ ] YARN permissions to submit Spark applications
- [ ] HDFS quota in `/user/your_username/`

### Network
- [ ] HTTPS access to Knox Gateway
- [ ] WebHDFS accessible through Knox (for JAR upload)

---

## 🔧 Installation Steps

### Step 1: Install R Packages

Open R or RStudio and install required packages:

```r
# Install sparklyr
install.packages("sparklyr")

# Install dependencies
install.packages("dplyr")
install.packages("jsonlite")
install.packages("DBI")

# Verify installation
library(sparklyr)
packageVersion("sparklyr")  # Should be 1.8.0 or higher
```

**Expected output:**
```
[1] '1.9.0'
```

---

### Step 2: Clone or Download This Repository

Choose one method:

#### Option A: Using Git
```bash
git clone https://github.com/ab2dridi/sparklyr-livy.git
cd sparklyr-livy
```

#### Option B: Download ZIP
1. Go to https://github.com/ab2dridi/sparklyr-livy
2. Click "Code" → "Download ZIP"
3. Extract to your working directory

#### Option C: Download Individual Files
Download these essential files:
- `knox_config.R.template`
- `sparklyr_connection.R`
- `setup_jar.R`
- `examples/basic_examples.R`

---

### Step 3: Configure Your Credentials

#### 3.1 Copy Configuration Template

```bash
# In the sparklyr-livy directory
cp knox_config.R.template knox_config.R
```

#### 3.2 Edit knox_config.R

Open `knox_config.R` in your favorite text editor and configure:

```r
# ============================================================================
# KNOX CREDENTIALS
# ============================================================================

KNOX_USERNAME <- "your_username"        # Your Knox username
KNOX_PASSWORD <- "your_password"        # Your Knox password

# ============================================================================
# KNOX URLS
# ============================================================================

# Livy URL - Replace hostname and port with your cluster details
KNOX_MASTER_URL <- "https://knox-host.company.com:8443/gateway/cdp-proxy-api/livy_for_spark3"

# WebHDFS URL - Same host and port, different path
KNOX_WEBHDFS_URL <- "https://knox-host.company.com:8443/gateway/cdp-proxy-api/webhdfs/v1"

# ============================================================================
# SPARK CONFIGURATION
# ============================================================================

# Adjust these based on your cluster resources and requirements

# Driver memory (common values: "2G", "4G", "8G")
SPARK_DRIVER_MEMORY <- "4G"

# Executor memory (common values: "2G", "4G", "8G")
SPARK_EXECUTOR_MEMORY <- "4G"

# Number of executors (start with 2, increase if needed)
SPARK_NUM_EXECUTORS <- 2

# Cores per executor (typically 2-4)
SPARK_EXECUTOR_CORES <- 2

# YARN queue (ask your cluster admin for available queues)
SPARK_QUEUE <- "default"

# Connection timeout in seconds
SPARK_CONNECT_TIMEOUT <- 300

# ============================================================================
# JAR PATH
# ============================================================================

# This will be configured automatically by setup_jar.R
# Don't modify unless you're manually installing the JAR
SPARKLYR_JAR_PATH <- ""
```

#### 3.3 Find Your Knox URLs

**How to get your Knox Master URL:**
1. Ask your cluster administrator, OR
2. Check your Cloudera Manager → Knox → Configurations
3. Typical format: `https://<knox-host>:<port>/gateway/<topology>/livy_for_spark3`

**Common topology names:**
- `cdp-proxy` or `cdp-proxy-api`
- `default`
- Your organization's custom topology

**Example URLs:**
```
# Production cluster
KNOX_MASTER_URL <- "https://knox.prod.company.com:8443/gateway/cdp-proxy-api/livy_for_spark3"
KNOX_WEBHDFS_URL <- "https://knox.prod.company.com:8443/gateway/cdp-proxy-api/webhdfs/v1"

# Development cluster
KNOX_MASTER_URL <- "https://knox.dev.company.com:8443/gateway/default/livy_for_spark3"
KNOX_WEBHDFS_URL <- "https://knox.dev.company.com:8443/gateway/default/webhdfs/v1"
```

#### 3.4 Protect Your Credentials

```bash
# Restrict file permissions (Unix/Linux/macOS)
chmod 600 knox_config.R

# Add to .gitignore to prevent accidental commits
echo "knox_config.R" >> .gitignore
```

---

### Step 4: Install sparklyr JAR on HDFS

The sparklyr JAR file is required for Spark to load R-specific functionality. In air-gapped environments, we must pre-install it on HDFS.

#### 4.1 Automated Installation (Recommended)

```r
# In R console, from the sparklyr-livy directory
source("setup_jar.R")
```

**What this script does:**
1. ✅ Loads your configuration from `knox_config.R`
2. ✅ Detects your Spark version (3.0, 3.3, 3.5, or 4.0)
3. ✅ Checks if JAR already exists on HDFS
4. ✅ Downloads appropriate JAR (from R installation or GitHub)
5. ✅ Creates your HDFS directory if needed
6. ✅ Uploads JAR via WebHDFS through Knox
7. ✅ Verifies successful upload
8. ✅ Updates `knox_config.R` with HDFS path

**Expected output:**
```
╔═══════════════════════════════════════════════════════════════════╗
║          INSTALLATION JAR SPARKLYR VIA WEBHDFS                    ║
╚═══════════════════════════════════════════════════════════════════╝

═══ 1. LOADING CONFIGURATION ═══

✓ Configuration loaded
  Username: your_username
  WebHDFS URL: https://knox.../webhdfs/v1

═══ 2. JAR PARAMETERS ═══

sparklyr version: 1.9.0
JAR filename: sparklyr-3.0-2.12.jar
HDFS destination: /user/your_username/sparklyr-3.0-2.12.jar

═══ 3. CHECKING HDFS ═══

→ JAR does not exist yet

═══ 4. RETRIEVING JAR ═══

✓ JAR found in sparklyr installation
  Path: /usr/local/lib/R/site-library/sparklyr/java/sparklyr-3.0-2.12.jar
✓ Local copy created

JAR size: 7.8 Mo

═══ 5. CREATING HDFS DIRECTORY ═══

✓ HDFS directory verified/created: /user/your_username

═══ 6. UPLOADING JAR VIA WEBHDFS ═══

This may take a few minutes...
→ Direct upload (without redirect)
✓ Upload complete

═══ 7. VERIFYING UPLOAD ═══

✓ JAR verified on HDFS
  Path: /user/your_username/sparklyr-3.0-2.12.jar
  Size: 7.8 Mo

═══ 8. UPDATING CONFIGURATION ═══

Add this line to knox_config.R:

  SPARKLYR_JAR_PATH <- 'hdfs:///user/your_username/sparklyr-3.0-2.12.jar'

Do you want me to add it automatically? (Y/n): Y
✓ Configuration updated automatically

╔═══════════════════════════════════════════════════════════════════╗
║                  INSTALLATION SUCCESSFUL!                         ║
╚═══════════════════════════════════════════════════════════════════╝
```

#### 4.2 Manual Installation (If WebHDFS Fails)

If the automated script fails, see [docs/manual_jar_install.md](docs/manual_jar_install.md) for manual installation instructions.

**Quick manual method:**
```bash
# 1. Find the JAR in your R installation
R -e "system.file('java', package = 'sparklyr')"
# Example output: /usr/local/lib/R/site-library/sparklyr/java

# 2. List available JARs
ls /usr/local/lib/R/site-library/sparklyr/java/*.jar

# 3. Copy to HDFS (requires HDFS access on the cluster)
hdfs dfs -put sparklyr-3.0-2.12.jar /user/your_username/

# 4. Update knox_config.R
SPARKLYR_JAR_PATH <- "hdfs:///user/your_username/sparklyr-3.0-2.12.jar"
```

---

### Step 5: Test Connection

#### 5.1 Connect to Spark

```r
# In R console, from the sparklyr-livy directory
source("sparklyr_connection.R")
```

**Expected output (success):**
```
╔═══════════════════════════════════════════════════════════════════╗
║          CLEANUP AND CLEAN SESSION STARTUP                        ║
╚═══════════════════════════════════════════════════════════════════╝

1. Detaching packages...
  ✓ sparklyr detached
  ✓ jsonlite detached

2. Environment cleanup...
  ✓ Variables removed

3. Garbage collector cleanup...
  ✓ Memory cleaned

4. Reloading packages...
  ✓ Packages loaded with clean state

═══════════════════════════════════════════════════════════════════

Loading configuration...
  ✓ Configuration loaded from knox_config.R
  ✓ Username: your_username
  ✓ URL: https://knox.../livy_for_spark3
  ✓ JAR Path: hdfs:///user/your_username/sparklyr-3.0-2.12.jar

═══════════════════════════════════════════════════════════════════

Applying patch...
✓ Patch applied

Configuration Spark:
  → JAR: hdfs:///user/your_username/sparklyr-3.0-2.12.jar
  → Driver Memory: 4G
  → Executor Memory: 4G
  → Num Executors: 2
  → Executor Cores: 2
  → YARN Queue: default

Attempting connection...
→ Using proxyUser: your_username

=== SESSION CREATION - BODY JSON ===
{
  "kind": "spark",
  "proxyUser": "your_username",
  "jars": ["hdfs:///user/your_username/sparklyr-3.0-2.12.jar"],
  "conf": {
    "spark.driver.memory": "4G",
    "spark.executor.memory": "4G"
  },
  "driverMemory": "4G",
  "executorMemory": "4G",
  "numExecutors": 2,
  "executorCores": 2,
  "queue": "default"
}

=== SESSION STATE: starting ===
=== SESSION STATE: idle ===

✓✓✓ SUCCESS ✓✓✓
Session ID: 123
```

You now have a working Spark connection object `sc`!

#### 5.2 Run a Simple Test

```r
# Test with a simple query
library(DBI)
result <- dbGetQuery(sc, "SELECT 'Hello from Spark!' as message")
print(result)
```

**Expected output:**
```
           message
1 Hello from Spark!
```

#### 5.3 Verify Spark Connection

```r
# Check connection status
connection_is_open(sc)  # Should return TRUE

# Get Spark version
spark_version(sc)  # Example: "3.3.2"

# View session details
spark_connection_info <- list(
  session_id = sc$sessionId,
  master = sc$master,
  version = spark_version(sc)
)
print(spark_connection_info)
```

---

### Step 6: Run Examples

Try the provided examples:

```r
# Basic sparklyr operations
source("examples/basic_examples.R")

# Working with Hive tables
source("examples/hive_tables.R")

# SQL queries
source("examples/sql_queries.R")

# Data transformations with dplyr
source("examples/data_transformations.R")
```

---

## 🔄 Daily Usage Workflow

Once installation is complete, your daily workflow is simple:

```r
# 1. Connect to Spark
source("sparklyr_connection.R")

# 2. Do your work
library(dplyr)
my_data <- tbl(sc, "database.table_name") %>%
  filter(date >= "2024-01-01") %>%
  collect()

# 3. Disconnect when done
spark_disconnect(sc)
```

---

## ⚙️ Configuration Tuning

### Adjust Resources Based on Workload

Edit `knox_config.R`:

**For small exploratory queries:**
```r
SPARK_DRIVER_MEMORY <- "2G"
SPARK_EXECUTOR_MEMORY <- "2G"
SPARK_NUM_EXECUTORS <- 1
SPARK_EXECUTOR_CORES <- 2
```

**For medium data processing:**
```r
SPARK_DRIVER_MEMORY <- "4G"
SPARK_EXECUTOR_MEMORY <- "4G"
SPARK_NUM_EXECUTORS <- 4
SPARK_EXECUTOR_CORES <- 2
```

**For large-scale analytics:**
```r
SPARK_DRIVER_MEMORY <- "8G"
SPARK_EXECUTOR_MEMORY <- "8G"
SPARK_NUM_EXECUTORS <- 8
SPARK_EXECUTOR_CORES <- 4
```

### Change YARN Queue

If you have access to different YARN queues:

```r
# Development queue
SPARK_QUEUE <- "dev"

# Production queue with higher priority
SPARK_QUEUE <- "production"

# Dedicated data science queue
SPARK_QUEUE <- "datascience"
```

Ask your cluster administrator for available queues and their resource limits.

---

## 🐛 Troubleshooting Installation

### Issue: "Cannot find knox_config.R"

**Solution:**
```bash
cp knox_config.R.template knox_config.R
# Then edit knox_config.R with your credentials
```

### Issue: "Package 'sparklyr' is not installed"

**Solution:**
```r
install.packages("sparklyr")
library(sparklyr)
```

### Issue: "KNOX_WEBHDFS_URL must be defined"

**Solution:** Add to `knox_config.R`:
```r
KNOX_WEBHDFS_URL <- "https://knox-host:port/gateway/topology/webhdfs/v1"
```

### Issue: "Failed to download JAR from GitHub"

**Cause:** No Internet access on your machine.

**Solution:** Use the JAR from your local R installation:
```r
# Find local JAR
jar_path <- system.file("java", package = "sparklyr")
list.files(jar_path, pattern = "*.jar", full.names = TRUE)

# Then run setup_jar.R which will detect and use local JAR
source("setup_jar.R")
```

### Issue: "Session state is dead"

**Possible causes:**
1. Wrong YARN queue
2. Insufficient resources
3. JAR not found on HDFS

**Solution:** Check the complete logs displayed by `sparklyr_connection.R` and see [docs/troubleshooting.md](docs/troubleshooting.md).

---

## ✅ Installation Complete!

You have successfully installed sparklyr-livy! Next steps:

1. **Learn:** Review the [examples/](examples/) directory
2. **Explore:** Try [docs/spark_versions.md](docs/spark_versions.md) for version details
3. **Troubleshoot:** Bookmark [docs/troubleshooting.md](docs/troubleshooting.md)
4. **Share:** Help your colleagues install using this guide

---

**Need help? Open an issue on GitHub or check the troubleshooting guide.**
