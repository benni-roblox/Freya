--//
--// * GitFetch for Freya
--// | Handles resolving GitHub Freya packages
--//

-- You'll need to take a look at the API, bright-eyes.

--// Headers:
--// # Accept: application/vnd.github.v3+json
--// # Authorization: token {OAuth Token}
--// # User-Agent: CrescentCode/Freya

--// APIs:
--// # Trees (https://developer.github.com/v3/git/trees/)
--// ## GET /repos/:owner/:repo/git/trees/:sha?recursive=1
--// # Contents (https://developer.github.com/v3/repos/contents/)
--// ## GET /repos/:owner/:repo/readme
--// ## GET /repos/:owner/:repo/contents/:path

local ^

Plugin = _G.Freya and _G.Freya.Plugin

b64e = do
  b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  (data) ->
      return ((data\gsub('.', (x) -> 
          r,b='',x\byte()
          for i=8,1,-1
            r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0')
          return r
      )..'0000')\gsub('%d%d%d?%d?%d?%d?', (x) ->
          if (#x < 6) then return ''
          c=0
          for i=1,6
            c=c+(x\sub(i,i)=='1' and 2^(6-i) or 0)
          return b\sub(c+1,c+1)
      )..({ '', '==', '=' })[#data%3+1])

Http = game\GetService "HttpService"
GET =  (url, headers) ->
  local s
  local r
  i = 1
  while (not s) and i < 3
    s, r = pcall Http.GetAsync, Http, url, true, headers
    i += 1
    unless s
      warn "HTTP GET failed. Trying again in 5 seconds (#{i} of 3)"
      wait(5)
  return error r unless s
  return r, (select 2, pcall Http.JSONDecode, Http, r)
TEST =  (url, headers) ->
  s, r = pcall Http.GetAsync, Http, url, true, headers
  return s
POST =  (url, body, headers) ->
  local s
  local r
  i = 1
  while (not s) and i < 3
    s, r = pcall Http.PostAsync, Http, url, Http\JSONEncode(body), nil, nil, headers
    i += 1
    unless s
      warn "HTTP GET failed. Trying again in 5 seconds (#{i} of 3)"
      wait(5)
  return error r unless s
  return r, (select 2, pcall Http.JSONDecode, Http, r)
ghroot = "https://api.github.com/"
ghraw = "https://raw.githubusercontent.com/"

extignore = {
  md: true
  properties: true
  gitnore: true
  gitkeep: true
  gitignore: true
}

GetPackage = (path, Version) ->
  ptype = select 2, path\gsub('/', '')
  headers = {
    Accept: "application/vnd.github.v3+json"
    --["User-Agent"]: "CrescentCode/Freya (User #{game.CreatorId})"
  }
  if _G.Freya then
    Plugin = _G.Freya.Plugin
    a = Plugin\GetSetting 'FreyaGitToken'
    if a
      headers.Authorization = "Basic #{b64e a}"
  lGET = GET
  local GET
  GET = (u) -> lGET u, headers
  switch ptype
    when 1
      -- Test repo for existance
      repo = path -- Old code migration
      _, j = GET "#{ghroot}repos/#{repo}", headers
      return nil, "Package repository does not exist: #{repo} (#{j.message})" if j.message
      -- Get the commit sha
      -- Branch?
      if Version
        v = ResolveVersion Version
        if v.branch
          _, j = GET "#{ghroot}repos/#{repo}/commits?sha=#{v.branch}", headers
        else
          _, j = GET "#{ghroot}repos/#{repo}/commits", headers
      else
        _, j = GET "#{ghroot}repos/#{repo}/commits", headers
      return nil, "Failed to get commit details: #{j.message}" if j.message
      sha = j[1].sha
      _, j = GET "#{ghroot}repos/#{repo}/git/trees/#{sha}?recursive=1", headers
      return nil, "Failed to get repo tree: #{j.message}" if j.message
      return nil, "Truncated repository :c" if j.truncated
      _, def = GET "#{ghraw}#{repo}/#{sha}/FreyaPackage.properties"
      return nil, "Bad package definition at FreyaPackage.properties" unless def
      return nil, "Malformed package definition at FreyaPackage.properties" unless def.Type and def.Package
      origin = with Instance.new "Folder"
        .Name = "Package"
      otab = {
        Name: def.Name
        Version: def.Version or Version or sha
        Type: def.Type
        LoadOrder: def.LoadOrder
      }
      if def.Description
        print "[Info][Freya GitFetch] (Description for #{repo}):\ndef.Description"
      j = j.tree
      for i=1, #j do
        v = j[i]
        -- Get content of object if it's not a directory.
        -- If it's a directory, check if it's masking an Instance.
        _,__,ext = v.path\find '^.*/.-%.(.+)$'
        ext or= select 3, v.path\find '^[^%.]+%.(.+)$'
        ext or= v.path
        if extignore[ext]
          print "[Info][Freya GitFetch] Skipping #{v.path}"
          continue
        local inst
        if v.type == 'tree'
          -- Directory
          -- Masking?
          if v.path\find '%.lua$' -- No moon support
            print "[Info][Freya GitFetch] Building #{v.path} as a blank Instance"
            -- Masking.
            -- Create as Instance (blank)
            inst = switch ext
              when 'mod.lua' then Instance.new "ModuleScript"
              when 'loc.lua' then Instance.new "LocalScript"
              when 'lua' then Instance.new "Script"
            if inst
              inst.Name = do
                n = select 3, v.path\find '^.+/(.-)%..+$'
                n or= select 3, v.path\find '^([^%.]+)%..+$'
                n
            else
              warn "[Warn][Freya GitFetch] GitFetch does not support .#{ext} extensions"
          else
            print "[Info][Freya GitFetch] Building #{v.path} as a Folder"
            inst = with Instance.new "Folder"
              .Name do
                n = select 3, v.path\find '^.+/(.-)%..+$'
                n or= select 3, v.path\find '^([^%.]+)%..+$'
                n
        else
          name = v.path\match '^.+/(.-)%..+$'
          if name == '_'
            print "[Info][Freya GitFetch] Building #{v.path} as the source to #{v.path\match('^(.+)/[^/]-$')}"
            inst = origin
            for t in v.path\gmatch '[^/]+'
              n = t\match '^([^%.]+).+$'
              unless n == '_'
                inst = origin[n]
            inst.Source = GET "#{ghraw}#{repo}/#{sha}/#{v.path}"
            inst = nil -- There is no need to parent the Instance later
          else
            print "[Info][Freya GitFetch] Building #{v.path}."
            inst = switch ext
              when 'mod.lua' then Instance.new "ModuleScript"
              when 'loc.lua' then Instance.new "LocalScript"
              when 'lua' then Instance.new "Script"
            if inst
              inst.Name = do
                n = select 3, v.path\find '^.+/(.-)%..+$'
                n or= select 3, v.path\find '^([^%.]+)%..+$'
                n
              inst.Source = GET "#{ghraw}#{repo}/#{sha}/#{v.path}"
            else
              warn "[Warn][Freya GitFetch] GitFetch does not support .#{ext} extensions"
        if inst
          p = origin
          if v.path\find('^(.+)/[^/]-$')
            for t in v.path\match('^(.+)/[^/]-$')\gmatch '[^/]+'
              p = p[t\match '^([^%.]+).+$']
          inst.Parent = p
        else
          print "[Info][Freya GitFetch] Skipping #{v.path}."
      print "[Info][Freya GitFetch] Loaded #{path}"
      otab.Install = def.Install and origin\FindFirstChild def.Install
      otab.Update = def.Update and origin\FindFirstChild def.Update
      otab.Uninstall = def.Uninstall and origin\FindFirstChild def.Uninstall
      otab.Install and= loadstring otab.Install.Source
      otab.Update and= loadstring otab.Update.Source
      otab.Uninstall and= loadstring otab.Uninstall.Source
      otab.Package = origin\FindFirstChild def.Package
      return otab
    when 2
      repo, supak = path\match("^(.+)/([^/]+)$")
      _, j = GET "#{ghroot}repos/#{repo}", headers
      return nil, "Package repository does not exist: #{repo} (#{j.message})" if j.message
      -- Get the commit sha
      -- Branch?
      if Version
        v = ResolveVersion Version
        if v.branch
          _, j = GET "#{ghroot}repos/#{repo}/commits?sha=#{v.branch}", headers
        else
          _, j = GET "#{ghroot}repos/#{repo}/commits", headers
      else
        _, j = GET "#{ghroot}repos/#{repo}/commits", headers
      return nil, "Failed to get commit details: #{j.message}" if j.message
      sha = j[1].sha
      _, j = GET "#{ghroot}repos/#{repo}/git/trees/#{sha}", headers
      return nil, "Failed to get repo tree: #{j.message}" if j.message
      return nil, "Truncated repository :c" if j.truncated
      _, def = GET "#{ghraw}#{repo}/#{sha}/FreyaRepo.properties"
      warn "[Warn][Freya GitFetch] Missing valid FreyaRepo.properties" unless def
      -- Look for the new package
      if def
        supak = def[supak] or supak
      local nppk
      for v in *(j.tree)
        if v.path == supak
          nppk = v.sha
          break
      return nil, "Failed to find #{supak} in repo" unless nppk
      _, j = GET "#{ghroot}repos/#{repo}/git/trees/#{nppk}?recursive=1", headers
      return nil, "Failed to get repo tree: #{j.message}" if j.message
      return nil, "Truncated repository :c" if j.truncated
      _, def = GET "#{ghraw}#{repo}/#{sha}/#{supak}/FreyaPackage.properties"
      return nil, "Bad package definition at FreyaPackage.properties" unless def
      return nil, "Malformed package definition at FreyaPackage.properties" unless def.Type and def.Package
      origin = with Instance.new "Folder"
        .Name = "Package"
      otab = {
        Name: def.Name
        Version: def.Version or Version or sha
        Type: def.Type
        LoadOrder: def.LoadOrder
      }
      if def.Description
        print "[Info][Freya GitFetch] (Description for #{supak}):\ndef.Description"
      j = j.tree
      for i=1, #j do
        v = j[i]
        -- Get content of object if it's not a directory.
        -- If it's a directory, check if it's masking an Instance.
        _,__,ext = v.path\find '^.*/.-%.(.+)$'
        ext or= select 3, v.path\find '^[^%.]+%.(.+)$'
        ext or= v.path
        if extignore[ext]
          print "[Info][Freya GitFetch] Skipping #{v.path}"
          continue
        local inst
        if v.type == 'tree'
          -- Directory
          -- Masking?
          if v.path\find '%.lua$' -- No moon support
            print "[Info][Freya GitFetch] Building #{v.path} as a blank Instance"
            -- Masking.
            -- Create as Instance (blank)
            inst = switch ext
              when 'mod.lua' then Instance.new "ModuleScript"
              when 'loc.lua' then Instance.new "LocalScript"
              when 'lua' then Instance.new "Script"
            if inst
              inst.Name = do
                n = select 3, v.path\find '^.+/(.-)%..+$'
                n or= select 3, v.path\find '^([^%.]+)%..+$'
                n
            else
              warn "[Warn][Freya GitFetch] GitFetch does not support .#{ext} extensions"
          else
            print "[Info][Freya GitFetch] Building #{v.path} as a Folder"
            inst = with Instance.new "Folder"
              .Name do
                n = select 3, v.path\find '^.+/(.-)%..+$'
                n or= select 3, v.path\find '^([^%.]+)%..+$'
                n
        else
          name = v.path\match '^.+/(.-)%..+$'
          if name == '_'
            print "[Info][Freya GitFetch] Building #{v.path} as the source to #{v.path\match('^(.+)/[^/]-$')}"
            inst = origin
            for t in v.path\gmatch '[^/]+'
              n = t\match '^([^%.]+).+$'
              unless n == '_'
                inst = origin[n]
            inst.Source = GET "#{ghraw}#{repo}/#{sha}/#{supak}/#{v.path}", headers
            inst = nil -- There is no need to parent the Instance later
          else
            print "[Info][Freya GitFetch] Building #{v.path}."
            inst = switch ext
              when 'mod.lua' then Instance.new "ModuleScript"
              when 'loc.lua' then Instance.new "LocalScript"
              when 'lua' then Instance.new "Script"
            if inst
              inst.Name = do
                n = select 3, v.path\find '^.+/(.-)%..+$'
                n or= select 3, v.path\find '^([^%.]+)%..+$'
                n
              inst.Source = GET "#{ghraw}#{repo}/#{sha}/#{supak}/#{v.path}"
            else
              warn "[Warn][Freya GitFetch] GitFetch does not support .#{ext} extensions"
        if inst
          p = origin
          if v.path\find('^(.+)/[^/]-$')
            for t in v.path\match('^(.+)/[^/]-$')\gmatch '[^/]+'
              p = p[t\match '^([^%.]+).+$']
          inst.Parent = p
        else
          print "[Info][Freya GitFetch] Skipping #{v.path}."
      print "[Info][Freya GitFetch] Loaded #{path}"
      otab.Install = def.Install and origin\FindFirstChild def.Install
      otab.Update = def.Update and origin\FindFirstChild def.Update
      otab.Uninstall = def.Uninstall and origin\FindFirstChild def.Uninstall
      otab.Install and= loadstring otab.Install.Source
      otab.Update and= loadstring otab.Update.Source
      otab.Uninstall and= loadstring otab.Uninstall.Source
      otab.Package = origin\FindFirstChild def.Package
      return otab

ReadRepo = (repo) ->
  -- Repo as repo. Yes.
  paklist = {}
  ptype = select 2, repo\gsub('/', '')
  headers = {
    Accept: "application/vnd.github.v3+json"
    --["User-Agent"]: "CrescentCode/Freya (User #{game.CreatorId})"
  }
  if _G.Freya then
    Plugin = _G.Freya.Plugin
    a = Plugin\GetSetting 'FreyaGitToken'
    if a
      headers.Authorization = "Basic #{b64e a}"
  switch ptype
    when 0, nil
      -- User as repo
      _, rlist = GET "#{ghroot}users/#{repo}/repos", headers
      for r in *rlist
        -- See if it's a Freya package
        continue unless TEST "#{ghraw}#{r.full_name}/master/FreyaPackage.properties"
        _, data = GET "#{ghraw}#{r.full_name}/master/FreyaPackage.properties", headers
        continue unless data and (data.Name or data.Package)
        paklist[r.name] = "github:#{r.full_name}"
    when 1
      -- Repo as repo
      return {} unless TEST "#{ghraw}#{repo}/master/FreyaRepo.properties"
      _, data = GET "#{ghraw}#{repo}/master/FreyaRepo.properties", headers
      unless data
        warn "[Warn][Freya GitFetch] Bad FreyaRepo file for #{repo}"
        return {}
      _, tree = GET "#{ghroot}repos/#{repo}/git/trees/master", headers
      if tree.message or tree.truncated
        warn "[Warn][Freya GitFetch] Bad repository tree for #{repo}"
        return {}
      ldat = {}
      for k,v in pairs data
        if type(v) == 'string' and not v\find ':'
          ldat[k] = v
        else
          paklist[k] = v
      do
        _ldat = {}
        for k,v in pairs ldat
          lt = _ldat[v] or {}
          lt[#lt+1] = k
          _ldat[v] = lt
        ldat = _ldat
      for t in *tree.tree
        continue unless t.type == 'tree'
        continue unless TEST "#{ghraw}#{repo}/master/#{t.path}/FreyaPackage.properties"
        _, pdat = GET "#{ghraw}#{repo}/master/#{t.path}/FreyaPackage.properties"
        continue unless pdat and (pdat.Name or pdat.Package)
        nom = t.path
        paklist[nom] = "github:#{repo}/#{nom}"
        if ldat[nom]
          for v in *ldat[nom]
            paklist[v] = paklist[nom]
  return paklist
Interface = {
  Ignore: extignore
  :ghroot
  :ghraw
  :POST
  :GET
  :TEST
  :GetPackage
  :ReadRepo
}

ni = newproxy true
with getmetatable ni
  .__index = Interface
  .__tostring = -> "GitFetch for Freya"
  .__metatable = "Locked metatable: Freya"

for k,v in pairs Interface
  Interface[k] = (...) ->
    return v ... if ni != ... else v select 2, ...

return ni
