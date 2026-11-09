-- Quarto leaves the image caption empty for crossref figures, so pandoc's docx
-- writer writes an empty Description. Copy fig-alt into the image's alt text
-- (the visible figure caption is unaffected).
function Image(img)
  local a = img.attributes["fig-alt"] or img.attributes["alt"]
  if a and a ~= "" then
    img.caption = { pandoc.Str(a) }
    return img
  end
end
