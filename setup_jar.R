# ============================================================================
# INSTALLATION DU JAR SPARKLYR VIA WEBHDFS
# ============================================================================
# Ce script télécharge et installe le JAR sparklyr sur HDFS via WebHDFS
# WebHDFS utilise les mêmes credentials Knox que la connexion Livy

library(jsonlite)

cat("╔═══════════════════════════════════════════════════════════════════╗\n")
cat("║          INSTALLATION JAR SPARKLYR VIA WEBHDFS                    ║\n")
cat("╚═══════════════════════════════════════════════════════════════════╝\n\n")

# ============================================================================
# 1. CHARGEMENT DE LA CONFIGURATION
# ============================================================================

cat("═══ 1. CHARGEMENT DE LA CONFIGURATION ═══\n\n")

config_file <- "knox_config.R"
if (!file.exists(config_file)) {
  stop(
    "Fichier de configuration '", config_file, "' introuvable!\n\n",
    "Créez le fichier knox_config.R avec:\n",
    "  KNOX_USERNAME <- 'votre_username'\n",
    "  KNOX_PASSWORD <- 'votre_password'\n",
    "  KNOX_WEBHDFS_URL <- 'https://hostname_knox:port_knox/gateway/cdp-proxy-api/webhdfs/v1'\n"
  )
}

source(config_file)

# Vérifications
if (!exists("KNOX_USERNAME") || !exists("KNOX_PASSWORD")) {
  stop("KNOX_USERNAME et KNOX_PASSWORD doivent être définis dans knox_config.R")
}

if (!exists("KNOX_WEBHDFS_URL")) {
  stop("KNOX_WEBHDFS_URL doit être défini dans knox_config.R\n",
       "Exemple: KNOX_WEBHDFS_URL <- 'https://hostname:port/gateway/cdp-proxy-api/webhdfs/v1'")
}

cat("✓ Configuration chargée\n")
cat("  Username:", KNOX_USERNAME, "\n")
cat("  WebHDFS URL:", KNOX_WEBHDFS_URL, "\n\n")

# ============================================================================
# 2. PARAMÈTRES DU JAR
# ============================================================================

cat("═══ 2. PARAMÈTRES DU JAR ═══\n\n")

# Version de sparklyr installée
sparklyr_version <- packageVersion("sparklyr")
cat("Version sparklyr installée:", as.character(sparklyr_version), "\n")

# Choix de la version Spark (dépend de votre cluster)
SPARK_VERSION <- "3.0"  # Changez si nécessaire : "3.0", "3.3", "3.5", "4.0"
SCALA_VERSION <- "2.12"

# Nom du JAR
jar_filename <- sprintf("sparklyr-%s-%s.jar", SPARK_VERSION, SCALA_VERSION)
cat("Nom du JAR:", jar_filename, "\n")

# Chemin HDFS de destination
hdfs_dir <- sprintf("/user/%s", KNOX_USERNAME)
hdfs_jar_path <- sprintf("%s/%s", hdfs_dir, jar_filename)
cat("Destination HDFS:", hdfs_jar_path, "\n\n")

# ============================================================================
# 3. VÉRIFICATION SI LE JAR EXISTE DÉJÀ
# ============================================================================

cat("═══ 3. VÉRIFICATION SUR HDFS ═══\n\n")

webhdfs_check_url <- sprintf(
  "%s%s?op=GETFILESTATUS&user.name=%s",
  KNOX_WEBHDFS_URL,
  hdfs_jar_path,
  KNOX_USERNAME
)

auth <- paste0(KNOX_USERNAME, ":", KNOX_PASSWORD)
auth_escaped <- gsub("'", "'\\''", auth)

check_cmd <- sprintf(
  "curl -s -k -u '%s' '%s'",
  auth_escaped,
  webhdfs_check_url
)

check_result <- system(check_cmd, intern = TRUE, ignore.stderr = TRUE)

if (length(check_result) > 0) {
  check_json <- tryCatch(
    fromJSON(paste(check_result, collapse = "\n")),
    error = function(e) NULL
  )
  
  if (!is.null(check_json) && !is.null(check_json$FileStatus)) {
    file_size <- check_json$FileStatus$length
    cat("✓ JAR déjà présent sur HDFS\n")
    cat("  Taille:", round(file_size / 1024 / 1024, 2), "Mo\n\n")
    
    response <- readline("Le JAR existe déjà. Voulez-vous le remplacer? (o/N): ")
    if (tolower(response) != "o") {
      cat("\n✓ Utilisation du JAR existant\n")
      cat("\nAjoutez cette ligne dans knox_config.R si pas déjà fait:\n")
      cat("  SPARKLYR_JAR_PATH <- 'hdfs://", hdfs_jar_path, "'\n\n", sep = "")
      quit(save = "no")
    }
  }
}

