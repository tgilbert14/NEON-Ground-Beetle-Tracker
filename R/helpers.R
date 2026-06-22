# ---------------------------------------------------------------------------
# helpers.R — the analytical engine for the NEON Ground Beetle Tracker
#
# Pure(ish) functions that turn a NEON ground-beetle (carabid) long table —
# one row per site / plot / bout / species with an individualCount and the
# trap-night effort — into the metrics that power the app: community
# composition, Hill-number diversity, individual-based rarefaction, species
# accumulation across bouts, and seasonal activity.
#
# Defensive throughout: NEON tables carry NAs, morphospecies, and uneven
# effort, so every function guards against empty / all-NA inputs and always
# normalises abundance to catch-per-trap-night where effort matters.
# ---------------------------------------------------------------------------

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

# ---------------------------------------------------------------------------
# QA/QC: is a scientificName resolved to SPECIES level?
#
# NEON beetle records are not all named to species: many are left at genus
# ("Bembidion sp."), family ("Carabidae"), or as ambiguous "A/B" calls. Counting
# each of those as if it were its own species inflates richness and diversity
# (a real foot-gun — the same mistake over-counted small-mammal taxa in an
# earlier app). So we flag species-level rows once, here, and let richness-type
# metrics use only those, while abundance keeps every beetle actually caught.
# A species-level name is a binomial: "Genus species" (epithet lowercase), and
# is not a "sp./spp./cf./aff." placeholder nor a family/subfamily/tribe name.
# Ref: NEON ground-beetle design, Hoekman et al. 2017, Ecosphere 8(4):e01744.
is_species_level <- function(name) {
  n <- trimws(as.character(name))
  n <- gsub("\\s*\\([^)]*\\)\\s*", " ", n)                  # drop subgenus "(Hypherpes)"
  n <- trimws(gsub("\\s+", " ", n))
  ok <- !is.na(n) & nzchar(n)
  binomial <- grepl("^[A-Z][a-z]+ [a-z][a-z]+", n)          # Genus species…
  placeholder <- grepl("\\b(sp|spp|cf|aff|nr|gen|indet)\\.?\\b", n, ignore.case = TRUE)
  higher <- grepl("(idae|inae|ini)$", n)                    # family/subfamily/tribe
  ambiguous <- grepl("/", n)                                # "Amara/Curtonotus" calls
  ok & binomial & !placeholder & !higher & !ambiguous
}

# Decide, per row, whether an ID is resolved to species. Prefer NEON's authoritative
# `taxonRank` (the robust discriminator the real bundle now carries from the expert
# table) and fall back to the scientific-name test when rank is missing (e.g. the
# demo CSV). Mirrors species_level_only() in the small-mammal app.
resolved_to_species <- function(rank, name) {
  name_ok <- is_species_level(name)
  if (is.null(rank)) return(name_ok)
  rank <- as.character(rank)
  known <- !is.na(rank) & nzchar(rank)
  ifelse(known, rank %in% c("species", "subspecies", "speciesGroup"), name_ok)
}

# Keep only species-level rows (for richness, diversity, ordination, indicators).
species_only <- function(d) {
  if (is.null(d) || !nrow(d)) return(d)
  flag <- if ("species_level" %in% names(d)) d$species_level
          else resolved_to_species(if ("taxonRank" %in% names(d)) d$taxonRank else NULL,
                                    d$scientificName)
  d[flag %in% TRUE, , drop = FALSE]
}

# Normalise a raw/bundled beetle table into the columns the app leans on.
clean_beetle <- function(d) {
  if (is.null(d) || nrow(d) == 0) return(NULL)
  d <- tibble::as_tibble(d)
  need <- c("siteID", "plotID", "collectDate", "taxonID", "scientificName",
            "taxonRank", "individualCount", "trapnights")
  for (col in need) if (!col %in% names(d)) d[[col]] <- NA
  d$individualCount <- suppressWarnings(as.numeric(d$individualCount))
  d$trapnights      <- suppressWarnings(as.numeric(d$trapnights))
  d$date <- as.Date(substr(as.character(d$collectDate), 1, 10))
  d$year <- as.integer(format(d$date, "%Y"))
  d$ym   <- substr(as.character(d$date), 1, 7)
  d$mon  <- as.integer(format(d$date, "%m"))
  # drop rows with no count or no name; keep genus/morphospecies for ABUNDANCE
  # but tag whether each is resolved to species so richness metrics can exclude
  # the higher-taxon rows (see is_species_level).
  d <- d[!is.na(d$individualCount) & d$individualCount > 0 &
         !is.na(d$scientificName) & d$scientificName != "", , drop = FALSE]
  d$species_level <- resolved_to_species(d$taxonRank, d$scientificName)
  d
}

# Per-species totals for the loaded site/window, most abundant first. `cpn` is
# catch per 100 trap-nights so sites/windows with different effort compare.
community_table <- function(d) {
  if (is.null(d) || nrow(d) == 0) return(NULL)
  tn <- effort_trapnights(d)
  out <- d %>%
    dplyr::group_by(.data$scientificName) %>%
    dplyr::summarise(individuals = sum(.data$individualCount, na.rm = TRUE),
                     bouts = dplyr::n_distinct(.data$collectDate),
                     .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(.data$individuals))
  out$cpn <- if (tn > 0) round(100 * out$individuals / tn, 2) else NA_real_
  # species-level flag must match the rest of the app (rank-aware): prefer the
  # per-row flag clean_beetle() set from NEON's authoritative taxonRank, and fall
  # back to the name heuristic only when rank is absent (e.g. the demo CSV).
  # Using is_species_level(name) here alone made the Overview/Diversity species
  # set disagree with the QA note, ordination and indicators once a real bundle
  # (which carries taxonRank) is loaded.
  out$species_level <- if ("species_level" %in% names(d)) {
    unname(tapply(d$species_level %in% TRUE, d$scientificName, any)[out$scientificName])
  } else is_species_level(out$scientificName)
  attr(out, "qa") <- taxon_qa(d)
  out
}

# QA/QC summary for the data-quality note: how much of the catch is resolved to
# species vs. left at genus/family. Richness uses species-level only; abundance
# (total individuals) keeps everything actually trapped.
taxon_qa <- function(d) {
  if (is.null(d) || !nrow(d)) return(NULL)
  sl <- if ("species_level" %in% names(d)) d$species_level
        else resolved_to_species(if ("taxonRank" %in% names(d)) d$taxonRank else NULL, d$scientificName)
  ind <- d$individualCount
  list(
    species          = length(unique(d$scientificName[sl %in% TRUE])),
    higher_taxa      = length(unique(d$scientificName[!(sl %in% TRUE)])),
    ind_total        = sum(ind, na.rm = TRUE),
    ind_higher       = sum(ind[!(sl %in% TRUE)], na.rm = TRUE),
    pct_ind_higher   = {
      tot <- sum(ind, na.rm = TRUE)
      if (tot > 0) round(100 * sum(ind[!(sl %in% TRUE)], na.rm = TRUE) / tot, 1) else 0
    })
}

# Total trap-night effort = sum of unique (plot, bout) trap-night values, so a
# species count isn't multiplied by however many species shared that sample.
effort_trapnights <- function(d) {
  if (is.null(d) || !"trapnights" %in% names(d)) return(NA_real_)
  u <- unique(d[, c("plotID", "collectDate", "trapnights"), drop = FALSE])
  sum(u$trapnights, na.rm = TRUE)
}

