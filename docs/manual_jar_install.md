# Manual JAR Installation Guide

If automated WebHDFS upload via `setup_jar.R` fails, you can manually install the sparklyr JAR using one of these methods.

---

## Method 1: Direct HDFS Access (On Cluster Node)

If you have SSH access to a cluster node with HDFS client:

### Step 1: Download JAR

On a machine with Internet access:

**For Spark 3.0:**
```bash
wget https://github.com/sparklyr/sparklyr/releases/download/v1.9.0/sparklyr-3.0-2.12.jar
```

**For Spark 3.5:**
```bash
wget https://github.com/sparklyr/sparklyr/releases/download/v1.9.0/sparklyr-3.5-2.12.jar
```

### Step 2: Transfer to Cluster

```bash
# Using scp
scp sparklyr-3.0-2.12.jar username@cluster-host:~/

# Or using any file transfer method your organization uses
```

### Step 3: Upload to HDFS

```bash
# SSH to cluster node
ssh username@cluster-host

# Create your HDFS directory
hdfs dfs -mkdir -p /user/your_username

# Upload JAR
hdfs dfs -put sparklyr-3.0-2.12.jar /user/your_username/

# Verify upload
hdfs dfs -ls /user/your_username/sparklyr-3.0-2.12.jar
```

### Step 4: Update Configuration

In `knox_config.R`:
```r
SPARKLYR_JAR_PATH <- "hdfs:///user/your_username/sparklyr-3.0-2.12.jar"
```

---

## Method 2: Using R's Local JAR

If you have sparklyr installed locally, you can use its JAR directly:

### Step 1: Find Local JAR

```r
# In R console
jar_dir <- system.file("java", package = "sparklyr")
jar_files <- list.files(jar_dir, pattern = "*.jar", full.names = TRUE)
print(jar_files)
```

Example output:
```
[1] "/usr/local/lib/R/site-library/sparklyr/java/sparklyr-3.0-2.12.jar"
[2] "/usr/local/lib/R/site-library/sparklyr/java/sparklyr-3.3-2.12.jar"
```

### Step 2: Upload via WebHDFS with curl

```bash
# Set variables
KNOX_HOST="your-knox-host"
KNOX_PORT="8443"
KNOX_USER="your_username"
KNOX_PASS="your_password"
JAR_FILE="/usr/local/lib/R/site-library/sparklyr/java/sparklyr-3.0-2.12.jar"
HDFS_PATH="/user/your_username/sparklyr-3.0-2.12.jar"

# Create HDFS directory
curl -k -u "${KNOX_USER}:${KNOX_PASS}" -X PUT \
  "https://${KNOX_HOST}:${KNOX_PORT}/gateway/cdp-proxy-api/webhdfs/v1/user/${KNOX_USER}?op=MKDIRS"

# Get redirect URL
REDIRECT_URL=$(curl -k -i -u "${KNOX_USER}:${KNOX_PASS}" -X PUT \
  "https://${KNOX_HOST}:${KNOX_PORT}/gateway/cdp-proxy-api/webhdfs/v1${HDFS_PATH}?op=CREATE&overwrite=true" \
  2>&1 | grep -i '^Location:' | cut -d' ' -f2 | tr -d '\r')

# Upload file
curl -k -u "${KNOX_USER}:${KNOX_PASS}" -X PUT -T "${JAR_FILE}" "${REDIRECT_URL}"

# Verify
curl -k -u "${KNOX_USER}:${KNOX_PASS}" \
  "https://${KNOX_HOST}:${KNOX_PORT}/gateway/cdp-proxy-api/webhdfs/v1${HDFS_PATH}?op=GETFILESTATUS"
```

---

## Method 3: Ask Your Administrator

If you don't have direct HDFS access or WebHDFS doesn't work:

1. **Download the JAR** (on a machine with Internet):
   - https://github.com/sparklyr/sparklyr/releases

2. **Provide to your administrator:**
   - JAR file: `sparklyr-3.0-2.12.jar` (or appropriate version)
   - Destination: `/user/your_username/sparklyr-3.0-2.12.jar`

3. **Request:**
   ```
   Please upload this JAR to HDFS:
   hdfs dfs -put sparklyr-3.0-2.12.jar /user/YOUR_USERNAME/
   ```

4. **Update your configuration** once done.

---

## Spark Version Selection

Choose the JAR matching your Spark cluster version:

| Spark Version | JAR Filename | Download URL |
|---------------|--------------|--------------|
| 3.0.x | `sparklyr-3.0-2.12.jar` | https://github.com/sparklyr/sparklyr/releases/download/v1.9.0/sparklyr-3.0-2.12.jar |
| 3.3.x | `sparklyr-3.0-2.12.jar` | Same as 3.0 |
| 3.5.x | `sparklyr-3.5-2.12.jar` | https://github.com/sparklyr/sparklyr/releases/download/v1.9.0/sparklyr-3.5-2.12.jar |
| 4.0.x | `sparklyr-4.0-2.12.jar` | https://github.com/sparklyr/sparklyr/releases/download/v1.9.0/sparklyr-4.0-2.12.jar |

**How to check your Spark version:**
Ask your cluster administrator or check Cloudera Manager.

---

## Verification

After uploading, verify the JAR is accessible:

### Via WebHDFS:
```bash
curl -k -u 'username:password' \
  'https://knox-host:port/gateway/cdp-proxy-api/webhdfs/v1/user/username/sparklyr-3.0-2.12.jar?op=GETFILESTATUS'
```

Expected response:
```json
{
  "FileStatus": {
    "length": 8179842,
    "type": "FILE",
    "path": "/user/username/sparklyr-3.0-2.12.jar"
  }
}
```

### Via HDFS CLI (on cluster):
```bash
hdfs dfs -ls /user/username/sparklyr-3.0-2.12.jar
```

Expected output:
```
-rw-r--r--   3 username hadoop    8179842 2026-01-02 10:30 /user/username/sparklyr-3.0-2.12.jar
```

---

## Troubleshooting

### Permission Denied

```bash
# Check permissions
hdfs dfs -ls -d /user/username

# Fix if needed (on cluster with HDFS access)
hdfs dfs -chown username:hadoop /user/username
hdfs dfs -chmod 755 /user/username
```

### JAR Not Found in Livy

Ensure the path in `knox_config.R` uses the correct prefix:
```r
# Correct formats:
SPARKLYR_JAR_PATH <- "hdfs:///user/username/sparklyr-3.0-2.12.jar"
# OR
SPARKLYR_JAR_PATH <- "hdfs://namenode:8020/user/username/sparklyr-3.0-2.12.jar"
```

### Wrong JAR Version

If you see errors like "ClassNotFoundException" or version mismatches:
1. Verify your Spark version
2. Download the matching JAR
3. Replace the old JAR on HDFS
4. Update `SPARKLYR_JAR_PATH` if filename changed

---

## Next Steps

Once the JAR is installed:

1. **Update configuration:**
   ```r
   # In knox_config.R
   SPARKLYR_JAR_PATH <- "hdfs:///user/your_username/sparklyr-3.0-2.12.jar"
   ```

2. **Test connection:**
   ```r
   source("sparklyr_connection.R")
   ```

3. **If successful, you're done!** If not, check [troubleshooting.md](troubleshooting.md).
