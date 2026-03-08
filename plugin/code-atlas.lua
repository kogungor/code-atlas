local ok, code_atlas = pcall(require, "code-atlas")
if not ok then
  return
end

code_atlas.create_user_commands()