# ---- diversity: Hill numbers ----------------------------------------------
# Three views of diversity in one unit — an EFFECTIVE number of species —
# indexed by q (how much rare species count): q0 = richness, q1 = exp(Shannon)
# (common species), q2 = inverse Simpson (dominant species). Hill 1973; Jost 2006.
hill_numbers <- function(counts) {
  n <- counts[!is.na(counts) & counts > 0]
  if (length(n) == 0) return(list(q0 = NA, q1 = NA, q2 = NA, even = NA))
  p <- n / sum(n)
  q0 <- length(n)
  shannon <- -sum(p * log(p))
  q1 <- exp(shannon)
  q2 <- 1 / sum(p^2)
  list(q0 = q0, q1 = round(q1, 2), q2 = round(q2, 2),
       even = if (q0 > 1) round(q1 / q0, 2) else NA)  # Pielou-style evenness
}

# ---- individual-based rarefaction (Hurlbert 1971) -------------------------
# Expected species E[S_n] in a random subsample of n individuals, with an
# analytic SD (Heck et al. 1975). Lets you compare richness at equal sample
# size instead of being fooled by who simply caught more beetles.
rarefaction_curve <- function(counts, step = NULL) {
  Ni <- counts[!is.na(counts) & counts > 0]
  N  <- sum(Ni)
  if (N < 2 || length(Ni) < 1) return(NULL)
  if (is.null(step)) step <- max(1L, floor(N / 40))
  ns <- unique(c(seq(1, N, by = step), N))
  es <- sd <- numeric(length(ns))
  lcN <- lchoose(N, ns)
  for (j in seq_along(ns)) {
    n <- ns[j]
    # P(species i absent from subsample) = C(N-Ni, n)/C(N, n)
    pa <- exp(lchoose(N - Ni, n) - lcN[j])
    pa[!is.finite(pa)] <- 0
    es[j] <- sum(1 - pa)
    # variance per Heck/Smith-Grassle approximation
    term <- pa * (1 - pa)
    sd[j] <- sqrt(max(0, sum(term)))
  }
  tibble::tibble(n = ns, richness = es, lo = pmax(0, es - sd), hi = es + sd)
}

# ---- species accumulation across bouts (sample-based) ---------------------
# As trapping bouts accumulate, how many species have been seen? A flattening
# curve means the site's beetle fauna is well sampled. Averaged over random
# bout orderings (Gotelli & Colwell 2001) for a smooth, order-free curve.
accumulation_by_bout <- function(d, perms = 50) {
  if (is.null(d) || nrow(d) == 0) return(NULL)
  d <- species_only(d)              # richness curve = species-level only
  if (is.null(d) || nrow(d) == 0) return(NULL)
  d$boutid <- paste(d$plotID, d$collectDate)
  bouts <- unique(d$boutid)
  K <- length(bouts)
  if (K < 2) return(NULL)
  by_b <- split(d$scientificName, d$boutid)
  set.seed(1)
  acc <- matrix(NA_real_, nrow = perms, ncol = K)
  for (p in seq_len(perms)) {
    ord <- sample(bouts)
    seen <- character(0)
    for (k in seq_len(K)) {
      seen <- union(seen, by_b[[ord[k]]])
      acc[p, k] <- length(seen)
    }
  }
  tibble::tibble(bouts = seq_len(K),
                 richness = colMeans(acc),
                 sd = apply(acc, 2, stats::sd))
}

# ---- seasonality ----------------------------------------------------------
# Mean catch-per-100-trap-night by calendar month — the activity-density
# curve. Optionally per species (top `top_n` by total abundance).
seasonality <- function(d, by_species = FALSE, top_n = 6) {
  if (is.null(d) || nrow(d) == 0) return(NULL)
  eff <- unique(d[, c("plotID", "collectDate", "trapnights")])
  eff$mon <- as.integer(format(as.Date(eff$collectDate), "%m"))
  mon_eff <- stats::aggregate(trapnights ~ mon, eff, sum)
  if (!by_species) {
    cap <- stats::aggregate(individualCount ~ mon, d, sum)
    m <- merge(cap, mon_eff, by = "mon")
    m$cpn <- 100 * m$individualCount / m$trapnights
    return(tibble::as_tibble(m[order(m$mon), c("mon", "cpn")]))
  }
  ds <- species_only(d)             # name real species in the per-species split
  if (is.null(ds) || !nrow(ds)) ds <- d
  keep <- names(sort(tapply(ds$individualCount, ds$scientificName, sum),
                     decreasing = TRUE))[seq_len(min(top_n, length(unique(ds$scientificName))))]
  sub <- ds[ds$scientificName %in% keep, ]
  cap <- stats::aggregate(individualCount ~ mon + scientificName, sub, sum)
  m <- merge(cap, mon_eff, by = "mon")
  m$cpn <- 100 * m$individualCount / m$trapnights
  tibble::as_tibble(m[order(m$scientificName, m$mon), c("mon", "scientificName", "cpn")])
}

# ---- phenology heatmap (species x month) ----------------------------------
# Top species by abundance, each row a species, each column a calendar month,
# the cell = that month's catch per 100 trap-nights (so a heavily-sampled month
# doesn't just look busier). A month with effort but no catch of the species is
# a real 0; a month never sampled is NA (a gap, not a zero). Reveals that each
# species has its OWN activity window, which a pooled curve hides.
phenology_matrix <- function(d, top = 10) {
  if (is.null(d) || !nrow(d)) return(NULL)
  sp_d <- species_only(d); if (!nrow(sp_d)) return(NULL)
  eff <- unique(d[, c("plotID", "collectDate", "trapnights")])
  eff$mon <- as.integer(format(as.Date(eff$collectDate), "%m"))
  mon_tn <- tapply(eff$trapnights, eff$mon, sum, na.rm = TRUE)   # named vector, month -> trap-nights
  tops <- names(sort(tapply(sp_d$individualCount, sp_d$scientificName, sum),
                     decreasing = TRUE))[seq_len(min(top, length(unique(sp_d$scientificName))))]
  if (!length(tops)) return(NULL)
  z <- matrix(NA_real_, nrow = length(tops), ncol = 12, dimnames = list(tops, month.abb))
  sampled <- suppressWarnings(as.integer(names(mon_tn))[mon_tn > 0])
  sampled <- sampled[!is.na(sampled)]
  if (length(sampled)) z[, sampled] <- 0                        # sampled-but-absent = real 0
  sub <- sp_d[sp_d$scientificName %in% tops, ]
  cap <- stats::aggregate(individualCount ~ scientificName + mon, sub, sum)
  for (i in seq_len(nrow(cap))) {
    tn <- mon_tn[as.character(cap$mon[i])]
    if (length(tn) && !is.na(tn) && tn > 0)
      z[cap$scientificName[i], cap$mon[i]] <- round(100 * cap$individualCount[i] / tn, 2)
  }
  list(z = z, species = tops, months = month.abb)
}

# ---- frequency of occurrence (naive occupancy) ----------------------------
# The share of CARABID-POSITIVE plot x bout samples in which each species was
# caught at least once. The count-data analogue of "how widespread": a beetle can
# be abundant but patchy, or sparse but everywhere. Two honest caveats baked into
# the UI copy: (1) NAIVE — not detection-corrected; (2) the denominator is bouts
# that caught >=1 ground beetle, because the bundle drops zero-catch bouts at
# clean_beetle() (so a true deployment denominator isn't reconstructable here);
# zero-carabid bouts are rare in the active season, so the bias is small but real.
occupancy_table <- function(d, min_samples = 6) {
  if (is.null(d) || !nrow(d)) return(NULL)
  sp_d <- species_only(d); if (!nrow(sp_d)) return(NULL)
  n_samp <- nrow(unique(d[, c("plotID", "collectDate"), drop = FALSE]))
  if (n_samp < min_samples) return(NULL)
  occ <- sp_d %>%
    dplyr::distinct(.data$scientificName, .data$plotID, .data$collectDate) %>%
    dplyr::group_by(.data$scientificName) %>%
    dplyr::summarise(present = dplyr::n(), .groups = "drop") %>%
    dplyr::mutate(occ = round(100 * .data$present / n_samp, 1)) %>%
    dplyr::arrange(dplyr::desc(.data$occ))
  attr(occ, "n_samp") <- n_samp
  occ
}

