local this_package = ... and (...):match("(.-)[^%.]+$") or ""
local machi_editor = require(this_package.."editor")
local awful = require("awful")
local capi = {
    screen = screen
}

local ERROR = 2
local WARNING = 1
local INFO = 0
local DEBUG = -1

local module = {
    log_level = WARNING,
    global_default_cmd = "w66.",
    allow_shrinking_by_mouse_moving = false,
}

local function log(level, msg)
    if level > module.log_level then
        print(msg)
    end
end

local function min(a, b)
    if a < b then return a else return b end
end

local function max(a, b)
    if a < b then return b else return a end
end

local function get_screen(s)
    return s and capi.screen[s]
end

awful.mouse.resize.add_enter_callback(
    function (c)
        c.full_width_before_move = c.width + c.border_width * 2
        c.full_height_before_move = c.height + c.border_width * 2
    end, 'mouse.move')

--- find the best area for the area-like object
-- @param c       area-like object - table with properties x, y, width, and height
-- @param areas   array of area objects
-- @return the index of the best area
local function find_area(c, areas)
    local choice = 1
    local choice_value = nil
    local c_area = c.width * c.height
    for i, a in ipairs(areas) do
        if not a.inhabitable then
            local x_cap = max(0, min(c.x + c.width, a.x + a.width) - max(c.x, a.x))
            local y_cap = max(0, min(c.y + c.height, a.y + a.height) - max(c.y, a.y))
            local cap = x_cap * y_cap
            -- -- a cap b / a cup b
            -- local cup = c_area + a.width * a.height - cap
            -- if cup > 0 then
            --    local itx_ratio = cap / cup
            --    if choice_value == nil or choice_value < itx_ratio then
            --       choice_value = itx_ratio
            --       choice = i
            --    end
            -- end
            -- a cap b
            if choice_value == nil or choice_value < cap then
                choice = i
                choice_value = cap
            end
        end
    end
    return choice
end

local function distance(x1, y1, x2, y2)
    -- use d1
    return math.abs(x1 - x2) + math.abs(y1 - y2)
end

local function find_lu(c, areas, rd)
    local lu = nil
    for i, a in ipairs(areas) do
        if not a.inhabitable then
            if rd == nil or (a.x < areas[rd].x + areas[rd].width and a.y < areas[rd].y + areas[rd].height) then
                if lu == nil or distance(c.x, c.y, a.x, a.y) < distance(c.x, c.y, areas[lu].x, areas[lu].y) then
                    lu = i
                end
            end
        end
    end
    return lu
end

local function find_rd(c, areas, lu)
    local x, y
    x = c.x + c.width + (c.border_width or 0)
    y = c.y + c.height + (c.border_width or 0)
    local rd = nil
    for i, a in ipairs(areas) do
        if not a.inhabitable then
            if lu == nil or (a.x + a.width > areas[lu].x and a.y + a.height > areas[lu].y) then
                if rd == nil or distance(x, y, a.x + a.width, a.y + a.height) < distance(x, y, areas[rd].x + areas[rd].width, areas[rd].y + areas[rd].height) then
                    rd = i
                end
            end
        end
    end
    return rd
end

function module.set_geometry(c, area_lu, area_rd, useless_gap, border_width)
    -- We try to negate the gap of outer layer
    if area_lu ~= nil then
        c.x = area_lu.x - useless_gap
        c.y = area_lu.y - useless_gap
    end

    if area_rd ~= nil then
        c.width = area_rd.x + area_rd.width - c.x + useless_gap - border_width * 2
        c.height = area_rd.y + area_rd.height - c.y + useless_gap - border_width * 2
    end
end