cat("→ Le JAR n'existe pas encore ou sera remplacé\n\n")

# ============================================================================
# 4. RÉCUPÉRATION DU JAR EN LOCAL
# ============================================================================

cat("═══ 4. RÉCUPÉRATION DU JAR ═══\n\n")

local_jar_path <- tempfile(fileext = ".jar")

# Option 1 : Essayer de récupérer depuis l'installation de sparklyr
system_jar <- system.file(
  "java",
  jar_filename,
  package = "sparklyr"
)

if (file.exists(system_jar) && file.size(system_jar) > 0) {
  cat("✓ JAR trouvé dans l'installation sparklyr\n")
  cat("  Chemin:", system_jar, "\n")
  file.copy(system_jar, local_jar_path)
  cat("✓ Copie locale créée\n\n")
} else {
  # Option 2 : Télécharger depuis GitHub
  cat("→ JAR non trouvé localement, téléchargement depuis GitHub...\n")
  
  # Déterminer la bonne version
  github_version <- as.character(sparklyr_version)
  if (grepl("^1\\.8", github_version)) {
    github_tag <- "v1.8.5"
  } else if (grepl("^1\\.9", github_version)) {
    github_tag <- "v1.9.0"
  } else {
    github_tag <- paste0("v", github_version)
  }
  
  github_url <- sprintf(
    "https://github.com/sparklyr/sparklyr/releases/download/%s/%s",
    github_tag,
    jar_filename
  )
  
  cat("  URL:", github_url, "\n")
  
  download_cmd <- sprintf(
    "curl -L -o '%s' '%s'",
    local_jar_path,
    github_url
  )
  
  result <- system(download_cmd, ignore.stderr = FALSE)
  
  if (result != 0 || !file.exists(local_jar_path) || file.size(local_jar_path) == 0) {
    unlink(local_jar_path)
    stop(
      "Échec du téléchargement depuis GitHub.\n\n",
      "Solutions:\n",
      "1. Téléchargez manuellement le JAR depuis:\n",
      "   ", github_url, "\n",
      "2. Placez-le dans le répertoire courant\n",
      "3. Relancez ce script\n"
    )
  }
  
  cat("✓ Téléchargement réussi\n\n")
}

jar_size <- file.size(local_jar_path)
cat("Taille du JAR:", round(jar_size / 1024 / 1024, 2), "Mo\n\n")

# ============================================================================
# 5. CRÉATION DU RÉPERTOIRE HDFS
# ============================================================================

cat("═══ 5. CRÉATION DU RÉPERTOIRE HDFS ═══\n\n")

webhdfs_mkdir_url <- sprintf(
  "%s%s?op=MKDIRS&user.name=%s",
  KNOX_WEBHDFS_URL,
  hdfs_dir,
  KNOX_USERNAME
)

mkdir_cmd <- sprintf(
  "curl -s -k -u '%s' -X PUT '%s'",
  auth_escaped,
  webhdfs_mkdir_url
)

mkdir_result <- system(mkdir_cmd, intern = TRUE, ignore.stderr = TRUE)
cat("✓ Répertoire HDFS vérifié/créé:", hdfs_dir, "\n\n")

# ============================================================================
# 6. UPLOAD DU JAR VIA WEBHDFS
# ============================================================================

cat("═══ 6. UPLOAD DU JAR VIA WEBHDFS ═══\n\n")

cat("Cette opération peut prendre quelques minutes...\n")

# Étape 1 : Obtenir l'URL de redirection
webhdfs_create_url <- sprintf(
  "%s%s?op=CREATE&user.name=%s&overwrite=true",
  KNOX_WEBHDFS_URL,
  hdfs_jar_path,
  KNOX_USERNAME
)

redirect_cmd <- sprintf(
  "curl -s -k -i -u '%s' -X PUT '%s' 2>&1 | grep -i '^Location:' | cut -d' ' -f2 | tr -d '\\r'",
  auth_escaped,
  webhdfs_create_url
)