# ---- rank-abundance (Whittaker) -------------------------------------------
# Species ranked by relative abundance — the curve's SHAPE is the evenness
# story the Hill numbers summarise: a steep drop = a few dominants, a shallow
# line = an even community. Species-level only.
rank_abundance <- function(d) {
  ct <- community_table(d); if (is.null(ct)) return(NULL)
  sp <- ct[ct$species_level %in% TRUE, , drop = FALSE]
  if (!nrow(sp)) return(NULL)
  tot <- sum(sp$individuals)
  data.frame(rank = seq_len(nrow(sp)), scientificName = sp$scientificName,
             individuals = sp$individuals,
             rel = if (tot > 0) round(100 * sp$individuals / tot, 3) else NA_real_,
             stringsAsFactors = FALSE)
}

# ---- inter-annual trend ---------------------------------------------------
# Catch-per-100-trap-nights by year, with a fitted linear trend. This is the
# "are the beetles disappearing?" view — NEON's standardized long records are
# exactly the kind of series the global insect-decline literature is built on.
# Falls back to raw counts when a bundle carries no effort data.
annual_trend <- function(d) {
  if (is.null(d) || nrow(d) == 0) return(NULL)
  yr <- if ("year" %in% names(d)) d$year else as.integer(format(as.Date(d$collectDate), "%Y"))
  cap <- stats::aggregate(list(individuals = d$individualCount), list(year = yr), sum, na.rm = TRUE)
  eff <- unique(d[, c("plotID", "collectDate", "trapnights"), drop = FALSE])
  eff$year <- as.integer(format(as.Date(eff$collectDate), "%Y"))
  te <- stats::aggregate(list(trapnights = eff$trapnights), list(year = eff$year),
                         function(x) sum(x, na.rm = TRUE))
  m <- merge(cap, te, by = "year", all.x = TRUE)
  m <- m[order(m$year), , drop = FALSE]
  has_eff <- sum(m$trapnights, na.rm = TRUE) > 0
  m$cpn <- if (has_eff) ifelse(m$trapnights > 0, 100 * m$individuals / m$trapnights, NA_real_) else NA_real_
  m$metric <- if (has_eff) m$cpn else as.numeric(m$individuals)
  m <- m[is.finite(m$metric), , drop = FALSE]
  if (nrow(m) < 2) return(NULL)
  out <- tibble::as_tibble(m[, c("year", "individuals", "trapnights", "cpn", "metric")])
  attr(out, "metric_kind") <- if (has_eff) "cpn" else "count"
  fit <- tryCatch(stats::lm(metric ~ year, data = m), error = function(e) NULL)
  if (!is.null(fit) && nrow(m) >= 3) {
    co <- summary(fit)$coefficients
    if ("year" %in% rownames(co)) {
      mu <- mean(m$metric, na.rm = TRUE)
      attr(out, "slope") <- co["year", "Estimate"]
      attr(out, "p") <- co["year", "Pr(>|t|)"]
      attr(out, "pct_per_yr") <- if (is.finite(mu) && mu > 0) 100 * co["year", "Estimate"] / mu else NA_real_
      attr(out, "pred") <- stats::predict(fit)
    }
  }
  out
}

# Stable species -> color map so a species is the same color everywhere.
# Colour-blind-safe base (Okabe & Ito 2008, minus the black/yellow that read
# poorly over the forest theme and in dark mode) used directly for the usual
# handful of species; only ramped when a site has more species than the base.
make_species_pal <- function(d) {
  sp <- sort(unique(d$scientificName[!is.na(d$scientificName)]))
  if (length(sp) == 0) return(character(0))
  base <- c("#0072B2", "#E69F00", "#009E73", "#CC79A7", "#56B4E9", "#D55E00", "#7E5CC9", "#1a7f37")
  cols <- if (length(sp) <= length(base)) base[seq_along(sp)]
          else grDevices::colorRampPalette(base)(length(sp))
  stats::setNames(cols, sp)
}

# Genus -> a one-line natural-history blurb for the "meet the beetles" cards.
beetle_blurb <- function(scientificName) {
  g <- sub(" .*$", "", scientificName %||% "")
  lut <- c(
    Pterostichus = "Glossy black woodland predators, fast night hunters of soft-bodied prey and a classic forest-floor carabid.",
    Carabus      = "Big, sculptured 'caterpillar hunters' that can't fly; flagship beetles of healthy forest soils.",
    Calosoma     = "Iridescent 'searchers' that climb plants to hunt caterpillars, voracious agricultural allies.",
    Harpalus     = "Stout seed-eating ground beetles (granivores) common in open prairies and fields.",
    Poecilus     = "Metallic-green active hunters of grasslands, abundant through the warm season.",
    Pasimachus   = "Large flightless predators with massive jaws that patrol bare desert and prairie soil at night.",
    Scarites     = "Pincer-jawed burrowers that ambush prey from tunnels in loose soil.",
    Cyclotrachelus = "Robust late-season woodland and prairie predators active into autumn.",
    Cicindela    = "Tiger beetles: dazzling, fast-running visual hunters of sunbaked open ground.",
    Synuchus     = "Small forest carabids that forage in leaf litter and shelter under bark.",
    Amara        = "Sun-loving seed and plant feeders of open, dry habitats.",
    Notiobia     = "Warm-climate seed-eating beetles of sandy southern soils.",
    Cratacanthus = "Small granivorous ground beetles of arid grassland and desert.",
    Sphaeroderus = "Snail-hunting woodland beetles with narrow heads built to reach into shells.",
    Agonum       = "Slender, often metallic beetles of damp ground and wetland margins.",
    Cychrus      = "Snail-specialist forest beetles with elongate snouts."
  )
  unname(lut[g]) %||% "A NEON-sampled ground beetle (Carabidae), a sensitive bioindicator of habitat and climate."
}

# Introduced (non-native, established European) carabids -----------------------
# Several NEON sites are numerically DOMINATED by an introduced European species
# (Pterostichus melanarius #1 at STEI/UNDE/WOOD; Carabus nemoralis at TREE), so a
# "most abundant / dominant" verdict reads backwards — a dominant European beetle
# is the opposite of intact native fauna. Keyed on the exact binomial (not genus:
# most Pterostichus/Carabus are native) so only the established invaders flag.
# Refs: Bousquet 2012 (Carabidae of America N of Mexico); Lindroth 1961-69.
INTRODUCED_CARABIDS <- c(
  "Pterostichus melanarius",   # common black ground beetle — widespread European invader
  "Carabus nemoralis",         # European bronze carabid, established across the N US
  "Carabus granulatus",
  "Carabus auratus",
  "Nebria brevicollis",
  "Clivina fossor",
  "Calathus fuscipes",
  "Harpalus affinis",
  "Harpalus rufipes",          # = Pseudoophonus rufipes, the strawberry seed beetle
  "Pseudoophonus rufipes",
  "Amara aenea",
  "Trechus quadristriatus",
  "Anisodactylus binotatus"
)
# TRUE for an introduced/non-native European carabid (exact-binomial match, so a
# subgenus tag or trailing author string is tolerated; vectorised).
is_introduced <- function(scientificName) {
  nm <- trimws(as.character(scientificName %||% ""))
  nm <- gsub("\\s*\\([^)]*\\)\\s*", " ", nm)               # drop subgenus "(Hypherpes)"
  nm <- trimws(gsub("\\s+", " ", nm))
  binom <- sub("^([A-Z][a-z]+ [a-z][a-z-]+).*$", "\\1", nm)  # first two words = Genus species
  binom %in% INTRODUCED_CARABIDS
}

