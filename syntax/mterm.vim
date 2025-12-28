if exists("b:current_syntax")
  finish
endif

syn match Debug /^DEBUGPRINT/

let b:current_syntax = "mterm"
