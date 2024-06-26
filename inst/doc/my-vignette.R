## ----include = FALSE----------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ----setup--------------------------------------------------------------------
library(LexFindR)

## ----installation, eval = FALSE-----------------------------------------------
#  # Install LexFindR from CRAN
#  install.packages("LexFindR")
#  
#  # Or the development version from GitHub:
#  # install.packages("devtools")
#  devtools::install_github("maglab-uconn/LexFindR")

## ----getting-started----------------------------------------------------------
library(LexFindR)

# Get cohort index of ark in dictionary of ark, art and bab
target <- "AA R K"
lexicon <- c("AA R K", "AA R T", "B AA B")

cohort <- get_cohorts(target, lexicon)
cohort

# To get forms rather than indices using base R
lexicon[cohort]

# To get forms rather than indices using the form option
get_cohorts(target, lexicon, form = TRUE)

# Get count using base R
length(cohort)

# Get count using the count option
get_cohorts(target, lexicon, count = TRUE)

# Frequency weighting
target_freq <- 50
lexicon_freq <- c(50, 274, 45)

# get the summed log frequencies of competitors
get_fw(lexicon_freq)

# 
get_fwcp(target_freq, lexicon_freq)

## ----comment-on-CMU-----------------------------------------------------------
# By default, CMU has numbers that indicate stress patterns
# 
# If you do not strip those out, instances of the same vowel
# with different stress numbers will be treated as different
# symbols. This may be useful for some purposes (e.g., finding
# cohorts or neighbors with the same stress pattern).
# 
# Here is a contrived example, where ARK will not be considered
# related to ART or BARK because of stress pattern differences
target <- "AA0 R K"
lexicon <- c("AA0 R K", "AA2 R T", "B AA3 R K")

get_cohorts(target, lexicon, form = TRUE)
get_neighbors(target, lexicon, form = TRUE)

# If this is not the behavior we want, we can strip lexical 
# stress indicators using regular expressions
target <- gsub("\\d", "", target)
lexicon <- gsub("\\d", "", lexicon)

print(target)
print(lexicon)

get_cohorts(target, lexicon, form = TRUE)
get_neighbors(target, lexicon, form = TRUE)


## ----slex-cohort-example------------------------------------------------------
library(tidyverse)
glimpse(slex)

# define the lexicon with the list of target words to compute
# cohorts for; we will use *target_df* instead of modifying
# slex or lemmalex directly
target_df <- slex

# specify the reference lexicon; here it is actually the list
# of pronunciations from slex, as we want to find all cohorts
# for all words in our lexicon. It is not necessary to create
# a new dataframe, but because we find it useful for more
# complex tasks, we use this approach here
lexicon_df <- target_df

# this instruction will create a new column in our target_df
# dataframe, "cohort_idx", which will be the list of lexicon_df
# indices corresponding to each word's cohort set
target_df$cohort_idx <-
  lapply(
    # in each lapply instance, select the target pronunciation
    target_df$Pronunciation,
    # in each lapply instance, apply the get_cohorts function
    FUN = get_cohorts,
    # in each lapply instance, compare the current target 
    # Pronunciation to each lexicon Pronunciation
    lexicon = lexicon_df$Pronunciation
  )

# let's look at the first few instances in each field...
glimpse(target_df)


## ----slex-rhyme-tidyverse-----------------------------------------------------
slex_rhymes <- slex %>% mutate(
  rhyme_idx = lapply(Pronunciation, get_rhymes, lexicon = Pronunciation),
  rhyme_str = lapply(rhyme_idx, function(idx) {
    Item[idx]
  }),
  rhyme_count = lengths(rhyme_idx)
)

glimpse(slex_rhymes)

slex_rhymes <- slex_rhymes %>%
  rowwise() %>%
  mutate(
    rhyme_freq = list(slex$Frequency[rhyme_idx]),
    rhyme_fw = get_fw(rhyme_freq),
    rhyme_fwcp = get_fwcp(Frequency, rhyme_freq)
  ) %>% 
  ungroup()

glimpse(slex_rhymes)

## ----parallelize, cache = TRUE------------------------------------------------
library(future.apply)
library(tictoc)

# using two cores for demo or else 
# set `workers` to availableCores() to use all cores
plan(multisession, workers = 2)

glimpse(lemmalex)


# the portion between tic and toc below takes ~X seconds on a 
# 15-inch Macbook Pro 6-core i9; if you replace future_lapply 
# with lapply, it takes ~317 secs, v. 66 secs with future_lapply

tic("Finding rhymes")

slex_rhyme_lemmalex <- lemmalex %>% mutate(
  rhyme = future_lapply(Pronunciation, get_rhymes, 
                            lexicon = lemmalex$Pronunciation),
  rhyme_str = lapply(rhyme, function(idx) {
    lemmalex$Item[idx]
  }),
  rhyme_len = lengths(rhyme)
)

toc()

glimpse(slex_rhyme_lemmalex)