# Number formatting used across cards/tables.
fmt_int <- function(x) formatC(x, format = "d", big.mark = ",")

# ---------------------------------------------------------------------------
# Codebook (data dictionary) for the CSV export — one row per exported column.
# Single source of truth so the shipped codebook can never drift from the data;
# the download handler asserts these `column` names match the frame it writes.
# Keep the rows in the SAME order the export writes its columns.
# ---------------------------------------------------------------------------
beetle_export_codebook <- function() {
  tibble::tribble(
    ~column,                  ~type,      ~units,                          ~definition,
    "siteID",                 "string",   "",                              "NEON four-letter site code (e.g. SRER, HARV).",
    "plotID",                 "string",   "",                              "NEON plot identifier within the site (e.g. HARV_001).",
    "collectDate",            "date",     "ISO 8601 (YYYY-MM-DD)",         "Date the pitfall bout was collected.",
    "year",                   "integer",  "",                              "Calendar year of collectDate.",
    "month",                  "integer",  "1-12",                          "Calendar month of collectDate.",
    "taxonID",                "string",   "",                              "NEON taxon code for the identification.",
    "scientificName",         "string",   "",                              "Scientific name - expert-taxonomist call where available, otherwise parataxonomist; may be a genus or family for unresolved IDs.",
    "taxonRank",              "string",   "",                              "Taxonomic rank of scientificName (species, genus, family, ...), from NEON's expert table where available.",
    "species_level",          "boolean",  "TRUE/FALSE",                    "TRUE when resolved to species/subspecies. Richness, diversity, ordination and indicator metrics use TRUE rows only; total abundance uses all rows.",
    "individualCount",        "integer",  "individuals",                   "Number of individuals of this taxon in this plot x bout sample.",
    "trapnights",             "numeric",  "trap-nights",                   "Trap-night effort for this plot x bout (sum of daysOfTrapping over traps set). Empty when NEON effort data is absent.",
    "cpn_per_100_trapnights", "numeric",  "individuals / 100 trap-nights", "Effort-normalised catch = 100 x individualCount / trapnights. Empty when trapnights is missing or zero.",
    "source",                 "string",   "",                              "'neon' = real NEON records; 'demo' = illustrative sample data."
  )
}

# ---------------------------------------------------------------------------
# Co-located monthly environmental series, materialised for the data export.
# Builds the date + the driver columns the app overlays (precip / temp / green-up
# etc.) plus a per-driver _n month-count from a site's env bundle (load_site_env).
# Returns NULL when no env bundle exists for the site. Columns are emitted in a
# stable order so the env codebook can iterate the SAME keep-vector (no drift).
# ---------------------------------------------------------------------------
beetle_env_export <- function(env) {
  if (is.null(env) || !nrow(env)) return(NULL)
  e <- env; e$date <- as.Date(e$date)
  cols <- c("precip_mm", "temp_c", "greenup_pct", "flowering_pct", "fruiting_pct")
  have <- intersect(cols, names(e))
  if (!length(have)) return(NULL)
  out <- data.frame(date = e$date, stringsAsFactors = FALSE)
  for (cc in have) out[[cc]] <- suppressWarnings(as.numeric(e[[cc]]))
  out <- out[order(out$date), , drop = FALSE]
  # one _n column per driver = how many non-NA months back that driver (honest
  # coverage, mirrors ENV_MIN_MONTHS gating).
  for (cc in have) out[[paste0(cc, "_n")]] <- sum(!is.na(out[[cc]]))
  attr(out, "drivers") <- have
  tibble::as_tibble(out)
}

# Codebook for the env export — built by iterating the ACTUAL emitted columns so
# it can never drift from beetle_env_export()'s output.
beetle_env_codebook <- function(env_df) {
  if (is.null(env_df)) return(NULL)
  unit_lut <- c(precip_mm = "mm/month (sum)", temp_c = "deg C (monthly mean)",
                greenup_pct = "% of plants leafing out", flowering_pct = "% of plants in flower",
                fruiting_pct = "% of plants in fruit")
  def_lut <- c(
    date          = "First day of the calendar month the value summarises.",
    precip_mm     = "Total monthly precipitation at the site (NEON DP1.00044.001).",
    temp_c        = "Mean monthly air temperature at the site (NEON DP1.00002.001).",
    greenup_pct   = "Share of monitored plants leafing out that month (NEON DP1.10055.001).",
    flowering_pct = "Share of monitored plants in flower that month (NEON DP1.10055.001).",
    fruiting_pct  = "Share of monitored plants in fruit that month (NEON DP1.10055.001).")
  rows <- lapply(names(env_df), function(cc) {
    base <- sub("_n$", "", cc); is_n <- grepl("_n$", cc)
    data.frame(
      column     = cc,
      type       = if (cc == "date") "date" else "numeric",
      units      = if (is_n) "# months" else unname(unit_lut[base] %||% ""),
      definition = if (is_n) sprintf("Number of non-NA monthly values of %s for this site (coverage).", base)
                   else unname(def_lut[cc] %||% ""),
      stringsAsFactors = FALSE)
  })
  tibble::as_tibble(do.call(rbind, rows))
}