function module.create(args_or_name, editor, default_cmd)
    local args
    if type(args_or_name) == "string" then
        args = {
            name = args_or_name
        }
    elseif type(args_or_name) == "function" then
        args = {
            name_func = args_or_name
        }
    elseif type(args_or_name) == "table" then
        args = args_or_name
    else
        return nil
    end
    args.name = args.name or function (tag)
        if tag.machi_name_cache == nil then
            tag.machi_name_cache =
                tostring(tag.screen.geometry.width) .. "x" .. tostring(tag.screen.geometry.height) .. "+" ..
                tostring(tag.screen.geometry.x) .. "+" .. tostring(tag.screen.geometry.y) .. '+' .. tag.name
        end
        return tag.machi_name_cache
    end
    args.editor = args.editor or editor or machi_editor.default_editor
    args.default_cmd = args.default_cmd or default_cmd or global_default_cmd
    args.persistent = args.persistent == nil or args.persistent

    local layout = {}
    local instances = {}

    local function get_instance_info(tag)
        return (args.name_func and args.name_func(tag) or args.name), args.persistent
    end

    local function get_instance_(tag)
        local name, persistent = get_instance_info(tag)
        if instances[name] == nil then
            instances[name] = {
                layout = layout,
                cmd = persistent and args.editor.get_last_cmd(name) or nil,
                areas_cache = {},
                tag_data = {},
                client_data = setmetatable({}, {__mode="k"}),
            }
            if instances[name].cmd == nil then
                instances[name].cmd = args.default_cmd
            end
        end
        return instances[name]
    end

    local function get_instance_data(screen, tag)
        local workarea = screen.workarea
        local instance = get_instance_(tag)
        local cmd = instance.cmd or module.global_default_cmd
        if cmd == nil then return end

        local key = tostring(workarea.width) .. "x" .. tostring(workarea.height) .. "+" .. tostring(workarea.x) .. "+" .. tostring(workarea.y)
        if instance.areas_cache[key] == nil then
            instance.areas_cache[key] = args.editor.run_cmd(cmd, screen, tag)
            if instance.areas_cache[key] == nil then
                return
            end
        end
        return instance.client_data, instance.tag_data, instance.areas_cache[key], instance, args.new_placement_cb
    end

    local function set_cmd(cmd, tag)
        local instance = get_instance_(tag)
        if instance.cmd ~= cmd then
            instance.cmd = cmd
            instance.areas_cache = {}
            instance.tag_data = {}
            instance.client_data = setmetatable({}, {__mode="k"})
        end
    end

    local function arrange(p)
        local useless_gap = p.useless_gap
        local screen = get_screen(p.screen)
        local wa = screen.workarea -- get the real workarea without the gap (instead of p.workarea)
        local cls = p.clients
        local tag = screen.selected_tag
        local cd, td, areas, instance, new_placement_cb = get_instance_data(screen, tag)

        if areas == nil then return end
        local nested_clients = {}

        local function place_client_in_area(c, area)
            if machi_editor.nested_layouts[areas[area].layout] ~= nil then
                local clients = nested_clients[area]
                if clients == nil then clients = {}; nested_clients[area] = clients end
                clients[#clients + 1] = c
            else
                module.set_geometry(p.geometries[c], areas[area], areas[area], useless_gap, 0)
            end
        end

        for i, c in ipairs(cls) do
            if c.floating or c.immobilized then
                log(DEBUG, "Ignore client " .. tostring(c))
            else
                cd[c] = cd[c] or {}

                local in_draft = cd[c].draft
                if cd[c].draft ~= nil then
                    in_draft = cd[c].draft
                elseif cd[c].lu then
                    in_draft = true
                elseif cd[c].area then
                    in_draft = false
                elseif new_placement_cb then
                    in_draft = new_placement_cb(c, instance, areas)
                else
                    in_draft = nil
                end
                local skip = false

                if in_draft ~= false then
                    if cd[c].lu ~= nil and cd[c].rd ~= nil and
                        cd[c].lu <= #areas and cd[c].rd <= #areas and
                        not areas[cd[c].lu].inhabitable and not areas[cd[c].rd].inhabitable
                    then
                        if areas[cd[c].lu].x == c.x and
                            areas[cd[c].lu].y == c.y and
                            areas[cd[c].rd].x + areas[cd[c].rd].width - c.border_width * 2 == c.x + c.width and
                            areas[cd[c].rd].y + areas[cd[c].rd].height - c.border_width * 2 == c.y + c.height
                        then
                            skip = true
                        end
                    end

                    local lu = nil
                    local rd = nil
                    if not skip then
                        log(DEBUG, "Compute areas for " .. (c.name or ("<untitled:" .. tostring(c) .. ">")))
                        lu = find_lu(c, areas)
                        if lu ~= nil then
                            c.x = areas[lu].x
                            c.y = areas[lu].y
                            rd = find_rd(c, areas, lu)
                        end
                    end

                    if lu ~= nil and rd ~= nil then
                        p.geometries[c] = {}
                        if lu == rd and cd[c].lu == nil then
                            cd[c].area = lu
                            place_client_in_area(c, lu)
                        else
                            cd[c].lu = lu
                            cd[c].rd = rd
                            cd[c].area = nil
                            module.set_geometry(p.geometries[c], areas[lu], areas[rd], useless_gap, 0)
                        end
                    end
                else
                    if cd[c].area ~= nil and
                        cd[c].area < #areas and
                        not areas[cd[c].area].inhabitable and
                        areas[cd[c].area].layout == nil and
                        areas[cd[c].area].x == c.x and
                        areas[cd[c].area].y == c.y and
                        areas[cd[c].area].width - c.border_width * 2 == c.width and
                        areas[cd[c].area].height - c.border_width * 2 == c.height
                    then
                    else
                        log(DEBUG, "Compute areas for " .. (c.name or ("<untitled:" .. tostring(c) .. ">")))
                        local area = find_area(c, areas)
                        cd[c].area, cd[c].lu, cd[c].rd = area, nil, nil
                        p.geometries[c] = {}
                        place_client_in_area(c, area)
                    end
                end
            end
        end

        for area, clients in pairs(nested_clients) do
            if td[area] == nil then
                -- TODO: Make the default more flexible.
                td[area] = {
                    column_count = 1,
                    master_count = 1,
                    master_fill_policy = "expand",
                    gap = 0,
                    master_width_factor = 0.5,
                    _private = {
                        awful_tag_properties = {
                        },
                    },
                }
            end
            local nested_params = {
                tag = td[area],
                screen = p.screen,
                clients = clients,
                padding = 0,
                geometry = {
                    x = areas[area].x,
                    y = areas[area].y,
                    width = areas[area].width,
                    height = areas[area].height,
                },
                -- Not sure how useless_gap adjustment works here. It seems to work anyway.
                workarea = {
                    x = areas[area].x - useless_gap,
                    y = areas[area].y - useless_gap,
                    width = areas[area].width + useless_gap * 2,
                    height = areas[area].height + useless_gap * 2,
                },
                useless_gap = useless_gap,
                geometries = {},
            }
            machi_editor.nested_layouts[areas[area].layout].arrange(nested_params)
            for _, c in ipairs(clients) do
                p.geometries[c] = {
                    x = nested_params.geometries[c].x,
                    y = nested_params.geometries[c].y,
                    width = nested_params.geometries[c].width,
                    height = nested_params.geometries[c].height,
                }
            end
        end
    end

    local function resize_handler (c, context, h)
        local tag = c.screen.selected_tag
        local instance = get_instance_(tag)
        local cd = instance.client_data
        local cd, td, areas, _placement_cb = get_instance_data(c.screen, tag)

        if areas == nil then return end

        if context == "mouse.move" then
            local in_draft = cd[c].draft
            if cd[c].draft ~= nil then
                in_draft = cd[c].draft
            elseif cd[c].lu then
                in_draft = true
            elseif cd[c].area then
                in_draft = false
            else
                log(ERROR, "Assuming in_draft for unhandled client "..tostring(c))
                in_draft = true
            end
            if in_draft then
                local lu = find_lu(h, areas)
                local rd = nil
                if lu ~= nil then
                    -- Use the initial width and height since it may change in undesired way.
                    local hh = {}
                    hh.x = areas[lu].x
                    hh.y = areas[lu].y
                    hh.width = c.full_width_before_move
                    hh.height = c.full_height_before_move
                    rd = find_rd(hh, areas, lu)

                    if rd ~= nil and not module.allowing_shrinking_by_mouse_moving and
                        (areas[rd].x + areas[rd].width - areas[lu].x < c.full_width_before_move or
                         areas[rd].y + areas[rd].height - areas[lu].y < c.full_height_before_move) then
                        hh.x = areas[rd].x + areas[rd].width - c.full_width_before_move
                        hh.y = areas[rd].y + areas[rd].height - c.full_height_before_move
                        lu = find_lu(hh, areas, rd)
                    end

                    if lu ~= nil and rd ~= nil then
                        cd[c].lu = lu
                        cd[c].rd = rd
                        cd[c].area = nil
                        module.set_geometry(c, areas[lu], areas[rd], 0, c.border_width)
                    end
                end
            else
                local center_x = h.x + h.width / 2
                local center_y = h.y + h.height / 2

                local choice = nil
                local choice_value = nil

                for i, a in ipairs(areas) do
                    if not a.inhabitable then
                        local ac_x = a.x + a.width / 2
                        local ac_y = a.y + a.height / 2
                        local dis = (ac_x - center_x) * (ac_x - center_x) + (ac_y - center_y) * (ac_y - center_y)
                        if choice_value == nil or choice_value > dis then
                            choice = i
                            choice_value = dis
                        end
                    end
                end

                if choice and cd[c].area ~= choice then
                    cd[c].lu = nil
                    cd[c].rd = nil
                    cd[c].area = choice
                    module.set_geometry(c, areas[choice], areas[choice], 0, c.border_width)
                end
            end
        elseif cd[c].draft ~= false then
            local lu = find_lu(h, areas)
            local rd = nil
            if lu ~= nil then
                local hh = {}
                hh.x = h.x
                hh.y = h.y
                hh.width = h.width
                hh.height = h.height
                hh.border_width = c.border_width
                rd = find_rd(hh, areas, lu)
            end

            if lu ~= nil and rd ~= nil then
                if lu == rd and cd[c].draft ~= true then
                    cd[c].lu = nil
                    cd[c].rd = nil
                    cd[c].area = lu
                    awful.layout.arrange(c.screen)
                else
                    cd[c].lu = lu
                    cd[c].rd = rd
                    cd[c].area = nil
                    module.set_geometry(c, areas[lu], areas[rd], 0, c.border_width)
                end
            end
        end
    end

    layout.name = args.icon_name or "machi"
    layout.editor = args.editor
    layout.arrange = arrange
    layout.resize_handler = resize_handler
    layout.machi_get_instance_info = get_instance_info
    layout.machi_get_instance_data = get_instance_data
    layout.machi_set_cmd = set_cmd
    return layout
end

return module
