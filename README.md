# sparklyr-livy

Solution to connect R (sparklyr) to Apache Spark via Knox Gateway and Livy on air-gapped Cloudera CDP 7.1.9 clusters (Spark 3.3.2).

## The Problem

Standard sparklyr fails to connect to Livy through Knox Gateway on air-gapped Cloudera CDP 7.1.9 clusters due to three issues:

1. **httr library incompatibility with Knox** - The R `httr` package returns empty responses when communicating through Knox Gateway
2. **Missing proxyUser** - Spark sessions run as 'livy' user instead of the authenticated Knox user, causing permission errors
3. **JAR download failure** - sparklyr tries to download its JAR from GitHub, which fails on air-gapped clusters

## The Solution

This repo provides:
- Runtime patches that replace `httr` with `system()` curl calls
- Automatic proxyUser configuration using Knox username
- Automated JAR installation on HDFS via WebHDFS (no direct HDFS access needed)

## Quick Start

### 1. Install R packages

```r
install.packages("sparklyr")
install.packages("dplyr")
install.packages("jsonlite")
```

### 2. Clone and configure

```bash
git clone https://github.com/ab2dridi/sparklyr-livy.git
cd sparklyr-livy
cp knox_config.R.template knox_config.R
```

Edit `knox_config.R` with your Knox credentials and URLs.

### 3. Install sparklyr JAR on HDFS via WebHDFS

```r
source("setup_jar.R")
```

This uploads the sparklyr JAR to your HDFS directory using WebHDFS through Knox (no direct HDFS access needed).

### 4. Connect to Spark

```r
source("sparklyr_connection.R")
```

### 5. Use Spark

```r
library(dplyr)
library(DBI)

# SQL queries
dbGetQuery(sc, "SHOW DATABASES")

# Hive tables
tbl(sc, "my_table") %>% 
  filter(date >= "2024-01-01") %>%
  collect()

# Disconnect
spark_disconnect(sc)
```

## Files

- `knox_config.R.template` - Configuration template (credentials, URLs, Spark parameters)
- `setup_jar.R` - Upload sparklyr JAR to HDFS via WebHDFS
- `sparklyr_connection.R` - Patched connection script (fixes httr, proxyUser, JAR issues)
- `examples/basic_examples.R` - Usage examples
- `PROBLEM.md` - Detailed technical analysis
- `INSTALLATION.md` - Step-by-step installation guide


## Configuration Example

```r
# knox_config.R
KNOX_USERNAME <- "your_username"
KNOX_PASSWORD <- "your_password"
KNOX_MASTER_URL <- "https://knox-host:8443/gateway/cdp-proxy-api/livy_for_spark3"
KNOX_WEBHDFS_URL <- "https://knox-host:8443/gateway/cdp-proxy-api/webhdfs/v1"

SPARK_DRIVER_MEMORY <- "4G"
SPARK_EXECUTOR_MEMORY <- "4G"
SPARK_NUM_EXECUTORS <- 2
SPARK_QUEUE <- "default"
```

## How It Works

1. **setup_jar.R** downloads the sparklyr JAR (from your R installation or GitHub) and uploads it to HDFS via WebHDFS
2. **sparklyr_connection.R** patches 7 sparklyr functions at runtime:
   - Replaces `httr` calls with `system("curl ...")` to bypass Knox incompatibility
   - Adds `proxyUser` automatically from Knox username
   - Uses HDFS JAR path instead of trying to download from GitHub

No modifications to sparklyr source code required.

## Troubleshooting

**Connection fails:** Reduce resources in `knox_config.R` (e.g., `SPARK_NUM_EXECUTORS <- 1`)

**JAR upload fails:** See `manual_jar_install.md` for manual HDFS upload

**More details:** See `PROBLEM.md` and `INSTALLATION.md`

## License

MIT License - see [LICENSE](LICENSE)

## Links

- [sparklyr documentation](https://spark.rstudio.com/)
- [Apache Livy](https://livy.apache.org/)
- [Technical problem analysis](PROBLEM.md)
