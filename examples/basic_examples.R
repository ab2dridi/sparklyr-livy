# ============================================================================
# EXEMPLES D'UTILISATION DE SPARKLYR AVEC KNOX/LIVY
# ============================================================================
# Ce script contient des exemples pratiques d'utilisation de sparklyr
# Assurez-vous d'avoir d'abord exécuté knox_debug_full_en.R pour vous connecter

# Si pas encore connecté, décommentez la ligne suivante :
# source("knox_debug_full_en.R")

library(dplyr)
library(DBI)

cat("╔═══════════════════════════════════════════════════════════════════╗\n")
cat("║               EXEMPLES SPARKLYR - KNOX/LIVY                       ║\n")
cat("╚═══════════════════════════════════════════════════════════════════╝\n\n")

# ============================================================================
# 1. VÉRIFICATION DE LA CONNEXION
# ============================================================================

cat("═══ 1. VÉRIFICATION DE LA CONNEXION ═══\n\n")

if (!exists("sc") || !connection_is_open(sc)) {
  cat("⚠ Pas de connexion active. Exécutez d'abord :\n")
  cat("  source('knox_debug_full_en.R')\n\n")
  stop("Connexion requise")
}

cat("✓ Connexion active - Session ID:", sc$sessionId, "\n")
cat("✓ Version Spark:", spark_version(sc), "\n\n")

# ============================================================================
# 2. REQUÊTES SQL SIMPLES
# ============================================================================

cat("═══ 2. REQUÊTES SQL SIMPLES ═══\n\n")

# Liste des bases de données
cat("→ Bases de données disponibles :\n")
databases <- dbGetQuery(sc, "SHOW DATABASES")
print(head(databases, 10))
cat("\n")

# Liste des tables dans une base (remplacez 'default' par votre base)
cat("→ Tables dans la base 'default' :\n")
tables <- dbGetQuery(sc, "SHOW TABLES IN default")
print(head(tables, 10))
cat("\n")

# Exemple de requête SELECT simple
# REMPLACEZ 'ma_table' par une vraie table de votre environnement
cat("→ Exemple de requête SELECT :\n")
cat("# result <- dbGetQuery(sc, \"SELECT * FROM ma_base.ma_table LIMIT 10\")\n")
cat("# print(result)\n\n")

# ============================================================================
# 3. CRÉATION DE DATAFRAMES SPARK
# ============================================================================

cat("═══ 3. CRÉATION DE DATAFRAMES SPARK ═══\n\n")

# Créer une séquence de nombres
cat("→ Création d'une séquence de 1 à 100 :\n")
df_sequence <- sdf_len(sc, 100) %>%
  spark_dataframe()
cat("✓ DataFrame créé\n\n")

# Afficher les premières lignes
cat("→ Premières lignes :\n")
sdf_len(sc, 100) %>%
  head(5) %>%
  collect() %>%
  print()
cat("\n")

# ============================================================================
# 4. TRANSFORMATIONS DPLYR
# ============================================================================

cat("═══ 4. TRANSFORMATIONS DPLYR ═══\n\n")

cat("→ Exemple de transformations avec dplyr :\n")
result <- sdf_len(sc, 1000) %>%
  mutate(
    squared = id * id,
    cubed = id * id * id,
    is_even = (id %% 2) == 0
  ) %>%
  filter(id <= 20) %>%
  select(id, squared, cubed, is_even) %>%
  collect()

print(result)
cat("\n")

# ============================================================================
# 5. AGRÉGATIONS ET GROUPEMENTS
# ============================================================================

cat("═══ 5. AGRÉGATIONS ET GROUPEMENTS ═══\n\n")

cat("→ Statistiques par groupe :\n")
stats <- sdf_len(sc, 1000) %>%
  mutate(
    category = (id %% 5),
    value = id * 2
  ) %>%
  group_by(category) %>%
  summarise(
    count = n(),
    sum_value = sum(value, na.rm = TRUE),
    avg_value = mean(value, na.rm = TRUE),
    min_value = min(value, na.rm = TRUE),
    max_value = max(value, na.rm = TRUE)
  ) %>%
  arrange(category) %>%
  collect()

print(stats)
cat("\n")

# ============================================================================
# 6. LECTURE DE TABLES HIVE
# ============================================================================

cat("═══ 6. LECTURE DE TABLES HIVE ═══\n\n")

cat("→ Référencer une table Hive :\n")
cat("# ma_table <- tbl(sc, 'ma_base.ma_table')\n")
cat("# \n")
cat("# # Aperçu des données\n")
cat("# ma_table %>%\n")
cat("#   head(10) %>%\n")
cat("#   collect() %>%\n")
cat("#   print()\n")
cat("# \n")
cat("# # Analyse avec filtres\n")
cat("# resultat <- ma_table %>%\n")
cat("#   filter(date >= '2024-01-01') %>%\n")
cat("#   select(colonne1, colonne2, colonne3) %>%\n")
cat("#   group_by(colonne1) %>%\n")
cat("#   summarise(\n")
cat("#     total = n(),\n")
cat("#     moyenne = mean(colonne2, na.rm = TRUE)\n")
cat("#   ) %>%\n")
cat("#   arrange(desc(total)) %>%\n")
cat("#   collect()\n")
cat("# print(resultat)\n\n")

# ============================================================================
# 7. CRÉATION DE TABLES TEMPORAIRES
# ============================================================================

cat("═══ 7. CRÉATION DE TABLES TEMPORAIRES ═══\n\n")

