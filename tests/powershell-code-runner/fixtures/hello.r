values <- commandArgs(trailingOnly = TRUE)
cat("OK:", paste(values, collapse = "|"), "\n", sep = "")
quit(status = 3)
