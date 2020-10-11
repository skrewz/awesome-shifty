--- Shifty: Dynamic tagging library, version for awesome v3.5
-- @author koniu &lt;gkusnierz@gmail.com&gt;
-- @author resixian (aka bioe007) &lt;resixian@gmail.com&gt;
-- @author cdump &lt;andreevmaxim@gmail.com&gt;
--
-- https://github.com/cdump/awesome-shifty
-- http://awesome.naquadah.org/wiki/index.php?title=Shifty

-- environment
local type = type
local ipairs = ipairs
local table = table
local string = string
local beautiful = require("beautiful")
local awful = require("awful")
local wibox = require("wibox")
local pairs = pairs
local io = io
local tonumber = tonumber
local capi = {
    client = client,
    tag = tag,
    screen = screen,
    button = button,
    mouse = mouse,
    root = root,
}
local gears = require("gears")

local shifty = {}

-- variables
shifty.config = {}
shifty.config.tags = {}
shifty.config.apps = {}
shifty.config.defaults = {}
shifty.config.float_bars = false
shifty.config.guess_name = true
shifty.config.guess_position = true
shifty.config.remember_index = true
shifty.config.sloppy = true
shifty.config.default_name = "new"
shifty.config.clientkeys = {}
shifty.config.globalkeys = nil
shifty.config.layouts = {}
shifty.config.prompt_sources = {
    "config_tags",
    "config_apps",
    "existing",
    "history"
}
shifty.config.prompt_matchers = {
    "^",
    ":",
    ""
}
shifty.config.delete_deserted = true

local matchp = ""
-- skrewz@20170208: commented; usefulness not certain (?)
--local index_cache = {}
--for i = 1, capi.screen.count() do index_cache[i] = {} end

--name2tags: matches string 'name' to tag objects
-- @param name : tag name to find
-- @param scr : screen to look for tags on
-- @return table of tag objects or nil
function name2tags(name, scr)
    local ret = {}
    --skrewwz@20170208: algorithm changed; "scr" needs to be re-integrated
    for s in screen do
        for i, t in ipairs(s.tags) do
            if name == t.name then
                table.insert(ret, t)
            end
        end
    end
    if #ret > 0 then return ret end
end

function name2tag(name, scr, idx)
    local ts = name2tags(name, scr)
    if ts then return ts[idx or 1] end
end

--substr_name2tags: finds tags by substring of name
-- @param needle: what to search for
-- @param scr: which screen to search in
-- @return: table of tag objects or nil
function substr_name2tags (needle)
    local ret = {}
    local try_screens = {}
    -- FIXME: respect any pased scr
    for s in screen do
        for i, t in ipairs(s.tags) do
            if string.find(t.name:lower(),needle:lower()) then
                table.insert(ret, t)
            end
        end
    end
    if #ret > 0 then return ret end
end

--substr_name2clients: finds clients by substring of name
-- @param needle: what to search for
-- @param scr: which screen to search in
-- @return: table of client objects or nil
function substr_name2clients (needle)
    local ret = {}
    local try_screens = {}
    -- FIXME: respect any pased scr
    for _, c in ipairs(client.get()) do
      if string.find(c.name:lower(),needle:lower()) then
          table.insert(ret, c)
      end
    end
    if #ret > 0 then return ret end
end

--tag2index: finds index of a tag object
-- @param scr : screen number to look for tag on
-- @param tag : the tag object to find
-- @return the index [or zero] or end of the list
function tag2index(scr, tag)
    for i, t in ipairs(scr.tags) do
        if t == tag then return i end
    end
end

--rename
--@param tag: tag object to be renamed
--@param prefix: if any prefix is to be added
--@param no_selectall:
function shifty.rename(tag, prefix, no_selectall)
    local theme = beautiful.get()
    local t = tag or awful.screen.focused().selected_tag

    if t == nil then return end

    local scr = t.screen
    local bg = nil
    local fg = nil
    local text = prefix or t.name
    local before = t.name

    if t == scr.selected_tag then
        bg = theme.bg_focus or '#535d6c'
        fg = theme.fg_urgent or '#ffffff'
    else
        bg = theme.bg_normal or '#222222'
        fg = theme.fg_urgent or '#ffffff'
    end
    
    local tag_index = tag2index(scr, t)
    -- Access to textbox widget in taglist
    -- skrewz@20170202: these are not widgets. They're labels. They are unlikely to be editable.
    -- See function taglist.taglist_label(t, args) in awful.widget.taglist.
    -- TODO: Workaround: what about a separate prompt-for-new-name wibox?
    --local tb_widget = scr.mytaglist.widgets[tag_index].widget.widgets[2].widget
    -- This is a bit of a workaround. The expectation is that you have a
    -- mypromptbox on each screen:
    -- See e.g. rc.lua on https://awesomewm.org/apidoc/documentation/17-porting-tips.md.html#v4
    local tb_widget = scr.mypromptbox
    awful.prompt.run({
        fg_cursor = fg, bg_cursor = bg, ul_cursor = "single",
        text = text,
        selectall = not no_selectall,
        textbox = tb_widget,
        exe_callback = function (name) if name:len() > 0 then t.name = name; end end,

        completion_callback = completion,
        history_path = awful.util.getdir("cache") .. "/history_tags",
        done_callback = function ()
            if t.name == before then
                if awful.tag.getproperty(t, "initial") then shifty.del(t) end
            else
                awful.tag.setproperty(t, "initial", true)
                set(t)
            end
            tagkeys(capi.screen[scr])
            t:emit_signal("property::name")
          end,
        changed_callback = shifty.schedule_tag_statesave()
        }
    )