## ----extended-example---------------------------------------------------------
library(LexFindR)
library(tidyverse) # for glimpse
library(future.apply) # parallelization
library(tictoc) # timing utilities

# In this example, we define a dataframe source for target words
# (target_df) and another for the lexicon to compare the target
# words to (lexicon_df). Often, these will be the same, but we keep
# them separate here to make it easier for others to generalize from
# this example code.

# Code assumes you have at least 3 columns in target_df & lexicon_df:
# 1. Item -- a label of some sort, can be identical to Pronunciation
# 2. Pronunciation -- typically a phonological form
# 3. Frequency -- should be in occurrences per million, or some other
#                 raw form, as the functions below take the log of
#                 the frequency form. See advice about padding in
#                 the main article text.
#
# Of course, you can name your fields as you like, and edit the
# field names below appropriately.
target_df <- slex
lexicon_df <- target_df

# Prepare for parallelizing
# 1. how many cores do we have?
# num_cores <- availableCores()

# using two cores for demo
num_cores <- 2

print(paste0("Using num_cores: ", num_cores))
# 2. now let future.apply figure out how to optimize parallel
#    division of labor over cores
plan(multisession, workers = num_cores)

# the functions in this list all return lists of word indices; the
# uniqueness point function is not included because it returns a
# single value per word.
fun_list <- c(
  "cohorts", "neighbors",
  "rhymes", "homoforms",
  "target_embeds_in", "embeds_in_target",
  "nohorts", "cohortsP", "neighborsP",
  "target_embeds_inP", "embeds_in_targetP"
)

# we need to keep track of the P variants, as we need to tell get_fwcp
# to add in the target frequency for these, as they exclude the target
Ps <- c(
  "cohortsP", "neighborsP", "target_embeds_inP",
  "embeds_in_targetP"
)

# determine how much to pad based on minimum frequency
if (min(target_df$Frequency) == 0) {
  pad <- 2
} else if (min(target_df$Frequency) < 1) {
  pad <- 1
} else {
  pad <- 0
}

# now let's loop through the functions
for (fun_name in fun_list) {
  # start timer for this function
  tic(fun_name)

  # the P functions do not include the target in the denominator for
  # get_fwcp; if we want this to be a consistent ratio, we need to
  # add target frequency to the denominator
  add_target <- FALSE
  if (fun_name %in% Ps) {
    add_target <- TRUE
  }

  # inform the user that we are starting the next function, make sure
  # we are correctly adding target or not
  cat("Starting", fun_name, " -- add_target = ", add_target)
  func <- paste0("get_", fun_name)

  # use *future_lapply* to do the competitor search, creating
  # a new column in *target_df* that will be this function's
  # name + _idx (e.g., cohort_idx)
  target_df[[paste0(fun_name, "_idx")]] <-
    future_lapply(target_df$Pronunciation,
      FUN = get(func),
      lexicon = lexicon_df$Pronunciation
    )

  # list the competitor form labels in functionname_str
  target_df[[paste0(fun_name, "_str")]] <- lapply(
    target_df[[paste0(fun_name, "_idx")]],
    function(idx) {
      lexicon_df$Item[idx]
    }
  )

  # list the competitor frequencies in functionname_freq
  target_df[[paste0(fun_name, "_freq")]] <- lapply(
    target_df[[paste0(fun_name, "_idx")]],
    function(idx) {
      lexicon_df$Frequency[idx]
    }
  )

  # put the count of competitors in functionname_num
  target_df[[paste0(fun_name, "_num")]] <-
    lengths(target_df[[paste0(fun_name, "_idx")]])

  # put the FW in functionname_fwt
  target_df[[paste0(fun_name, "_fwt")]] <-
    mapply(get_fw,
      competitors_freq = target_df[[paste0(fun_name, "_freq")]],
      pad = pad
    )

  # put the FWCP in functionname_fwcp
  target_df[[paste0(fun_name, "_fwcp")]] <-
    mapply(get_fwcp,
      target_freq = target_df$Frequency,
      competitors_freq = target_df[[paste0(fun_name, "_freq")]],
      pad = pad, add_target = add_target
    )

  toc()
}

# Note that get_neighborsP excludes rhymes. If you do not want to 
# track rhymes separately and want neighborsP to include all 
# rhymes that are not cohorts, you can create new fields that 
# combine them, as we do here, creating "Pr" versions
target_df$neighborsPr_num = target_df$neighborsP_num + target_df$rhymes_num
target_df$neighborsPr_fwcp = target_df$neighborsP_fwcp + target_df$rhymes_fwcp
target_df$neighborsPr_fwt = target_df$neighborsP_fwt + target_df$rhymes_fwt

# Now let's streamline the dataframe; we'll select the num, fwt, and fwcp
# columns and put them in that order, while not keeping some of the other
# 'helper' columns we created

export_df <- target_df %>% 
  select(Item | Pronunciation |	Frequency 
         | ends_with("_num") | ends_with("_fwt") | ends_with("_fwcp"))

glimpse(export_df)