# ---------------------------------------------------------------------------
# beetle_qc(): site-level data-quality review flags for the loaded bundle.
# Returns ranked "verify, not wrong" flags PLUS the exact offending rows behind
# each, so the UI lists them (clickable) and the user can download a per-flag CSV
# and a full QC report. Ported from the suite's bird_qc()/mos_qc() contract:
#   out <- list(flags = <ranked list of {level,title,key,n,detail}>,
#               sets  = <named list: key -> data.frame of the flagged rows>)
# Flagged rows are RETAINED, never deleted. Thresholds are data-derived and
# domain-grounded so the system stays near-zero "high" on clean NEON data.
#   high = a result that reads BACKWARDS unless you know the caveat
#          (an introduced European carabid is the dominant "signature" species)
#   warn = worth a look (a high coarse-ID share; one species swamps the catch)
#   info = a transparency note (genus/family-only rows; singleton-heavy tail)
# `d` is the cleaned long table (clean_beetle output) for ONE site.
# ---------------------------------------------------------------------------
beetle_qc <- function(d) {
  out <- list(flags = list(), sets = list())
  if (is.null(d) || !nrow(d)) return(out)
  cols <- intersect(c("siteID", "plotID", "collectDate", "year", "taxonID",
                      "scientificName", "taxonRank", "species_level",
                      "individualCount", "trapnights"), names(d))
  tidy <- function(rows, label) {
    rows <- rows[!is.na(rows)]; if (!length(rows)) return(NULL)
    x <- d[rows, cols, drop = FALSE]; if (!nrow(x)) return(NULL); x$flag <- label; x
  }
  add <- function(level, title, key, rows, detail) {
    rows <- unique(rows[!is.na(rows)]); n <- length(rows); if (!n) return(invisible())
    out$flags[[length(out$flags) + 1L]] <<- list(level = level, title = title,
      key = key, n = n, detail = detail)
    out$sets[[key]] <<- tidy(rows, title)
  }

  sl  <- d$species_level %in% TRUE
  ind <- suppressWarnings(as.numeric(d$individualCount))
  tot_ind <- sum(ind, na.rm = TRUE)

  # 1 (HIGH) — the most-abundant SPECIES is an introduced European carabid.
  # A "dominant" or "#1" label then reads backwards: a numerically dominant
  # non-native is the opposite of intact native fauna (see is_introduced).
  sp_ind <- tapply(ind[sl], d$scientificName[sl], sum, na.rm = TRUE)
  if (length(sp_ind)) {
    dom <- names(sp_ind)[which.max(sp_ind)]
    if (length(dom) && is_introduced(dom))
      add("high", sprintf("Dominant species is introduced (%s)", dom), "introduced",
          which(sl & is_introduced(d$scientificName)),
          sprintf("%s, the most abundant named beetle here, is an introduced European carabid, not native. A 'dominant/top species' verdict reads backwards: a numerically dominant non-native usually marks a disturbed or human-modified site, not a rich native fauna. The rows behind this flag are every catch of an introduced species at this site.", dom))
  }

  # 2 (WARN) — high coarse-ID share. When a large share of INDIVIDUALS is left at
  # genus/family (not resolved to species), richness/diversity (species-level only)
  # rest on a thin slice of the catch. Threshold is the suite default 25% of
  # individuals unresolved; the flagged rows are the unresolved catch itself.
  pct_higher <- if (tot_ind > 0) 100 * sum(ind[!sl], na.rm = TRUE) / tot_ind else 0
  if (pct_higher >= 25)
    add("warn", sprintf("Coarse IDs: %.0f%% of the catch isn't named to species", pct_higher),
        "coarse",
        which(!sl),
        sprintf("%.0f%% of the individuals here stop at genus or family (for example 'Bembidion sp.' or 'Carabidae'). Those are kept in total abundance but excluded from richness, diversity, the ordination and indicators, so the diversity story rests on the named slice. Worth knowing how much of the community is unresolved.", pct_higher))

  # 3 (WARN) — one species swamps the catch. When a single species is >=60% of all
  # named individuals, the community is very uneven; verify it isn't a sampling or
  # ID artifact (e.g. a pitfall over-catching one fast surface hunter).
  if (length(sp_ind)) {
    top_sp <- names(sp_ind)[which.max(sp_ind)]
    top_sh <- if (sum(sp_ind) > 0) 100 * max(sp_ind) / sum(sp_ind) else 0
    if (top_sh >= 60)
      add("warn", sprintf("One species is %.0f%% of the named catch (%s)", top_sh, top_sp),
          "dominance",
          which(sl & d$scientificName == top_sp),
          sprintf("%s alone is %.0f%% of every named beetle caught here. Pitfall catch tracks activity x density, so a fast, large, surface-active hunter can swamp the trap without being that much more abundant. Read the diversity numbers with that in mind; the rows are every catch of this species.", top_sp, top_sh))
  }

  # 4 (WARN) — bouts missing trap-night effort. A plot x bout with catch but no
  # trapnights can't be effort-normalised, so it's dropped from the per-trap-night
  # denominator (counts still appear in totals). Flag the affected rows.
  tn <- suppressWarnings(as.numeric(d$trapnights))
  no_eff <- which((is.na(tn) | tn <= 0) & is.finite(ind) & ind > 0)
  if (length(no_eff))
    add("warn", "Catch with no trap-night effort", "noeffort", no_eff,
        "These records have beetles counted but no usable trap-night effort, so they can't be turned into a catch-per-100-trap-nights rate and drop out of the effort-normalised metrics (they still count toward raw totals). A trapping record with no recorded effort is unusable for fair site comparison.")

  # 5 (INFO) — genus/family-only identifications (transparency list). Distinct from
  # the WARN threshold: this always lists the unresolved rows so they're inspectable
  # even when the coarse share is modest.
  add("info", "Genus / family-only identifications", "higher",
      which(!sl),
      "Rows left at genus or family rather than a species. They are kept in total abundance and listed here for transparency, but excluded from every richness-type metric (richness, Hill numbers, rarefaction, accumulation, ordination, indicators), so counting them as species can't inflate diversity.")

  # 6 (INFO) — singleton-heavy tail. Many species seen as a single individual is a
  # normal hallmark of under-sampling, not an error; it means richness is a minimum
  # and the accumulation curve hasn't flattened. Flag the singleton species' rows.
  if (length(sp_ind)) {
    singles <- names(sp_ind)[sp_ind == 1]
    if (length(singles) >= 5)
      add("info", sprintf("%d species seen just once (singletons)", length(singles)),
          "singletons",
          which(sl & d$scientificName %in% singles),
          sprintf("%d of the named species were each caught as a single individual. A long singleton tail is the normal fingerprint of an under-sampled community: richness here is a minimum, and more trapping would likely turn up more species. It is not a data error, just a note on how to read the richness number.", length(singles)))
  }

  # rank the flags high -> warn -> info for display
  if (length(out$flags)) {
    ord <- order(match(vapply(out$flags, function(f) f$level, ""), c("high", "warn", "info")))
    out$flags <- out$flags[ord]
  }
  out
}

# Full QC report: every flagged row across all flags, bound into one frame.
beetle_qc_report <- function(d) {
  q <- beetle_qc(d); if (!length(q$sets)) return(NULL)
  do.call(rbind, c(q$sets, list(make.row.names = FALSE)))
}

# ---------------------------------------------------------------------------
# assemble_beetles() — turn a neonUtilities loadByProduct() result for
# DP1.10022.001 into the app's tidy long schema:
#   siteID, plotID, collectDate, taxonID, scientificName, taxonRank,
#   individualCount, trapnights
#
# Steps (the canonical EFI/neonDivData recipe, kept pragmatic for a scaffold):
#  1. carabid counts from bet_sorting (sampleType == "carabid")
#  2. reconcile taxonomy: override the parataxonomist call with the authoritative
#     EXPERT call where one exists for that taxonID
#  3. effort: trap-nights per plot × bout from bet_fielddata$daysOfTrapping,
#     summed over the traps actually set — this absorbs the 2018 trap-count and
#     2023 plot-count protocol changes, so abundance stays per-trap-night.
#
# Defensive about column names (NEON renames tables occasionally); a maintainer
# should confirm names once with names(loadByProduct(...)). Used by both the
# live-fetch path (global.R) and the bundle builder (scripts/refresh_data.R).
# ---------------------------------------------------------------------------
assemble_beetles <- function(raw) {
  if (is.null(raw) || is.null(raw$bet_sorting)) stop("no bet_sorting table in result")
  srt <- tibble::as_tibble(raw$bet_sorting)
  if ("sampleType" %in% names(srt))
    srt <- srt[!is.na(srt$sampleType) & srt$sampleType == "carabid", , drop = FALSE]
  if (!nrow(srt)) return(NULL)
  for (col in c("individualCount", "taxonID", "scientificName", "taxonRank",
                "plotID", "collectDate", "siteID"))
    if (!col %in% names(srt)) srt[[col]] <- NA
  srt$individualCount <- suppressWarnings(as.numeric(srt$individualCount))

  # 2) expert-ID override (authoritative). Build a taxonID -> expert name/rank
  #    lookup; the expert's taxonRank is what lets richness exclude genus/family
  #    records cleanly (see is_species_level / species_only).
  exp <- raw$bet_expertTaxonomistIDProcessed
  if (!is.null(exp) && nrow(exp)) {
    exp <- tibble::as_tibble(exp)
    if (!"taxonRank" %in% names(exp)) exp$taxonRank <- NA
    if (all(c("taxonID", "scientificName") %in% names(exp))) {
      lut <- unique(exp[!is.na(exp$taxonID) & !is.na(exp$scientificName),
                        c("taxonID", "scientificName", "taxonRank")])
      lut <- lut[!duplicated(lut$taxonID), , drop = FALSE]
      hit <- match(srt$taxonID, lut$taxonID)
      srt$scientificName <- ifelse(is.na(hit), srt$scientificName, lut$scientificName[hit])
      srt$taxonRank      <- ifelse(is.na(hit), srt$taxonRank,      lut$taxonRank[hit])
    }
  }

  counts <- srt %>%
    dplyr::filter(!is.na(.data$individualCount), .data$individualCount > 0,
                  !is.na(.data$scientificName)) %>%
    dplyr::group_by(.data$siteID, .data$plotID, .data$collectDate,
                    .data$taxonID, .data$scientificName, .data$taxonRank) %>%
    dplyr::summarise(individualCount = sum(.data$individualCount), .groups = "drop")

  # 3) trap-night effort per plot × bout from field data
  fd <- raw$bet_fielddata
  eff <- NULL
  if (!is.null(fd) && nrow(fd)) {
    fd <- tibble::as_tibble(fd)
    dcol <- intersect(c("daysOfTrapping", "trappingDays"), names(fd))
    if (length(dcol) && all(c("plotID", "collectDate") %in% names(fd))) {
      fd$.days <- suppressWarnings(as.numeric(fd[[dcol[1]]]))
      eff <- fd %>% dplyr::filter(!is.na(.data$.days)) %>%
        dplyr::group_by(.data$plotID, .data$collectDate) %>%
        dplyr::summarise(trapnights = sum(.data$.days), .groups = "drop")
    }
  }
  out <- if (is.null(eff)) dplyr::mutate(counts, trapnights = NA_real_)
         else dplyr::left_join(counts, eff, by = c("plotID", "collectDate"))
  out$source <- "neon"
  tibble::as_tibble(out)
}

