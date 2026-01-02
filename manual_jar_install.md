# Manual JAR Installation Methods

This guide describes alternative methods to install the sparklyr JAR on HDFS when the automated `setup_jar.R` script cannot be used.

## Environment

- **Cloudera CDP**: 7.1.9
- **Spark**: 3.3.2 (or 3.x versions)
- **Scala**: 2.12

## JAR Version Selection

For **Spark 3.3.2** on Cloudera CDP 7.1.9, you should use one of these JARs (to be tested):

- `sparklyr-3.0-2.12.jar` (try this first)
- `sparklyr-3.5-2.12.jar` (alternative to test)

> **Note**: The exact compatibility between sparklyr JAR versions and Spark 3.3.2 needs to be tested in your environment. Start with `sparklyr-3.0-2.12.jar` and if you encounter issues, try `sparklyr-3.5-2.12.jar`.

## Method 1: WebHDFS via Knox (Recommended)

This method uses WebHDFS through Knox Gateway without requiring direct HDFS access or edge node access.

### Step 1: Get the JAR

Find the JAR in your local R sparklyr installation:

```bash
R --slave -e "system.file('java', 'sparklyr-3.0-2.12.jar', package='sparklyr')"
```

Or download from GitHub:

```bash
# For Spark 3.0
wget https://github.com/sparklyr/sparklyr/releases/download/v1.8.5/sparklyr-3.0-2.12.jar

# For Spark 3.5 (alternative)
wget https://github.com/sparklyr/sparklyr/releases/download/v1.8.5/sparklyr-3.5-2.12.jar
```

### Step 2: Create HDFS directory via WebHDFS

```bash
curl -k -u "username:password" -X PUT \
  "https://knox_host:8443/gateway/cdp-proxy-api/webhdfs/v1/user/username/sparklyr?op=MKDIRS"
```

### Step 3: Get upload location

```bash
curl -k -i -u "username:password" -X PUT \
  "https://knox_host:8443/gateway/cdp-proxy-api/webhdfs/v1/user/username/sparklyr/sparklyr-3.0-2.12.jar?op=CREATE&overwrite=true"
```

This returns a `Location:` header with the upload URL.

### Step 4: Upload the JAR

```bash
curl -k -u "username:password" -X PUT -T sparklyr-3.0-2.12.jar \
  "LOCATION_URL_FROM_STEP_3"
```

### Step 5: Configure knox_config.R

```r
SPARKLYR_JAR_PATH <- "hdfs:///user/username/sparklyr/sparklyr-3.0-2.12.jar"
```

## Method 2: Direct HDFS (if you have access)

If you have access to an edge node with HDFS client:

```bash
# Create directory
hdfs dfs -mkdir -p /user/your_username/sparklyr

# Upload JAR
hdfs dfs -put sparklyr-3.0-2.12.jar /user/your_username/sparklyr/

# Verify
hdfs dfs -ls /user/your_username/sparklyr/
```

Then configure:

```r
SPARKLYR_JAR_PATH <- "hdfs:///user/your_username/sparklyr/sparklyr-3.0-2.12.jar"
```

## Method 3: Use existing JAR on cluster

If sparklyr JARs are already available on your cluster (some Cloudera deployments include them):

```bash
# Search for existing JARs
find /opt/cloudera/parcels -name "sparklyr*.jar" 2>/dev/null
```

If found, use the file:// protocol:

```r
SPARKLYR_JAR_PATH <- "file:///opt/cloudera/parcels/CDH/jars/sparklyr-3.0-2.12.jar"
```

## Verification

After installation, verify the JAR is accessible:

### Via WebHDFS:

```bash
curl -k -u "username:password" \
  "https://knox_host:8443/gateway/cdp-proxy-api/webhdfs/v1/user/username/sparklyr/sparklyr-3.0-2.12.jar?op=GETFILESTATUS"
```

### Via HDFS:

```bash
hdfs dfs -ls /user/your_username/sparklyr/sparklyr-3.0-2.12.jar
```

## Troubleshooting

### JAR not found error

If you get "JAR not found" when connecting:

1. Check the path is correct in `knox_config.R`
2. Verify HDFS path format: `hdfs:///user/...` (three slashes)
3. Verify file permissions: `hdfs dfs -ls -h /user/your_username/sparklyr/`

### Wrong Spark version

If you get Spark version compatibility errors:

1. Try the alternative JAR version (switch between `sparklyr-3.0-2.12.jar` and `sparklyr-3.5-2.12.jar`)
2. Check Spark version: `spark-submit --version`
3. Ensure Scala version matches (2.12 for Spark 3.x)

### WebHDFS upload fails

Common issues:

- **403 Forbidden**: Check Knox credentials and permissions
- **404 Not Found**: Verify KNOX_WEBHDFS_URL is correct
- **Connection refused**: Check Knox service is running and accessible

## Additional Notes

- JAR size is typically 5-10 MB
- Upload time depends on network speed (usually < 1 minute)
- The JAR is shared across all your Spark sessions
- You only need to upload once per Spark version
