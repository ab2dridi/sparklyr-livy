# Spark Versions Compatibility

This document details Spark version compatibility for sparklyr-livy.

---

## ✅ Tested Versions

| Spark Version | Scala Version | JAR Filename | Status | Notes |
|---------------|---------------|--------------|--------|-------|
| 3.0.x | 2.12 | `sparklyr-3.0-2.12.jar` | ✅ Fully Tested | CDP 7.1.7+ |
| 3.3.x | 2.12 | `sparklyr-3.0-2.12.jar` | ✅ Fully Tested | CDP 7.1.9+ |
| 3.5.x | 2.12 | `sparklyr-3.5-2.12.jar` | ✅ Tested | Requires sparklyr 1.9+ |
| 4.0.x | 2.12 | `sparklyr-4.0-2.12.jar` | ⚠️ Beta | Spark 4.0 preview |

---

## 🔍 How to Check Your Spark Version

### Method 1: Ask Your Administrator
Contact your cluster administrator or data platform team.

### Method 2: Cloudera Manager
1. Log into Cloudera Manager
2. Go to Clusters → Spark
3. Check the version displayed

### Method 3: Via Livy (if accessible)
```bash
curl -k -u 'username:password' \
  'https://knox-host:port/gateway/cdp-proxy-api/livy/sessions' | jq
```

Look for `sparkVersion` in active sessions.

### Method 4: After Connection
```r
# After successful connection
spark_version(sc)
```

---

## 📦 JAR Download URLs

### Spark 3.0 / 3.3

**For sparklyr 1.9.x:**
```
https://github.com/sparklyr/sparklyr/releases/download/v1.9.0/sparklyr-3.0-2.12.jar
```

**For sparklyr 1.8.x:**
```
https://github.com/sparklyr/sparklyr/releases/download/v1.8.5/sparklyr-3.0-2.12.jar
```

### Spark 3.5

**For sparklyr 1.9.x:**
```
https://github.com/sparklyr/sparklyr/releases/download/v1.9.0/sparklyr-3.5-2.12.jar
```

### Spark 4.0 (Preview)

**For sparklyr 1.9.x:**
```
https://github.com/sparklyr/sparklyr/releases/download/v1.9.0/sparklyr-4.0-2.12.jar
```

---

## 🔧 Version-Specific Configuration

### For Spark 3.0 / 3.3

```r
# In knox_config.R
SPARKLYR_JAR_PATH <- "hdfs:///user/your_username/sparklyr-3.0-2.12.jar"

# In sparklyr_connection.R connection call
sc <- spark_connect(
  master = KNOX_MASTER_URL,
  method = "livy",
  version = "3.3",  # or "3.0"
  config = config
)
```

### For Spark 3.5

```r
# In knox_config.R
SPARKLYR_JAR_PATH <- "hdfs:///user/your_username/sparklyr-3.5-2.12.jar"

# In sparklyr_connection.R connection call
sc <- spark_connect(
  master = KNOX_MASTER_URL,
  method = "livy",
  version = "3.5",
  config = config
)
```

### For Spark 4.0

```r
# In knox_config.R
SPARKLYR_JAR_PATH <- "hdfs:///user/your_username/sparklyr-4.0-2.12.jar"

# In sparklyr_connection.R connection call
sc <- spark_connect(
  master = KNOX_MASTER_URL,
  method = "livy",
  version = "4.0",
  config = config
)
```

---

## ⚠️ Version Mismatch Issues

### Symptom
```
Error: No matched method found for class org.apache.spark.sql.SQLUtils.createDataFrame
```

### Cause
The JAR version doesn't match your Spark cluster version.

### Solution
1. Verify your Spark version
2. Download the correct JAR (see above)
3. Replace the JAR on HDFS:
   ```bash
   hdfs dfs -rm /user/username/sparklyr-3.0-2.12.jar
   hdfs dfs -put sparklyr-3.5-2.12.jar /user/username/
   ```
4. Update `knox_config.R`:
   ```r
   SPARKLYR_JAR_PATH <- "hdfs:///user/username/sparklyr-3.5-2.12.jar"
   ```

---

## 🏢 Cloudera CDP Version Mapping

| CDP Version | Default Spark Version | Recommended JAR |
|-------------|----------------------|-----------------|
| CDP 7.1.7 | Spark 3.0.0 | `sparklyr-3.0-2.12.jar` |
| CDP 7.1.8 | Spark 3.2.1 | `sparklyr-3.0-2.12.jar` |
| CDP 7.1.9 | Spark 3.3.2 | `sparklyr-3.0-2.12.jar` |
| CDP 7.2.x | Spark 3.5.x | `sparklyr-3.5-2.12.jar` |

**Note:** CDP clusters may have multiple Spark versions available. Check with your administrator.

---

## 📝 Scala Version Notes

All modern Cloudera Spark distributions use **Scala 2.12**.

- ✅ Use: `sparklyr-X.X-2.12.jar`
- ❌ Avoid: `sparklyr-X.X-2.11.jar` (older Spark 2.x)

**Verify Scala version:**
```bash
# On cluster node
spark-submit --version | grep -i scala
```

---

## 🔄 Upgrading Spark Versions

If your cluster is upgraded to a newer Spark version:

1. **Check new Spark version**
2. **Download new JAR** if needed
3. **Upload new JAR** to HDFS
4. **Update configuration:**
   ```r
   SPARKLYR_JAR_PATH <- "hdfs:///user/username/sparklyr-NEW-VERSION.jar"
   ```
5. **Update version in connection:**
   ```r
   spark_connect(
     master = KNOX_MASTER_URL,
     method = "livy",
     version = "NEW.VERSION",  # e.g., "3.5"
     config = config
   )
   ```
6. **Test connection**

---

## 🧪 Testing Multiple Versions

If your cluster has multiple Spark versions, you can maintain multiple JARs:

```bash
# HDFS structure
/user/your_username/
├── sparklyr-3.0-2.12.jar
├── sparklyr-3.3-2.12.jar
└── sparklyr-3.5-2.12.jar
```

Switch in `knox_config.R`:
```r
# For Spark 3.0
SPARKLYR_JAR_PATH <- "hdfs:///user/your_username/sparklyr-3.0-2.12.jar"

# For Spark 3.5
SPARKLYR_JAR_PATH <- "hdfs:///user/your_username/sparklyr-3.5-2.12.jar"
```

---

## 💡 Best Practices

1. **Match versions:** Always use a JAR matching your Spark version
2. **Test first:** Test in dev/sandbox before production
3. **Document:** Keep notes on which JAR version works with your cluster
4. **Coordinate:** Work with your data platform team for upgrades
5. **Version control:** Keep old JARs for rollback if needed

---

## 📞 Need Help?

If you're unsure which version to use:
1. Check with your cluster administrator
2. Start with Spark 3.0 JAR (most compatible)
3. Open an issue on GitHub with your cluster details

---

**Next:** [Troubleshooting Guide](troubleshooting.md)
