#!/usr/bin/lua
-- File created 2025-11-30 00:47:36 CET

local lfs = require("lfs")
local posix = require("posix")

local dry_run = true

local src_dir = "/home/ost"
local dst_dir = "/mnt/LINUX_BACKUP/home_backup"
local backup_dev = "/dev/sdb2"
local mount_point = "/mnt/LINUX_BACKUP"
local exclude_path = "/home/ost/backup_exclude.txt"
local log_path = "/tmp/rsync_home_backup_log.txt"

local datetime = os.date("%Y-%m-%d__%H_%M_%S")

local backup_path = dst_dir.."/"..datetime
local latest      = dst_dir.."/LATEST"
local latest_tmp  = dst_dir.."/LATEST_TMP"

local weekday = dst_dir.."/"..os.date("%a")
local month   = dst_dir.."/"..os.date("%b")
local year    = dst_dir.."/"..os.date("%Y")

local function dir_exists(path)
  return lfs.attributes(path, "mode") == "directory"
end
local function is_sym_link(path)
  return lfs.symlinkattributes(path) == "link"
end
local function is_dir(path)
  return lfs.attributes(path) == "directory"
end

local function do_cmd(cmd)
  print(cmd)
  if not dry_run then assert(os.execute(cmd)) end
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

print(src_dir)
print(dst_dir)
print(backup_path)
print(src_dir)
print(src_dir)
print(src_dir)
print(src_dir)
print(src_dir)
print(src_dir)

print("src_dir:     "..src_dir)
print("dst_dir:     "..dst_dir)
print("backup_path: "..backup_path)
print("latest:      "..latest)
print("weekday:     "..weekday)
print("month:       "..month)
print("year:        "..year)

print(     "mount "..backup_dev.." "..mount_point)
os.execute("mount "..backup_dev.." "..mount_point)
assert(dir_exists(dst_dir))

local rsync_args = {
  "-avH --delete",
  "--exclude-from="..exclude_path,
  "--link-dest="..latest,
  "--log-file="..log_path,
  src_dir.." "..backup_path,
}
local rsync_cmd = "rsync"
for _, arg in ipairs(rsync_args) do
  rsync_cmd = rsync_cmd.." "..arg
end
print(rsync_cmd)
do_cmd(rsync_cmd)

sym_link_relative(backup_path, latest_tmp)
mv(latest_tmp, latest)

rm_dir_recursive(weekday)
sym_link_relative(backup_path, weekday)
rm_dir_recursive(month)
sym_link_relative(backup_path, month)
rm_dir_recursive(year)
sym_link_relative(backup_path, year)

for dir in lfs.dir(dst_dir) do
  local dir_path = dst_dir.."/"..dir
  if dir == "." or dir == ".." then
    goto continue_outer
  end
  if is_sym_link(dir_path) or is_dir(dir_path) then
    goto continue_outer
  end

  for link in lfs.dir(dst_dir) do
    local link_path = dst_dir.."/"..link
    if link == "." or link == ".." then
      goto continue_inner
    end
    if is_sym_link(link_path) then
      print("Link found! "..link.." -> "..dir)
      goto continue_outer -- We found a symbolic link to dir, so we don't delete dir.
    end
    ::continue_inner::
  end

  -- We didn't find a symbolic link to dir, so we delete
  rm_dir_recursive(dir_path)

  ::continue_outer::
end
