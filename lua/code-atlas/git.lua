local M = {}

local function run_git(root, args, opts)
  opts = opts or {}
  local cmd = { "git", "-C", root }
  for _, arg in ipairs(args or {}) do
    cmd[#cmd + 1] = arg
  end

  local timeout = tonumber(opts.timeout_ms) or 4000
  local ok, result = pcall(vim.system, cmd, { text = true, timeout = timeout })
  if not ok or not result then
    return nil, "failed to execute git command"
  end

  local completed = result:wait()
  if completed.code ~= 0 then
    local stderr = (completed.stderr or ""):gsub("%s+$", "")
    if stderr == "" then
      stderr = "git command failed"
    end
    return nil, stderr
  end

  local stdout = completed.stdout or ""
  return stdout, nil
end

local function parse_num(value)
  if value == "-" then
    return 0
  end
  return tonumber(value) or 0
end

function M.repo_root(path)
  local root, err = run_git(path, { "rev-parse", "--show-toplevel" })
  if not root then
    return nil, err
  end
  local normalized = (root:gsub("%s+$", ""))
  if normalized == "" then
    return nil, "unable to determine git root"
  end
  return vim.fs.normalize(normalized), nil
end

function M.history_with_stats(root, opts)
  opts = opts or {}
  local limit = math.max(1, math.floor(tonumber(opts.limit) or 30))

  local args = {
    "log",
    "--date=iso-strict",
    string.format("--pretty=format:%s", "@@@%H\t%ad\t%an\t%s"),
    "--numstat",
    "-n",
    tostring(limit),
  }

  if opts.include_merges ~= true then
    args[#args + 1] = "--no-merges"
  end

  if opts.since and tostring(opts.since) ~= "" then
    args[#args + 1] = "--since=" .. tostring(opts.since)
  end

  if opts.path and tostring(opts.path) ~= "" then
    args[#args + 1] = "--"
    args[#args + 1] = tostring(opts.path)
  end

  local out, err = run_git(root, args, {
    timeout_ms = opts.timeout_ms,
  })
  if not out then
    return nil, err
  end

  local commits = {}
  local current = nil
  for line in (out .. "\n"):gmatch("([^\n]*)\n") do
    if line:sub(1, 3) == "@@@" then
      local hash, date, author, subject = line:sub(4):match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t(.*)$")
      current = {
        hash = hash,
        date = date,
        author = author,
        subject = subject,
        files = {},
        files_count = 0,
        insertions = 0,
        deletions = 0,
      }
      commits[#commits + 1] = current
    elseif current and line ~= "" then
      local added, deleted, path = line:match("^(%S+)\t(%S+)\t(.+)$")
      if added and deleted and path then
        local file = {
          path = path,
          added = parse_num(added),
          deleted = parse_num(deleted),
        }
        current.files[#current.files + 1] = file
        current.files_count = current.files_count + 1
        current.insertions = current.insertions + file.added
        current.deletions = current.deletions + file.deleted
      end
    end
  end

  return commits, nil
end

return M