# ---------------------------------------------------------------------------
# Cross-site community ordination (PCoA on Bray-Curtis), base R only.
# Each "sample" is a site x plot x year community; we measure how dissimilar
# every pair of samples is (Bray-Curtis) and lay them out in 2-D so similar
# communities sit close together. Samples from the same biome cluster — the
# classic carabid biogeography picture — without needing the vegan package.
# ---------------------------------------------------------------------------
bray_ordination <- function(d, min_total = 3, min_samples = 4) {
  if (is.null(d) || nrow(d) == 0) return(NULL)
  d <- species_only(d)              # community structure on named species only
  d <- d[!is.na(d$scientificName) & !is.na(d$individualCount), , drop = FALSE]
  if (!nrow(d)) return(NULL)
  # one community per site x year — the cross-site biogeography unit. Aggregating
  # across plots (was site x plot x year, ~3,100 samples) keeps the ordination
  # legible AND turns the Bray-Curtis matrix + cmdscale eigen — formerly the app's
  # dominant ~4-minute boot cost — into a sub-second build (~380 samples).
  d$sample <- paste(d$siteID, d$year, sep = "|")
  agg <- stats::aggregate(individualCount ~ sample + scientificName, d, sum)
  tab <- stats::xtabs(individualCount ~ sample + scientificName, data = agg)
  mat <- matrix(as.numeric(tab), nrow = nrow(tab),
                dimnames = list(rownames(tab), colnames(tab)))
  mat <- mat[rowSums(mat) >= min_total, , drop = FALSE]
  if (nrow(mat) < min_samples) return(NULL)
  # Vectorized Bray-Curtis: the numerator sum|x_i - x_j| is the Manhattan distance
  # (computed at C level by dist()), and the denominator sum(x_i + x_j) is
  # rowSum_i + rowSum_j. Replaces an O(n^2) interpreted R double-loop that
  # dominated startup.
  rs <- rowSums(mat)
  D <- as.matrix(stats::dist(mat, method = "manhattan")) / outer(rs, rs, "+")
  D[!is.finite(D)] <- 0; diag(D) <- 0
  fit <- tryCatch(stats::cmdscale(stats::as.dist(D), k = 2, eig = TRUE),
                  error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  pts <- fit$points
  out <- tibble::tibble(x = pts[, 1], y = pts[, 2], sample = rownames(mat))
  out$site <- sub("\\|.*", "", out$sample)
  ev <- fit$eig[fit$eig > 0]
  attr(out, "var_explained") <- if (length(ev) >= 2) round(100 * ev[1:2] / sum(ev)) else c(NA, NA)
  out
}

# Per-species, per-site abundance — powers the "range map" species picker.
species_site_table <- function(d) {
  if (is.null(d) || nrow(d) == 0) return(NULL)
  d <- species_only(d)              # range maps name species, not genera
  if (is.null(d) || !nrow(d)) return(NULL)
  tibble::as_tibble(stats::aggregate(individualCount ~ scientificName + siteID, d, sum))
}

# ---------------------------------------------------------------------------
# Indicator species (Dufrêne-Legendre IndVal), base R only.
# For each species we find the site it most "belongs" to. IndVal = A x B x 100:
#   A (specificity) = how concentrated the species' abundance is in that site
#   B (fidelity)    = the share of that site's samples where it actually shows up
# A species scores high only when it is both abundant in, AND consistently found
# at, one site — i.e. a genuine signature of that place. Samples are plot x year.
# ---------------------------------------------------------------------------
indicator_species <- function(d, min_total = 5) {
  if (is.null(d) || nrow(d) == 0) return(NULL)
  d <- species_only(d)              # indicators must be actual species
  d <- d[!is.na(d$scientificName) & !is.na(d$individualCount), , drop = FALSE]
  if (!nrow(d)) return(NULL)
  d$sample <- paste(d$siteID, d$plotID, d$year, sep = "|")
  n_per_site <- table(unique(d[, c("sample", "siteID")])$siteID)
  sites <- names(n_per_site)
  if (length(sites) < 2) return(NULL)
  ab <- stats::aggregate(individualCount ~ sample + scientificName + siteID, d, sum)
  tot <- tapply(ab$individualCount, ab$scientificName, sum)
  keep <- names(tot)[tot >= min_total]
  ab <- ab[ab$scientificName %in% keep, , drop = FALSE]
  if (!nrow(ab)) return(NULL)
  rows <- lapply(unique(ab$scientificName), function(sp) {
    s <- ab[ab$scientificName == sp, , drop = FALSE]
    meanab <- vapply(sites, function(g)
      sum(s$individualCount[s$siteID == g]) / as.numeric(n_per_site[g]), numeric(1))
    if (sum(meanab) <= 0) return(NULL)
    A <- meanab / sum(meanab)
    B <- vapply(sites, function(g)
      length(unique(s$sample[s$siteID == g & s$individualCount > 0])) /
        as.numeric(n_per_site[g]), numeric(1))
    iv <- A * B; g <- which.max(iv)
    data.frame(scientificName = sp, indicator_site = sites[g],
               indval = round(100 * iv[g], 1),
               specificity = round(100 * A[g]), fidelity = round(100 * B[g]),
               total = as.integer(tot[sp]), stringsAsFactors = FALSE)
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (!length(rows)) return(NULL)
  res <- do.call(rbind, rows)
  tibble::as_tibble(res[order(-res$indval), ])
}

# ---------------------------------------------------------------------------
# Environmental overlays — "compare beetle activity with environment". Ported
# from the Small Mammal Tracker (whose author wrote these as pure data/plotly
# utilities to reuse verbatim); the only beetle-specific change is the RESPONSE
# variable in the two correlation functions: monthly catch per 100 trap-nights
# (beetle CPN) instead of the mammal CPUE. See global.R ENV_LAYERS / load_site_env.
# ---------------------------------------------------------------------------

# Shift a monthly env table's dates forward by `lag` months — a driver often
# LEADS the response (a rain pulse precedes the activity it feeds).
shift_env <- function(env, lag = 0) {
  if (is.null(env) || !nrow(env)) return(env)
  env$date <- as.Date(env$date)
  lag <- as.integer(lag %||% 0)
  if (lag != 0) { lt <- as.POSIXlt(env$date); lt$mon <- lt$mon + lag; env$date <- as.Date(lt) }
  env
}

# Monthly beetle CPN time series (per ym): 100 * total individuals / trap-nights,
# where trap-nights = sum over unique (plot, bout). The response both correlation
# helpers below share.
.beetle_cpn_series <- function(d) {
  if (is.null(d) || !nrow(d) || !"ym" %in% names(d)) return(NULL)
  dd <- d[!is.na(d$ym), , drop = FALSE]
  if (!nrow(dd)) return(NULL)
  cap <- stats::aggregate(individualCount ~ ym, dd, sum, na.rm = TRUE)
  eff <- unique(dd[, c("plotID", "collectDate", "ym", "trapnights")])
  eff <- stats::aggregate(trapnights ~ ym, eff, sum, na.rm = TRUE)
  m <- merge(cap, eff, by = "ym")
  m <- m[m$trapnights > 0, , drop = FALSE]
  if (!nrow(m)) return(NULL)
  m$cpue <- 100 * m$individualCount / m$trapnights   # name 'cpue' to match the ported code
  m$date <- as.Date(paste0(m$ym, "-01"))
  m[order(m$date), c("ym", "date", "cpue")]
}

# Collapse a monthly env table to a 12-point calendar-month climatology (mean of
# each metric across years) for the by-month activity overlay; `lag` rotates the
# months so a leading driver lines up with the activity month.
env_climatology <- function(env, layer, lag = 0) {
  meta <- ENV_LAYERS[[layer]]
  if (is.null(meta) || is.null(env) || !(meta$col %in% names(env))) return(NULL)
  e <- env; e$date <- as.Date(e$date)
  e$.v <- suppressWarnings(as.numeric(e[[meta$col]]))
  e <- e[!is.na(e$.v), , drop = FALSE]
  if (!nrow(e)) return(NULL)
  e$mon <- as.integer(format(e$date, "%m"))
  clim <- stats::aggregate(.v ~ mon, data = e, FUN = mean, na.rm = TRUE)
  lag <- as.integer(lag %||% 0)
  if (lag != 0) clim$mon <- ((clim$mon - 1 + lag) %% 12) + 1
  clim <- clim[order(clim$mon), ]
  clim$value <- round(clim$.v, 1)
  clim[, c("mon", "value")]
}

# Layout spec for an env overlay's secondary axis. Anchor at zero only for
# non-negative ("fillable") drivers; temperature gets a free axis so a negative
# winter mean isn't clamped against an artificial floor.
env_axis_spec <- function(layer, side = "right", overlaying = "y", show = TRUE) {
  meta <- ENV_LAYERS[[layer]]
  if (is.null(meta)) return(list(overlaying = overlaying, side = side, visible = FALSE))
  spec <- list(title = if (show) sprintf("%s (%s)", meta$label, meta$unit) else "",
       overlaying = overlaying, side = side,
       showgrid = FALSE, zeroline = FALSE, color = meta$color, showticklabels = show)
  if (isTRUE(meta$fillable)) spec$rangemode <- "tozero"
  spec
}

# Scan lags 0..max_lag for the strongest DESEASONALIZED correlation between this
# site's monthly beetle CPN and a lagged driver. Both series have their
# calendar-month climatology removed first, so r reflects year-to-year ANOMALIES
# (not the shared "both peak in summer" cycle, which would inflate |r|). Returns
# best lag + Pearson r, or NULL when there's too little monthly overlap.
env_corr_scan <- function(d, env, layer, max_lag = 12) {
  meta <- ENV_LAYERS[[layer]]
  if (is.null(meta) || is.null(env) || !(meta$col %in% names(env))) return(NULL)
  m <- .beetle_cpn_series(d)
  if (is.null(m) || nrow(m) < 8) return(NULL)             # honest monthly-overlap floor
  ev <- env; ev$date <- as.Date(ev$date)
  ev$.v <- suppressWarnings(as.numeric(ev[[meta$col]]))
  ev <- ev[!is.na(ev$.v), c("date", ".v"), drop = FALSE]
  if (!nrow(ev)) return(NULL)
  deseason <- function(val, date) {
    mon <- as.integer(format(date, "%m"))
    clim <- tapply(val, mon, mean, na.rm = TRUE)
    val - as.numeric(clim[as.character(mon)])
  }
  m$cpue <- deseason(m$cpue, m$date)
  ev$.v  <- deseason(ev$.v, ev$date)
  best <- list(lag = NA_integer_, r = NA_real_, n = 0L)
  for (lag in 0:max_lag) {
    e2 <- ev; lt <- as.POSIXlt(e2$date); lt$mon <- lt$mon + lag; e2$date <- as.Date(lt)
    j <- merge(m[, c("date", "cpue")], e2, by = "date")
    if (nrow(j) >= 8 && stats::sd(j$cpue, na.rm = TRUE) > 0 && stats::sd(j$.v, na.rm = TRUE) > 0) {
      r <- suppressWarnings(stats::cor(j$cpue, j$.v))
      if (!is.na(r) && (is.na(best$r) || abs(r) > abs(best$r)))
        best <- list(lag = lag, r = round(r, 2), n = nrow(j))
    }
  }
  if (is.na(best$r)) return(NULL)
  best$label <- meta$label; best$unit <- meta$unit
  best
}

# Month-matched (beetle CPN, lagged driver) pairs for the response scatter.
env_response_points <- function(d, env, layer, lag = 0) {
  meta <- ENV_LAYERS[[layer]]
  if (is.null(meta) || is.null(env) || !(meta$col %in% names(env))) return(NULL)
  m <- .beetle_cpn_series(d)
  if (is.null(m)) return(NULL)
  e <- shift_env(env, lag)
  e$.v <- suppressWarnings(as.numeric(e[[meta$col]]))
  e <- e[!is.na(e$.v), c("date", ".v"), drop = FALSE]
  j <- merge(m[, c("date", "cpue")], e, by = "date")
  if (nrow(j) < 3) return(NULL)
  j$year <- as.integer(format(j$date, "%Y"))
  names(j)[names(j) == ".v"] <- "value"
  tibble::as_tibble(j[order(j$date), c("date", "year", "value", "cpue")])
}

# Best-lag correlation for EVERY available driver, ranked by |r| — the data
# behind the "which driver does activity track best?" panel.
env_corr_all <- function(d, env, max_lag = 12) {
  if (is.null(d) || is.null(env)) return(NULL)
  rows <- lapply(names(ENV_LAYERS), function(k) {
    meta <- ENV_LAYERS[[k]]
    # require real coverage, not just one non-NA month, so a near-empty driver
    # (e.g. fruiting_pct, ~15 months) can't top the ranking on noise.
    if (!(meta$col %in% names(env)) || !env_has_min_coverage(env[[meta$col]])) return(NULL)
    sc <- env_corr_scan(d, env, k, max_lag)
    if (is.null(sc)) return(NULL)
    data.frame(layer = k, label = meta$label, color = meta$color,
               lag = sc$lag, r = sc$r, n = sc$n, stringsAsFactors = FALSE)
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (!length(rows)) return(NULL)
  tibble::as_tibble(do.call(rbind, rows)[order(-abs(do.call(rbind, rows)$r)), ])
}

# Permutation null for the WHOLE driver × lag dredge ------------------------
# env_corr_all() reports the single best |r| out of (n drivers × 13 lags) ≈ 65
# candidates. With only ~8–150 monthly anomalies, the largest of that many
# correlations is sizeable even under pure noise, so a raw "Strong link" verdict
# over-claims. This asks the honest question: how often does a best-of-dredge
# correlation THIS large arise from chance alignment? We circularly rotate every
# env series in time by a random whole-month offset (preserving each driver's
# autocorrelation, its deseasonalized structure, and the drivers' shared
# collinearity) and re-run the full scan, recording the null's max |r|. The
# rotation only destroys the true temporal alignment with the beetle series.
#   p = (1 + #{null max|r| >= observed}) / (1 + #perms)
# Cyclic shifts give at most n-1 distinct permutations, so a thin series honestly
# yields a coarse, conservative p (e.g. n = 8 -> floor ~ 1/8) rather than a
# falsely precise one. Seeded so the p is stable across re-renders.
env_corr_pvalue <- function(d, env, max_lag = 12, nperm = 99, min_n = 8) {
  if (is.null(d) || is.null(env)) return(NULL)
  m <- .beetle_cpn_series(d)
  if (is.null(m) || nrow(m) < min_n) return(NULL)
  # deseasonalize a value vector by removing its per-calendar-month climatology
  deseason_vec <- function(val, dt) {
    mon  <- as.integer(format(dt, "%m"))
    clim <- tapply(val, mon, mean, na.rm = TRUE)
    val - as.numeric(clim[as.character(mon)])
  }
  midx <- function(dt) { lt <- as.POSIXlt(dt); 12L * (lt$year + 1900L) + lt$mon }  # integer month index

  bdate  <- as.Date(m$date)
  b_anom <- deseason_vec(m$cpue, bdate)
  bm     <- midx(bdate)

  ev <- env; ev$date <- as.Date(ev$date); ev <- ev[order(ev$date), , drop = FALSE]
  evm  <- midx(ev$date)
  cols <- intersect(vapply(ENV_LAYERS, function(z) z$col, character(1)), names(ev))
  # same coverage floor as env_corr_all(): a near-empty driver (e.g. fruiting_pct)
  # must not enter the dredge OR its null, so the observed best |r| and the null
  # are computed over the SAME driver set.
  cols <- cols[vapply(cols, function(cc) env_has_min_coverage(ev[[cc]]), logical(1))]
  if (!length(cols)) return(NULL)

  # Lay beetle + every driver on ONE dense monthly axis (NA for gaps), so a lag
  # is a cheap vector shift and a rotation is a cheap index permute — no merge()
  # in the inner loop. ~250x faster than re-running the full scan per permutation.
  allm <- seq.int(min(c(bm, evm)), max(c(bm, evm)))
  M    <- length(allm)
  bvec <- rep(NA_real_, M); bvec[match(bm, allm)] <- b_anom
  drivers <- lapply(cols, function(cc) {
    v <- suppressWarnings(as.numeric(ev[[cc]])); keep <- !is.na(v)
    if (!any(keep)) return(NULL)
    vec <- rep(NA_real_, M); vec[match(evm[keep], allm)] <- deseason_vec(v[keep], ev$date[keep]); vec
  })
  drivers <- drivers[!vapply(drivers, is.null, logical(1))]
  if (!length(drivers)) return(NULL)

  # strongest |r| over all (driver, lag) pairs; beetle[t] vs driver[t - lag]
  best_absr <- function(dvs) {
    best <- NA_real_
    for (vec in dvs) for (L in 0:max_lag) {
      ds <- if (L == 0) vec else c(rep(NA_real_, L), vec[seq_len(M - L)])
      ok <- is.finite(bvec) & is.finite(ds)
      if (sum(ok) >= min_n) {
        bx <- bvec[ok]; dx <- ds[ok]
        if (stats::sd(bx) > 0 && stats::sd(dx) > 0) {
          r <- abs(suppressWarnings(stats::cor(bx, dx)))
          if (is.finite(r) && (is.na(best) || r > best)) best <- r
        }
      }
    }
    best
  }
  observed <- best_absr(drivers)
  if (!is.finite(observed) || M < min_n + 1L) return(NULL)

  old <- if (exists(".Random.seed", envir = .GlobalEnv)) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit(if (!is.null(old)) assign(".Random.seed", old, envir = .GlobalEnv), add = TRUE)
  set.seed(7L)
  shifts <- sample(seq_len(M - 1L), min(nperm, M - 1L))   # distinct non-zero circular shifts
  null_max <- vapply(shifts, function(k) {
    idx <- ((seq_len(M) - 1L + k) %% M) + 1L              # same rotation for every driver -> keeps collinearity
    best_absr(lapply(drivers, function(vec) vec[idx]))
  }, numeric(1))
  null_max <- null_max[is.finite(null_max)]
  if (!length(null_max)) return(NULL)
  list(observed  = round(observed, 2),
       p         = (1 + sum(null_max >= observed - 1e-9)) / (1 + length(null_max)),
       nperm     = length(null_max),
       n_search  = length(drivers) * (max_lag + 1L),
       n_drivers = length(drivers))
}

# Minimum non-NA months a driver must have to ENTER the dredge. A column that is
# present but near-empty (e.g. fruiting_pct: ~15 non-NA months at SRER, inherited
# verbatim from the mammal app) is not "empty" — the any(!is.na()) test passes — so
# it can still win the best-of-dredge on 15 points of noise. Requiring >= 2 years
# of monthly coverage drops that thin column from BOTH the ranking and its
# permutation null, so neither ranks a driver on a sliver of data.
ENV_MIN_MONTHS <- 24L
env_has_min_coverage <- function(v) sum(!is.na(v)) >= ENV_MIN_MONTHS

# ec_corr_color() — single source of truth for the hue of a (driver, r) pair:
# identity->hue family, direction->pole (only where sign is ALSO geometric),
# magnitude->loudness (weak links fade to the surface; |r|<0.2 -> neutral grey).
EC_CORR_POLES <- list(
  precip  = list(pos = c("#1f6fb2", "#5aa9e6"), neg = c("#b07a35", "#d8a85a")),
  temp    = list(pos = c("#d9480f", "#ff7a45"), neg = c("#2f7fb5", "#6cc4ec")),
  flower  = list(pos = c("#c2255c", "#f06595"), neg = c("#7a8a99", "#9aa7b5")),
  greenup = list(pos = c("#2b8a3e", "#69db7c"), neg = c("#9c6644", "#c08457")),
  fruit   = list(pos = c("#9c6644", "#c08457"), neg = c("#2f7fb5", "#6cc4ec"))
)
blend_hex <- function(a, b, w) {
  ca <- grDevices::col2rgb(a); cb <- grDevices::col2rgb(b)
  m <- round(ca * (1 - w) + cb * w)
  grDevices::rgb(m[1], m[2], m[3], maxColorValue = 255)
}
ec_corr_color <- function(layer, r, dark = FALSE) {
  if (length(r) != 1 || is.na(r)) return("#8a97a8")
  s <- abs(r)
  if (s < 0.2) return("#8a97a8")
  pole <- EC_CORR_POLES[[layer]]
  base <- if (is.null(pole)) (ENV_LAYERS[[layer]]$color %||% "#8a97a8")
          else (if (r >= 0) pole$pos else pole$neg)[[if (dark) 2L else 1L]]
  surf <- if (dark) "#18241f" else "#ffffff"
  w <- if (s >= 0.6) 0 else if (s >= 0.35) 0.15 else 0.40
  blend_hex(base, surf, w)
}
