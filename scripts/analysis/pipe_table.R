# Markdown pipe table with chosen relative column widths (dash counts), for results = "asis" chunks in the proposal
pipe_table <- function(df, widths, caption = NULL, id = NULL) {
  esc <- function(x) gsub("\\|", "/", as.character(x))
  hdr <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep <- paste0("|", paste(vapply(widths, function(w) strrep("-", w), ""), collapse = "|"), "|")
  rows <- apply(df, 1, function(r) paste0("| ", paste(esc(r), collapse = " | "), " |"))
  out <- c(hdr, sep, rows)
  if (!is.null(caption)) out <- c(out, "", sprintf(": %s%s", caption, if (is.null(id)) "" else sprintf(" {#%s}", id)))
  paste(out, collapse = "\n")
}
