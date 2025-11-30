local runners = { javascript = 'node {file}', rust = 'cargo run {file}' }
Task.termrun = function()
  -- fetch project-local config
  local cmd = u.project(uv.cwd()).runner or runners[vim.bo.ft]
  if not cmd then return end
  cmd = cmd:gsub('%{file%}', api.nvim_buf_get_name(0))
  if mt.is_empty() then
    mt.open(nil, false, { layout = 'bot' })
  else
    mt.open()
  end
  mt.send_key('G')
end