cat("→ Créer une vue temporaire :\n")
# Créer un DataFrame et l'enregistrer comme vue temporaire
sdf_len(sc, 100) %>%
  mutate(
    value = id * 10,
    label = paste0("item_", id)
  ) %>%
  sdf_register("ma_vue_temp")

cat("✓ Vue temporaire 'ma_vue_temp' créée\n\n")

# Utiliser la vue avec SQL
cat("→ Requête SQL sur la vue temporaire :\n")
result_vue <- dbGetQuery(sc, "
  SELECT label, value 
  FROM ma_vue_temp 
  WHERE value > 500 
  LIMIT 10
")
print(result_vue)
cat("\n")

# ============================================================================
# 8. JOINTURES
# ============================================================================

cat("═══ 8. JOINTURES ═══\n\n")

cat("→ Exemple de jointure entre deux DataFrames :\n")

# Créer deux DataFrames
df1 <- sdf_len(sc, 10) %>%
  mutate(name = paste0("user_", id)) %>%
  select(id, name)

df2 <- sdf_len(sc, 15) %>%
  mutate(
    user_id = id,
    score = id * 10
  ) %>%
  select(user_id, score)

# Jointure
result_join <- df1 %>%
  left_join(df2, by = c("id" = "user_id")) %>%
  collect()

print(head(result_join, 10))
cat("\n")

# ============================================================================
# 9. FONCTIONS SPARK SQL
# ============================================================================

cat("═══ 9. FONCTIONS SPARK SQL ═══\n\n")

cat("→ Utilisation de fonctions SQL :\n")
result_sql <- sdf_len(sc, 100) %>%
  mutate(
    id_str = as.character(id),
    timestamp = current_timestamp(),
    random_val = rand(),
    abs_diff = abs(id - 50)
  ) %>%
  filter(id <= 10) %>%
  select(id, id_str, random_val, abs_diff) %>%
  collect()

print(result_sql)
cat("\n")

# ============================================================================
# 10. EXPORT DE RÉSULTATS
# ============================================================================

cat("═══ 10. EXPORT DE RÉSULTATS ═══\n\n")

cat("→ Sauvegarder des résultats :\n")
cat("# Option 1 : Écrire en Parquet sur HDFS\n")
cat("# ma_table %>%\n")
cat("#   spark_write_parquet('hdfs:///user/matricule/output/mon_resultat')\n")
cat("# \n")
cat("# Option 2 : Écrire en CSV\n")
cat("# ma_table %>%\n")
cat("#   spark_write_csv('hdfs:///user/matricule/output/mon_resultat.csv')\n")
cat("# \n")
cat("# Option 3 : Collecter en R et sauver localement\n")
cat("# resultat_local <- ma_table %>% collect()\n")
cat("# write.csv(resultat_local, 'mon_resultat.csv', row.names = FALSE)\n")
cat("# saveRDS(resultat_local, 'mon_resultat.rds')\n\n")

# ============================================================================
# 11. MONITORING ET DEBUG
# ============================================================================

cat("═══ 11. MONITORING ET DEBUG ═══\n\n")

cat("→ Informations de session :\n")
cat("  Session ID:", sc$sessionId, "\n")
cat("  Master URL:", sc$master, "\n")
cat("  Version Spark:", spark_version(sc), "\n\n")

cat("→ Pour voir les logs Spark détaillés :\n")
cat("# spark_log(sc, n = 50)  # Dernières 50 lignes de logs\n\n")

# ============================================================================
# 12. DÉCONNEXION
# ============================================================================

cat("═══ 12. DÉCONNEXION ═══\n\n")

cat("Pour vous déconnecter proprement :\n")
cat("# spark_disconnect(sc)\n\n")

# ============================================================================
# RÉSUMÉ DES COMMANDES UTILES
# ============================================================================

cat("╔═══════════════════════════════════════════════════════════════════╗\n")
cat("║                    RÉSUMÉ DES COMMANDES UTILES                    ║\n")
cat("╚═══════════════════════════════════════════════════════════════════╝\n\n")

cat("CONNEXION :\n")
cat("  source('knox_debug_full_en.R')\n\n")

cat("REQUÊTES SQL :\n")
cat("  dbGetQuery(sc, 'SELECT ...')\n")
cat("  dbExecute(sc, 'CREATE TABLE ...')\n\n")

cat("DATAFRAMES SPARK :\n")
cat("  tbl(sc, 'nom_table')           # Référencer une table\n")
cat("  sdf_len(sc, n)                 # Créer une séquence\n")
cat("  sdf_register(df, 'nom_vue')    # Créer une vue temporaire\n\n")

cat("OPÉRATIONS DPLYR :\n")
cat("  %>% filter(...)                # Filtrer\n")
cat("  %>% select(...)                # Sélectionner colonnes\n")
cat("  %>% mutate(...)                # Créer/modifier colonnes\n")
cat("  %>% group_by(...) %>% summarise(...) # Agréger\n")
cat("  %>% arrange(...)               # Trier\n")
cat("  %>% collect()                  # Ramener en R\n\n")

cat("LECTURE/ÉCRITURE :\n")
cat("  spark_read_parquet(sc, 'nom', 'chemin')\n")
cat("  spark_write_parquet(df, 'chemin')\n")
cat("  spark_read_csv(sc, 'nom', 'chemin')\n\n")

cat("DEBUG :\n")
cat("  spark_log(sc)                  # Voir les logs\n")
cat("  spark_connection_is_open(sc)  # Vérifier connexion\n\n")

cat("DÉCONNEXION :\n")
cat("  spark_disconnect(sc)\n\n")

cat("═══════════════════════════════════════════════════════════════════\n\n")
cat("✓ Exemples terminés avec succès !\n\n")
