#!/usr/bin/lua
-- File created 2025-11-30 00:47:36 CET

local lfs = require("lfs")
local posix = require("posix")
local inspect = require("inspect")

local dry_run = false

local function dir_exists(path)
  return lfs.attributes(path, "mode") == "directory"
end
local function get_sym_link_target(path)
  -- print("is_sym_link "..path)
  local attrs = lfs.symlinkattributes(path)
  if attrs.mode ~= "link" then return nil end
  return attrs.target
end
local function is_dir(path)
  return lfs.attributes(path) == "directory"
end

local function do_cmd(cmd)
  print(cmd)
  if not dry_run then assert(os.execute(cmd)) end
end
local function do_cmd_always(cmd)
  print(cmd)
  assert(os.execute(cmd))
end
local function sym_link_relative(src, dst)
  do_cmd("ln -s --relative "..src.." "..dst)
end
local function mv(src, dst)
  do_cmd("mv -T "..src.." "..dst)
end
local function rm_dir_recursive(dir)
  do_cmd("rm -rf "..dir)
end
local function rm_dir(dir)
  do_cmd("rm -f "..dir)
end

local function parse_ini(filepath)
  local sections = {}
  local curr = sections
  local line_num = 1
  for line in io.lines(filepath) do
    line = line:match("^%s*(.-)%s*$")
    local section = line:match("^%[(.+)%]$")
    local key = line:match("^(.-)%s*%=")
    if section then
      curr = {}
      sections[section] = curr
    elseif key then
      assert(curr ~= nil, filepath..":"..line_num..": Section missing before line " .. line_num)
      local val = line:match("^.-%s*%=%s*(.+)$") or ""
      assert(curr[key] == nil, filepath..":"..line_num..": Element with key '"..key.."' already exists")
      curr[key] = val
    end
    line_num = line_num + 1
  end
  return sections
end

local function set_defaults(trgt, src)
  for k, v in pairs(src) do
    if trgt[k] == nil then
      trgt[k] = v
    end
  end
end

local function load_cfg(filepath)
  local cfg = parse_ini(filepath)
  local defaults = {
    src_dirs = {"/home/", "/root", "/etc/"},
    dst_dir = nil,
    backup_dev = nil,
    mount_point = nil,
    exclude_path = "/root/lua_backup_exclude.txt",
    log_path = "/tmp/lua_backup_log.txt",
  }
  set_defaults(cfg, defaults)
  return cfg
end

local cfg_filepath = "/root/lua_backup.ini"
local cfg = load_cfg(cfg_filepath)
print(cfg_filepath.." loaded:")
print(inspect(cfg))
assert(cfg.dst_dir)
assert(cfg.mount_point)

-- local src_dirs = {}
-- for s in cfg.src_dirs:gmatch("([^,]+)") do
--   s = s:match("^%s*(.-)/?%s*$")
--   table.insert(src_dirs, s)
-- end

local datetime = os.date("%Y-%m-%d__%H_%M_%S")

local backup_path = cfg.dst_dir.."/"..datetime
local latest      = cfg.dst_dir.."/LATEST"
local latest_tmp  = cfg.dst_dir.."/LATEST_TMP"

local weekday = cfg.dst_dir.."/"..os.date("%a")
local month   = cfg.dst_dir.."/"..os.date("%b")
local year    = cfg.dst_dir.."/"..os.date("%Y")

-- print("src_dirs:     "..inspect(src_dirs))
print("src_dirs:     "..cfg.src_dirs)
print("dst_dir:     "..cfg.dst_dir)
print("backup_path: "..backup_path)
print("latest:      "..latest)
print("weekday:     "..weekday)
print("month:       "..month)
print("year:        "..year)


if cfg.backup_dev then
  assert(cfg.mount_point)
  do_cmd("mount "..cfg.backup_dev.." "..cfg.mount_point)
end
if cfg.mount_point then
  assert(cfg.dst_dir:sub(1, #cfg.mount_point) == cfg.mount_point)
end
assert(dir_exists(cfg.dst_dir))

local rsync_args = {
  "-avH --delete --relative",
  "--exclude-from="..cfg.exclude_path,
  "--link-dest="..latest,
  "--log-file="..cfg.log_path,
  cfg.src_dirs.." "..backup_path,
}
local rsync_cmd = "rsync"
if dry_run then
  rsync_cmd = rsync_cmd.." --dry-run"
end
for _, arg in ipairs(rsync_args) do
  rsync_cmd = rsync_cmd.." "..arg
end
do_cmd_always(rsync_cmd)

sym_link_relative(backup_path, latest_tmp)
mv(latest_tmp, latest)

rm_dir(weekday)
sym_link_relative(backup_path, weekday)
rm_dir(month)
sym_link_relative(backup_path, month)
rm_dir(year)
sym_link_relative(backup_path, year)

print("Deleting old backups...")
for dir in lfs.dir(cfg.dst_dir) do
  local dir_path = cfg.dst_dir.."/"..dir
  if dir == "." or dir == ".." then
    goto continue_outer
  end
  if get_sym_link_target(dir_path) or is_dir(dir_path) then
    goto continue_outer
  end
  print("#"..dir_path)

  for link in lfs.dir(cfg.dst_dir) do
    local link_path = cfg.dst_dir.."/"..link
    if link == "." or link == ".." then
      goto continue_inner
    end
    local sym_link_target = get_sym_link_target(link_path)
    if sym_link_target and sym_link_target == dir then
      print("Link found! "..link.." -> "..dir)
      goto continue_outer -- We found a symbolic link to dir, so we don't delete dir.
    end
    ::continue_inner::
  end

  print("Link not found, deleting...")
  -- We didn't find a symbolic link to dir, so we delete
  rm_dir_recursive(dir_path)

  ::continue_outer::
end