redirect_url <- system(redirect_cmd, intern = TRUE)

if (length(redirect_url) == 0 || redirect_url == "") {
  # Fallback : upload direct sans suivre la redirection
  cat("→ Upload direct (sans redirection)\n")
  
  upload_cmd <- sprintf(
    "curl -s -k -u '%s' -X PUT -T '%s' '%s'",
    auth_escaped,
    local_jar_path,
    webhdfs_create_url
  )
} else {
  cat("→ Upload vers:", redirect_url, "\n")
  
  upload_cmd <- sprintf(
    "curl -s -k -u '%s' -X PUT -T '%s' '%s'",
    auth_escaped,
    local_jar_path,
    redirect_url
  )
}

upload_result <- system(upload_cmd, intern = TRUE, ignore.stderr = TRUE)

cat("✓ Upload terminé\n\n")

# Nettoyage du fichier temporaire
unlink(local_jar_path)

# ============================================================================
# 7. VÉRIFICATION DE L'UPLOAD
# ============================================================================

cat("═══ 7. VÉRIFICATION DE L'UPLOAD ═══\n\n")

Sys.sleep(2)  # Attendre la propagation

verify_result <- system(check_cmd, intern = TRUE, ignore.stderr = TRUE)
verify_json <- tryCatch(
  fromJSON(paste(verify_result, collapse = "\n")),
  error = function(e) NULL
)

if (!is.null(verify_json) && !is.null(verify_json$FileStatus)) {
  uploaded_size <- verify_json$FileStatus$length
  cat("✓ JAR vérifié sur HDFS\n")
  cat("  Chemin:", hdfs_jar_path, "\n")
  cat("  Taille:", round(uploaded_size / 1024 / 1024, 2), "Mo\n\n")
  
  if (uploaded_size != jar_size) {
    warning("⚠ Différence de taille détectée (local vs HDFS)")
  }
} else {
  stop("⚠ Impossible de vérifier l'upload. Vérifiez manuellement avec WebHDFS.")
}

# ============================================================================
# 8. MISE À JOUR DE LA CONFIGURATION
# ============================================================================

cat("═══ 8. MISE À JOUR DE LA CONFIGURATION ═══\n\n")

hdfs_full_path <- sprintf("hdfs://%s", hdfs_jar_path)

cat("Ajoutez cette ligne dans knox_config.R:\n\n")
cat("  SPARKLYR_JAR_PATH <- '", hdfs_full_path, "'\n\n", sep = "")

# Vérifier si knox_config.R a déjà SPARKLYR_JAR_PATH
config_content <- readLines(config_file)
has_jar_path <- any(grepl("SPARKLYR_JAR_PATH", config_content))

if (!has_jar_path) {
  response <- readline("Voulez-vous que je l'ajoute automatiquement? (O/n): ")
  if (tolower(response) != "n") {
    cat(sprintf("\n# Chemin du JAR sparklyr sur HDFS\nSPARKLYR_JAR_PATH <- '%s'\n", hdfs_full_path),
        file = config_file, append = TRUE)
    cat("✓ Configuration mise à jour automatiquement\n\n")
  }
} else {
  cat("⚠ SPARKLYR_JAR_PATH existe déjà dans knox_config.R\n")
  cat("  Mettez-le à jour manuellement si nécessaire\n\n")
}

# ============================================================================
# 9. RÉSUMÉ ET PROCHAINES ÉTAPES
# ============================================================================

cat("╔═══════════════════════════════════════════════════════════════════╗\n")
cat("║                  INSTALLATION RÉUSSIE !                           ║\n")
cat("╚═══════════════════════════════════════════════════════════════════╝\n\n")

cat("Résumé:\n")
cat("  ✓ JAR téléchargé:", jar_filename, "\n")
cat("  ✓ Upload sur HDFS:", hdfs_jar_path, "\n")
cat("  ✓ Configuration:", config_file, "\n\n")

cat("Prochaines étapes:\n")
cat("  1. Vérifiez que SPARKLYR_JAR_PATH est dans knox_config.R\n")
cat("  2. Lancez la connexion Spark:\n")
cat("       source('knox_debug_full_en.R')\n")
cat("  3. Testez avec les exemples:\n")
cat("       source('exemples_sparklyr.R')\n\n")

cat("═══════════════════════════════════════════════════════════════════\n\n")