end

--send: moves client to tag[idx]
-- maybe this isn't needed here in shifty?
-- @param idx the tag number to send a client to
function send(idx)
    local scr = capi.client.focus.screen or capi.mouse.screen
    local sel = scr.selected_tag
    local sel_idx = tag2index(scr, sel)
    local tags = scr.tags
    local target = awful.util.cycle(#tags, sel_idx + idx)
    capi.client.focus:move_to_tag(tags[target])
    tags[target]:view_only()
end

function shifty.send_next() send(1) end
function shifty.send_prev() send(-1) end

--pos2idx: translate shifty position to tag index
--@param pos: position (an integer)
--@param scr: screen number
function pos2idx(pos, scr)
    local v = 1
    if pos and scr then
        local tags = scr.tags
        for i = #tags , 1, -1 do
            local t = tags[i]
            if awful.tag.getproperty(t, "position") and
                awful.tag.getproperty(t, "position") <= pos then
                v = i + 1
                break
            end
        end
    end
    return v
end

--select : helper function chooses the first non-nil argument
--@param args - table of arguments
local function select(args)
    for i, a in pairs(args) do
        if a ~= nil then
            return a
        end
    end
end

--tagtoscr : move an entire tag to another screen
--
--@param scr : the screen to move tag to
--@param t : the tag to be moved [scr.selected_tag]
--@return the tag
function shifty.tagtoscr(scr, t)
    -- skrewz@20170202: shouldn't be relevant when called with screen objects
    -- break if called with an invalid screen number
    --if not scr or scr < 1 or scr > capi.screen.count() then return end
    -- tag to move
    local otag = t or scr.selected_tag

    otag.screen = scr
    -- set screen and then reset tag to order properly
    if #otag:clients() > 0 then
        for _ , c in ipairs(otag:clients()) do
            if not c.sticky then
                c.screen = scr
                c:tags({otag})
            else
                awful.client.toggletag(otag, c)
            end
        end
    end
    return otag
end

--set : set a tags properties
--@param t: the tag
--@param args : a table of optional (?) tag properties
--@return t - the tag object
function set(t, args)
    if not t then return end
    if not args then args = {} end

    -- set the name
    t.name = args.name or t.name

    -- attempt to load preset on initial run
    local preset = (awful.tag.getproperty(t, "initial") and
    shifty.config.tags[t.name]) or {}

    -- pick screen and get its tag table
    local scr = args.screen or
      (not t.screen and preset.screen) or
      t.screen or
      awful.screen.focused()

    local clientstomove = nil
    --skrewz@20170202: if scr is an object, this shouldn't be necessary:
    --if scr > capi.screen.count() then scr = capi.screen.count() end
    if t.screen and scr ~= t.screen then
        shifty.tagtoscr(scr, t)
        t.screen = nil
    end
    local tags = scr.tags

    -- try to guess position from the name
    local guessed_position = nil
    if not (args.position or preset.position) and shifty.config.guess_position then
        local num = t.name:find('^[1-9]')
        if num then guessed_position = tonumber(t.name:sub(1, 1)) end
    end

    -- allow preset.layout to be a table to provide a different layout per
    -- screen for a given tag
    local preset_layout = preset.layout
    if preset_layout and preset_layout[scr] then
        preset_layout = preset.layout[scr]
    end

    -- select from args, preset, getproperty,
    -- config.defaults.configs or defaults
    local props = {
        layout = select{args.layout, preset_layout,
                        awful.tag.getproperty(t, "layout"),
                        shifty.config.defaults.layout, awful.layout.suit.tile},
        mwfact = select{args.mwfact, preset.mwfact,
                        awful.tag.getproperty(t, "mwfact"),
                        shifty.config.defaults.mwfact, 0.55},
        nmaster = select{args.nmaster, preset.nmaster,
                        awful.tag.getproperty(t, "nmaster"),
                        shifty.config.defaults.nmaster, 1},
        ncol = select{args.ncol, preset.ncol,
                        awful.tag.getproperty(t, "ncol"),
                        shifty.config.defaults.ncol, 1},
        matched = select{args.matched, awful.tag.getproperty(t, "matched")},
        exclusive = select{args.exclusive, preset.exclusive,
                        awful.tag.getproperty(t, "exclusive"),
                        shifty.config.defaults.exclusive},
        persist = select{args.persist, preset.persist,
                        awful.tag.getproperty(t, "persist"),
                        shifty.config.defaults.persist},
        nopopup = select{args.nopopup, preset.nopopup,
                        awful.tag.getproperty(t, "nopopup"),
                        shifty.config.defaults.nopopup},
        leave_kills = select{args.leave_kills, preset.leave_kills,
                        awful.tag.getproperty(t, "leave_kills"),
                        shifty.config.defaults.leave_kills},
        max_clients = select{args.max_clients, preset.max_clients,
                        awful.tag.getproperty(t, "max_clients"),
                        shifty.config.defaults.max_clients},
        position = select{args.position, preset.position, guessed_position,
                        awful.tag.getproperty(t, "position")},
        icon = select{args.icon and args.icon,
                        preset.icon and preset.icon,
                        awful.tag.getproperty(t, "icon"),
                    shifty.config.defaults.icon and shifty.config.defaults.icon},
        icon_only = select{args.icon_only, preset.icon_only,
                        awful.tag.getproperty(t, "icon_only"),
                        shifty.config.defaults.icon_only},
        sweep_delay = select{args.sweep_delay, preset.sweep_delay,
                        awful.tag.getproperty(t, "sweep_delay"),
                        shifty.config.defaults.sweep_delay},
        overload_keys = select{args.overload_keys, preset.overload_keys,
                        awful.tag.getproperty(t, "overload_keys"),
                        shifty.config.defaults.overload_keys},
    }

    -- get layout by name if given as string
    if type(props.layout) == "string" then
        props.layout = getlayout(props.layout)
    end

    -- set keys
    if args.keys or preset.keys then
        local keys = awful.util.table.join(shifty.config.globalkeys,
        args.keys or preset.keys)
        if props.overload_keys then
            props.keys = keys
        else
            props.keys = squash_keys(keys)
        end
    end

    -- calculate desired taglist index
    local index = args.index or preset.index or shifty.config.defaults.index
    local rel_index = args.rel_index or
    preset.rel_index or
    shifty.config.defaults.rel_index
    local sel = scr.selected_tag
    --TODO: what happens with rel_idx if no tags selected
    local sel_idx = (sel and tag2index(scr, sel)) or 0
    local t_idx = tag2index(scr, t)
    local limit = (not t_idx and #tags + 1) or #tags
    local idx = nil

    if rel_index then
        idx = awful.util.cycle(limit, (t_idx or sel_idx) + rel_index)
    elseif index then
        idx = awful.util.cycle(limit, index)
    elseif props.position then
        idx = pos2idx(props.position, scr)
        if t_idx and t_idx < idx then idx = idx - 1 end
    -- skrewz@20170208: commented, usefulness not clear:
    --elseif shifty.config.remember_index and index_cache[scr][t.name] then
    --    idx = math.min(index_cache[scr][t.name], #tags+1)
    elseif not t_idx then
        idx = #tags + 1
    end

    -- if we have a new index, remove from old index and insert
    if idx then
        if t_idx then table.remove(tags, t_idx) end
        table.insert(tags, idx, t)
	-- skrewz@20170208: commented, usefulness not clear:
        --index_cache[scr][t.name] = idx
    end

    -- set tag properties and push the new tag table
    for i, tmp_tag in ipairs(tags) do
        tmp_tag.screen=scr
        awful.tag.setproperty(tmp_tag, "index", i)
    end
    for prop, val in pairs(props) do awful.tag.setproperty(t, prop, val) end

    -- execute run/spawn
    if awful.tag.getproperty(t, "initial") then
        local spawn = args.spawn or preset.spawn or shifty.config.defaults.spawn
        local run = args.run or preset.run or shifty.config.defaults.run
        if spawn and args.matched ~= true then
            awful.util.spawn_with_shell(spawn, scr)
        end
        if run then run(t) end
        awful.tag.setproperty(t, "initial", nil)
    end


    return t
end

function shifty.shift_next()
  set(awful.tag.selected(), {rel_index = 1})
  shifty.schedule_tag_statesave()
end
function shifty.shift_prev()
  set(awful.tag.selected(), {rel_index = -1})
  shifty.schedule_tag_statesave()
end

function shifty.view_tag_by_substr(name)
    if name:len() > 0 then
        local all_found = substr_name2tags(name)
        if all_found then
            local found = all_found[1]
            found:view_only()
        end
    end
end

function shifty.view_client_by_substr(name)
    if name:len() > 0 then
        local all_found = substr_name2clients(name)
        if all_found then
            local found = all_found[1]
            found:jump_to()
        end
    end
end

function surround_infix_insensitive(input,pre,search,post)
  m_start, m_end = string.find(input:lower(),search:lower())
  if m_start then
    return input:sub(0,m_start-1)
      ..pre
      ..input:sub(m_start,m_end)
      ..post
      ..input:sub(m_end+1,string.len(input))
  else
    return input
  end
end

function shifty.retrieve_tags_matching(searchstring,formatted,relative_to_screen)
  local tags_matched = nil
  local string_matches = {}
  if nil == formatted then formatted = true end
  assert(nil == relative_to_screen) -- unsupported as of yet

  if searchstring and '' ~= searchstring then
    tags_matched = substr_name2tags(searchstring)
    if tags_matched then
      for i, t in ipairs(tags_matched) do
        if 1 == i then
          colour = 'lightgreen'
        else
          colour = 'red'
        end
        if formatted then
        string_matches[t.name] = surround_infix_insensitive(
          t.name,
          '<span foreground="'..colour..'">',
          searchstring,
          '</span>')
        else
          string_matches[t.name] = t.name
        end
      end
    end
  end
  return string_matches
end

function shifty.retrieve_clients_matching(searchstring,formatted,relative_to_screen)
  local clients_matched = nil
  local string_matches = {}
  if nil == formatted then formatted = true end
  assert(nil == relative_to_screen) -- unsupported as of yet

  if searchstring and '' ~= searchstring then
    clients_matched = substr_name2clients(searchstring)
  end

  if clients_matched then
    for i, c in ipairs(clients_matched) do
      if 1 == i then
        colour = 'lightgreen'
      else
        colour = 'red'
      end
      if formatted then
        string_matches[c.name] = surround_infix_insensitive(
          c.name,
          '<span foreground="'..colour..'">',
          searchstring,
          '</span>')
      else
        string_matches[c.name] = c.name
      end
    end
  end
  return string_matches
end
--]]

function shifty.update_search_results(layout, search_fn, searchstring)
  local matches = nil
  layout:reset()

  if searchstring and '' ~= searchstring then
    matches = search_fn(searchstring,true)
  end

  if not matches then
    search_promptwibox.border_color = '#ff7777'
    search_promptwibox.bg           = '#ff7777'
    layout:add(
      wibox.widget.textbox(
        '<span background="red" font_size="larger">(no matches)</span>',
        false
      )
    )
  else
    local count = 0
    for _, _ in pairs(matches) do count = count + 1 end

    if 1 == count then
      search_promptwibox.border_color = '#77aa77'
      search_promptwibox.bg           = '#77aa77'
    else
      search_promptwibox.border_color = '#777777'
      search_promptwibox.bg           = '#777777'
    end
    for res, formatted in pairs(matches) do
      layout:add(
        wibox.widget.textbox(
          formatted,
          false
        )
      )
    end
  end
end

search_promptbox = wibox.widget.textbox()
search_completion = wibox.layout.fixed.vertical()

search_promptwibox = awful.popup {
    widget = {
      search_promptbox,
      search_completion,
      layout = wibox.layout.fixed.vertical,
    },
    border_width   = 10,
    minimum_height = 100,
    minimum_width  = 600,
    ontop          = true,
    placement      = awful.placement.centered,
    visible        = false,
    shape          = gears.shape.rounded_rect
}

function shifty.search_client_interactive ()
    search_promptwibox.visible = true
    shifty.update_search_results(search_completion, nil, nil)
    awful.prompt.run({
        fg_cursor = '#ffffff', ul_cursor = "single",
        prompt = 'client search: ',
        text = "",
        exe_callback = shifty.view_client_by_substr,
        done_callback = function () search_promptwibox.visible = false end,
        changed_callback = function(now)
          shifty.update_search_results(
            search_completion,
            shifty.retrieve_clients_matching,
            now)
        end,
	textbox = search_promptbox
        }
    )
end
function shifty.search_tag_interactive ()
    search_promptwibox.visible = true
    shifty.update_search_results(search_completion, nil, nil)
    awful.prompt.run({
        fg_cursor = '#ffffff', ul_cursor = "single",
        prompt = 'tag search: ',
        text = "",
        exe_callback = shifty.view_tag_by_substr,
        done_callback = function () search_promptwibox.visible = false end,
        changed_callback = function(now)
          shifty.update_search_results(
            search_completion,
            shifty.retrieve_tags_matching,
            now)
        end,
	textbox = search_promptbox
        }
    )
end

--add : adds a tag
--@param args: table of optional arguments
function shifty.add(args)
    if not args then args = {} end
    local name = args.name or " "

    -- initialize a new tag object and its data structure
    local t = awful.tag.add(name, { initial = true })


    -- apply tag settings
    set(t, args)

    -- unless forbidden or if first tag on the screen, show the tag
    if not (awful.tag.getproperty(t, "nopopup") or args.noswitch) or
        #t.screen.tags == 1 then
        t:view_only()
    end

    -- get the name or rename
    if args.name then
        t.name = args.name
    else
        -- FIXME: hack to delay rename for un-named tags for
        -- tackling taglist refresh which disabled prompt
        -- from being rendered until input
        awful.tag.setproperty(t, "initial", true)
        local f
        local tmr
        if args.position then
            f = function()  shifty.rename(t, args.rename, true); tmr:stop()  end
        else
            f = function()  shifty.rename(t); tmr:stop() end
        end
        tmr = gears.timer({timeout = 0.01})
        tmr:connect_signal("timeout", f)
        tmr:start()
    end

    shifty.schedule_tag_statesave()
    return t
end

--del : delete a tag
--@param tag : the tag to be deleted [current tag]
function shifty.del(tag)
    local scr = (tag and tag.screen) or awful.screen.focused() or 1
    local tags = scr.tags
    local sel = scr.selected_tag
    local t = tag or sel
    local idx = tag2index(scr, t)

    -- return if tag not empty (except sticky)
    local clients = t:clients()
    local sticky = 0
    for i, c in ipairs(clients) do
        if c.sticky then sticky = sticky + 1 end
    end
    if #clients > sticky then return end

    -- store index for later
    -- skrewz@20170208: commented, usefulness not clear:
    --index_cache[scr][t.name] = idx

    -- remove tag
    t:delete()

    -- if the current tag is being deleted, restore from history
    if t == sel and #tags > 1 then
        awful.tag.history.restore(scr, 1)
        -- this is supposed to cycle if history is invalid?
        -- e.g. if many tags are deleted in a row
        if not scr.selected_tag then
            tags[awful.util.cycle(#tags, idx - 1)]:view_only()
        end
    end

    -- FIXME: what is this for??
    if capi.client.focus then capi.client.focus:raise() end
    shifty.schedule_tag_statesave()
end

--is_client_tagged : replicate behavior in tag.c - returns true if the
--given client is tagged with the given tag
function is_client_tagged(tag, client)
    for i, c in ipairs(tag:clients()) do
        if c == client then
            return true
        end
    end
    return false
end


--match : handles app->tag matching, a replacement for the manage hook in
--            rc.lua
--@param c : client to be matched
function match(c, startup)
    local nopopup, intrusive, nofocus, run, slave
    local wfact, struts, geom, float
    local target_tag_names, target_tags = {}, {}
    local typ = c.type
    local cls = c.class
    local inst = c.instance
    local role = c.role
    local name = c.name
    local keys = shifty.config.clientkeys or c:keys() or {}
    local target_screen = awful.screen.focused()

    c.border_color = beautiful.border_normal
    c.border_width = beautiful.border_width

    -- try matching client to config.apps
    for i, a in ipairs(shifty.config.apps) do
        if a.match then
            local matched = false
            -- match only class
            if not matched and cls and a.match.class then
                for k, w in ipairs(a.match.class) do
                    matched = cls:find(w)
                    if matched then
                        break
                    end
                end
            end
            -- match only instance
            if not matched and inst and a.match.instance then
                for k, w in ipairs(a.match.instance) do
                    matched = inst:find(w)
                    if matched then
                        break
                    end
                end
            end
            -- match only name
            if not matched and name and a.match.name then
                for k, w in ipairs(a.match.name) do
                    matched = name:find(w)
                    if matched then
                        break
                    end
                end
            end
            -- match only role
            if not matched and role and a.match.role then
                for k, w in ipairs(a.match.role) do
                    matched = role:find(w)
                    if matched then
                        break
                    end
                end
            end
            -- match only type
            if not matched and typ and a.match.type then
                for k, w in ipairs(a.match.type) do
                    matched = typ:find(w)
                    if matched then
                        break
                    end
                end
            end
            -- check everything else against all attributes
            if not matched then
                for k, w in ipairs(a.match) do
                    matched = (cls and cls:find(w)) or
                            (inst and inst:find(w)) or
                            (name and name:find(w)) or
                            (role and role:find(w)) or
                            (typ and typ:find(w))
                    if matched then
                        break
                    end
                end
            end
            -- set attributes
            if matched then
                if a.screen then target_screen = a.screen end
                if a.tag then
                    if type(a.tag) == "string" then
                        target_tag_names = {a.tag}
                    else
                        target_tag_names = a.tag
                    end
                end
                if a.startup and startup then
                    a = awful.util.table.join(a, a.startup)
                end
                if a.geometry ~=nil then
                    geom = {x = a.geometry[1],
                    y = a.geometry[2],
                    width = a.geometry[3],
                    height = a.geometry[4]}
                end
                if a.float ~= nil then float = a.float end
                if a.slave ~=nil then slave = a.slave end
                if a.border_width ~= nil then
                    c.border_width = a.border_width
                end
                if a.nopopup ~=nil then nopopup = a.nopopup end
                if a.intrusive ~=nil then
                    intrusive = a.intrusive
                end
                if a.fullscreen ~=nil then
                    c.fullscreen = a.fullscreen
                end
                if a.honorsizehints ~=nil then
                    c.size_hints_honor = a.honorsizehints
                end
                if a.kill ~=nil then c:kill(); return end
                if a.ontop ~= nil then c.ontop = a.ontop end
                if a.above ~= nil then c.above = a.above end
                if a.below ~= nil then c.below = a.below end
                if a.buttons ~= nil then
                    c:buttons(a.buttons)
                end
                if a.nofocus ~= nil then nofocus = a.nofocus end
                if a.keys ~= nil then
                    keys = awful.util.table.join(keys, a.keys)
                end
                if a.hidden ~= nil then c.hidden = a.hidden end
                if a.minimized ~= nil then
                    c.minimized = a.minimized
                end
                if a.dockable ~= nil then
                    awful.client.dockable.set(c, a.dockable)
                end
                if a.urgent ~= nil then
                    c.urgent = a.urgent
                end
                if a.opacity ~= nil then
                    c.opacity = a.opacity
                end
                if a.run ~= nil then run = a.run end
                if a.sticky ~= nil then c.sticky = a.sticky end
                if a.wfact ~= nil then wfact = a.wfact end
                if a.struts then struts = a.struts end
                if a.skip_taskbar ~= nil then
                    c.skip_taskbar = a.skip_taskbar
                end
                if a.props then
                    for kk, vv in pairs(a.props) do
                        awful.client.property.set(c, kk, vv)
                    end
                end
            end
        end
    end

    -- set key bindings
    c:keys(keys)

    -- Add titlebars to all clients when the float, remove when they are
    -- tiled.
    if shifty.config.float_bars then
        shifty.create_titlebar(c)

        c:connect_signal("property::floating", function(c)
            if awful.client.floating.get(c) then
                awful.titlebar(c)
            else
                awful.titlebar(c, { size = 0 })
            end
            awful.placement.no_offscreen(c)
        end)
    end

    -- set properties of floating clients
    if float ~= nil then
        awful.client.floating.set(c, float)
        awful.placement.no_offscreen(c)
    end

    local sel = target_screen.selected_tags
    if not target_tag_names or #target_tag_names == 0 then
        -- if not matched to some names try putting
        -- client in c.transient_for or current tags
        if c.transient_for then
            target_tags = c.transient_for:tags()
        elseif #sel > 0 then
            for i, t in ipairs(sel) do
                local mc = awful.tag.getproperty(t, "max_clients")
                if intrusive or
                    not (awful.tag.getproperty(t, "exclusive") or
                                    (mc and mc >= #t:clients())) then
                    table.insert(target_tags, t)
                end
            end
        end
    end

    if (not target_tag_names or #target_tag_names == 0) and
        (not target_tags or #target_tags == 0) then
        -- if we still don't know any target names/tags guess
        -- name from class or use default
        if shifty.config.guess_name and cls then
            target_tag_names = {cls:lower()}
        else
            target_tag_names = {shifty.config.default_name}
        end
    end

    if #target_tag_names > 0 and #target_tags == 0 then
        -- translate target names to tag objects, creating
        -- missing ones
        for i, tn in ipairs(target_tag_names) do
            local res = {}
            for j, t in ipairs(name2tags(tn, target_screen) or
                name2tags(tn) or {}) do
                local mc = awful.tag.getproperty(t, "max_clients")
                local tagged = is_client_tagged(t, c)
                if intrusive or
                    not (mc and (((#t:clients() >= mc) and not
                    tagged) or
                    (#t:clients() > mc))) or
                    intrusive then
                    if t.screen == awful.screen.focused() then
                        table.insert(res, t)
                    end
                end
            end
            if #res == 0 then
                table.insert(target_tags,
                shifty.add({name = tn,
                noswitch = true,
                matched = true}))
            else
                target_tags = awful.util.table.join(target_tags, res)
            end
        end
    end

    -- set client's screen/tag if needed
    target_screen = target_tags[1].screen or target_screen
    if c.screen ~= target_screen then c.screen = target_screen end
    if slave then awful.client.setslave(c) end
    c:tags(target_tags)

    if wfact then awful.client.setwfact(wfact, c) end
    if geom then c:geometry(geom) end
    if struts then c:struts(struts) end

    local showtags = {}
    local u = nil
    if #target_tags > 0 and not startup then
        -- switch or highlight
        for i, t in ipairs(target_tags) do
            if not (nopopup or awful.tag.getproperty(t, "nopopup")) then
                table.insert(showtags, t)
            elseif not startup then
                c.urgent = true
            end
        end
        if #showtags > 0 then
            local ident = false
            -- iterate selected tags and and see if any targets
            -- currently selected
            for kk, vv in pairs(showtags) do
                for _, tag in pairs(sel) do
                    if tag == vv then
                        ident = true
                    end
                end
            end
            if not ident then
                awful.tag.viewmore(showtags, c.screen)
            end
        end
    end

    if not (nofocus or c.hidden or c.minimized) then
        --focus and raise accordingly or lower if supressed
        if (target and target ~= sel) and
           (awful.tag.getproperty(target, "nopopup") or nopopup)  then
            awful.client.focus.history.add(c)
        else
            capi.client.focus = c
        end
        c:raise()
    else
        c:lower()
    end

    if shifty.config.sloppy then
        -- Enable sloppy focus
        c:connect_signal("mouse::enter", function(c)
            if awful.client.focus.filter(c) and
                awful.layout.get(c.screen) ~= awful.layout.suit.magnifier then
                capi.client.focus = c
            end
        end)
    end

    -- execute run function if specified
    if run then run(c, target) end

end

--sweep : hook function that marks tags as used, visited,
--deserted also handles deleting used and empty tags
function sweep()
  for s in screen do
        for i, t in ipairs(s.tags) do
            local clients = t:clients()
            local sticky = 0
            for i, c in ipairs(clients) do
                if c.sticky then sticky = sticky + 1 end
            end
            if #clients == sticky then
                if awful.tag.getproperty(t, "used") and
                    not awful.tag.getproperty(t, "persist") then
                    if awful.tag.getproperty(t, "deserted") or
                        not awful.tag.getproperty(t, "leave_kills") then
                        local delay = awful.tag.getproperty(t, "sweep_delay")
                        if delay then
                            local tmr
                            local f = function()
                                        shifty.del(t); tmr:stop()
                                    end
                            tmr = gears.timer({timeout = delay})
                            tmr:connect_signal("timeout", f)
                            tmr:start()
                        else
                            if shifty.config.delete_deserted then
                                shifty.del(t)
                            end
                        end
                    else
                        if awful.tag.getproperty(t, "visited") and
                            not t.selected then
                            awful.tag.setproperty(t, "deserted", true)
                        end
                    end
                end
            else
                awful.tag.setproperty(t, "used", true)
            end
            if t.selected then
                awful.tag.setproperty(t, "visited", true)
            end
        end
    end
end

--getpos : returns a tag to match position
-- @param pos : the index to find
-- @return v : the tag (found or created) at position == 'pos'
function shifty.getpos(pos, scr_arg)
    local v = nil
    local existing = {}
    local selected = nil
    local scr = scr_arg or awful.screen.focused() or 1

    -- search for existing tag assigned to pos
    for i = 1, capi.screen.count() do
        for j, t in ipairs(i.tags) do
            if awful.tag.getproperty(t, "position") == pos then
                table.insert(existing, t)
                if t.selected and i == scr then
                    selected = #existing
                end
            end
        end
    end

    if #existing > 0 then
        -- if there is no selected tag on current screen, look for the first one
        if not selected then
            for _, tag in pairs(existing) do
                if tag.screen == scr then return tag end
            end

            -- no tag found, loop through the other tags
            selected = #existing
        end

        -- look for the next unselected tag
        i = selected
        repeat
            i = awful.util.cycle(#existing, i + 1)
            tag = existing[i]

            if (scr_arg == nil or tag.screen == scr_arg) and not tag.selected then return tag end
        until i == selected

        -- if the screen is not specified or
        -- if a selected tag exists on the specified screen
        -- return the selected tag
        if scr_arg == nil or existing[selected].screen == scr then return existing[selected] end

        -- if scr_arg ~= nil and no tag exists on this screen, continue
    end

    local screens = {}
    for s = 1, capi.screen.count() do table.insert(screens, s) end

    -- search for preconf with 'pos' on current screen and create it
    for i, j in pairs(shifty.config.tags) do
        local tag_scr = j.screen or screens
        if type(tag_scr) ~= 'table' then tag_scr = {tag_scr} end

        if j.position == pos and awful.util.table.hasitem(tag_scr, scr) then
            return shifty.add({name = i,
                    position = pos,
                    noswitch = not switch})
        end
    end

    -- not existing, not preconfigured
    return shifty.add({position = pos,
            rename = pos .. ':',
            no_selectall = true,
            noswitch = not switch})
end

--init : search config.tags for initial set of
--tags to open
function shifty.init()
    local numscr = capi.screen.count()

    local screens = {}
    for s = 1, capi.screen.count() do table.insert(screens, s) end

    for i, j in pairs(shifty.config.tags) do
        local scr = j.screen or screens
        if type(scr) ~= 'table' then
            scr = {scr}
        end
        for _, s in pairs(scr) do
            if j.init and (s <= numscr) then
                shifty.add({name = i,
                    persist = true,
                    screen = s,
                    layout = j.layout,
                    mwfact = j.mwfact})
            end
        end
    end
end

-- Create a titlebar for the given client
-- By default, make it invisible (size = 0)

function shifty.create_titlebar(c)
    -- Widgets that are aligned to the left
    local left_layout = wibox.layout.fixed.horizontal()
    left_layout:add(awful.titlebar.widget.iconwidget(c))

    -- Widgets that are aligned to the right
    local right_layout = wibox.layout.fixed.horizontal()
    right_layout:add(awful.titlebar.widget.floatingbutton(c))
    right_layout:add(awful.titlebar.widget.maximizedbutton(c))
    right_layout:add(awful.titlebar.widget.stickybutton(c))
    right_layout:add(awful.titlebar.widget.ontopbutton(c))
    right_layout:add(awful.titlebar.widget.closebutton(c))

    -- The title goes in the middle
    local title = awful.titlebar.widget.titlewidget(c)
    title:buttons(awful.util.table.join(
            awful.button({ }, 1, function()
                client.focus = c
                c:raise()
                awful.mouse.client.move(c)
            end),
            awful.button({ }, 3, function()
                client.focus = c
                c:raise()
                awful.mouse.client.resize(c)
            end)
            ))

    -- Now bring it all together
    local layout = wibox.layout.align.horizontal()
    layout:set_left(left_layout)
    layout:set_right(right_layout)
    layout:set_middle(title)

    awful.titlebar(c, { size = 0 }):set_widget(layout)
end

--count : utility function returns the index of a table element
--FIXME: this is currently used only in remove_dup, so is it really
--necessary?
function count(table, element)
    local v = 0
    for i, e in pairs(table) do
        if element == e then v = v + 1 end
    end
    return v
end

--remove_dup : used by shifty.completion when more than one
--tag at a position exists
function remove_dup(table)
    local v = {}
    for i, entry in ipairs(table) do
        if count(v, entry) == 0 then v[#v+ 1] = entry end
    end
    return v
end

--completion : prompt completion
--
function completion(cmd, cur_pos, ncomp, sources, matchers)

    -- get sources and matches tables
    sources = sources or shifty.config.prompt_sources
    matchers = matchers or shifty.config.prompt_matchers

    local get_source = {
        -- gather names from config.tags
        config_tags = function()
            local ret = {}
            for n, p in pairs(shifty.config.tags) do
                table.insert(ret, n)
            end
            return ret
        end,
        -- gather names from config.apps
        config_apps = function()
            local ret = {}
            for i, p in pairs(shifty.config.apps) do
                if p.tag then
                    if type(p.tag) == "string" then
                        table.insert(ret, p.tag)
                    else
                        ret = awful.util.table.join(ret, p.tag)
                    end
                end
            end
            return ret
        end,
        -- gather names from existing tags, starting with the
        -- current screen
        existing = function()
            local ret = {}
            for s in screen do
            --for i = 1, capi.screen.count() do
            --    local s = awful.util.cycle(capi.screen.count(),
            --                                capi.mouse.screen + i - 1)
                local tags = s.tags
                for j, t in pairs(tags) do
                    table.insert(ret, t.name)
                end
            end
            return ret
        end,
        -- gather names from history
        history = function()
            local ret = {}
            local f = io.open(awful.util.getdir("cache") ..
                                    "/history_tags")
            for name in f:lines() do table.insert(ret, name) end
            f:close()
            return ret
        end,
    }

    -- if empty, match all
    if #cmd == 0 or cmd == " " then cmd = "" end

    -- match all up to the cursor if moved or no matchphrase
    if matchp == "" or
        cmd:sub(cur_pos, cur_pos+#matchp) ~= matchp then
        matchp = cmd:sub(1, cur_pos)
    end

    -- find matching commands
    local matches = {}
    for i, src in ipairs(sources) do
        local source = get_source[src]()
        for j, matcher in ipairs(matchers) do
            for k, name in ipairs(source) do
                if name:find(matcher .. matchp) then
                    table.insert(matches, name)
                end
            end
        end
    end

    -- no matches
    if #matches == 0 then return cmd, cur_pos end

    -- remove duplicates
    matches = remove_dup(matches)

    -- cycle
    while ncomp > #matches do ncomp = ncomp - #matches end

    -- put cursor at the end of the matched phrase
    if #matches == 1 then
        cur_pos = #matches[ncomp] + 1
    else
        cur_pos = matches[ncomp]:find(matchp) + #matchp
    end

    -- return match and position
    return matches[ncomp], cur_pos
end

-- tagkeys : hook function that sets keybindings per tag
function tagkeys(s)
    local sel = s.selected_tag
    local keys = awful.tag.getproperty(sel, "keys") or
                    shifty.config.globalkeys
    if keys and sel and sel.selected then capi.root.keys(keys) end
end

-- squash_keys: helper function which removes duplicate
-- keybindings by picking only the last one to be listed in keys
-- table arg
function squash_keys(keys)
    local squashed = {}
    local ret = {}
    for i, k in ipairs(keys) do
        squashed[table.concat(k.modifiers) .. k.key] = k
    end
    for i, k in pairs(squashed) do
        table.insert(ret, k)
    end
    return ret
end

-- getlayout: returns a layout by name
function getlayout(name)
    for _, layout in ipairs(shifty.config.layouts) do
        if awful.layout.getname(layout) == name then
            return layout
        end
    end
end
-- save tags state:
local save_tags_tmr
function shifty.save_tag_names()
  --local naughty   = require("naughty")
  --naughty.notify({ title = "Timer fired", text = "Ran save_tag_names", timeout = 1 })
  persistence_file = awful.util.getdir("cache") .. "/tags_state_persistence"
  local f = assert(io.open(persistence_file, "w"))
  for s in screen do
    for i, t in ipairs(s.tags) do
      -- skrewz@20170202: disabling f.write temporarily
      f:write(s.index .. ":".. t.name .. "\n")
    end
  end
  f:close()
end
-- helper function to merely background the task
function shifty.schedule_tag_statesave()
  if save_tags_tmr then
    save_tags_tmr:stop()
    save_tags_tmr = nil
  end
  save_tags_tmr = gears.timer({timeout = 2.00})
  save_tags_tmr:connect_signal("timeout", function()
    save_tags_tmr:stop()
    shifty.save_tag_names();
    save_tags_tmr = nil
  end)
  save_tags_tmr:start()
end


-- restore tags state
--[[
skrewz@20170208: really, this is best-effort: the screen objects are not
supposed to be used by index anymore (and there's good reason for that!) but
this creates a bridge from Awesome 3.5 to 4.0 here.

A more viable approach might be to identify screens by their s.geometry
coordinates---and hope that these don't change between restarts?
--]]
function shifty.restore_saved_tag_names()
  for s in screen do
    for i, t in ipairs(s.tags) do
      shifty.del(t)
    end
  end
  persistence_file = awful.util.getdir("cache") .. "/tags_state_persistence"
  local ret = {}
  local f = io.open(persistence_file, "r")
  if f then
    for line in f:lines() do
      local screen_index, _   = tonumber(string.gsub(line,"(%d+):(.+)","%1"),10)
      local n, _   = string.gsub(line,"(%d+):(.+)","%2")
      shifty.add({
        name = n,
        persist = true,
        screen = screen[screen_index],
        -- TODO:
        --layout = j.layout,
        --mwfact = j.mwfact})
      })
    end
    f:close()
  end
  return ret
end

-- add signals before using them
-- Note: these signals are emitted when tag properties
-- are accessed through awful.tag.setproperty
--[[
capi.tag.add_signal("property::initial")
capi.tag.add_signal("property::used")
capi.tag.add_signal("property::visited")
capi.tag.add_signal("property::deserted")
capi.tag.add_signal("property::matched")
capi.tag.add_signal("property::selected")
capi.tag.add_signal("property::position")
capi.tag.add_signal("property::exclusive")
capi.tag.add_signal("property::persist")
capi.tag.add_signal("property::index")
capi.tag.add_signal("property::nopopup")
capi.tag.add_signal("property::leave_kills")
capi.tag.add_signal("property::max_clients")
capi.tag.add_signal("property::icon_only")
capi.tag.add_signal("property::sweep_delay")
capi.tag.add_signal("property::overload_keys")
--]]

-- replace awful's default hook
capi.client.connect_signal("manage", match)
capi.client.connect_signal("unmanage", sweep)
capi.client.disconnect_signal("manage", awful.tag.withcurrent)

for s = 1, capi.screen.count() do
    awful.tag.attached_connect_signal(s, "property::selected", sweep)
    awful.tag.attached_connect_signal(s, "tagged", sweep)
    capi.screen[s]:connect_signal("tag::history::update", tagkeys)
end

return shifty

