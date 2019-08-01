local machi = {
   layout = require((...):match("(.-)[^%.]+$") .. "layout"),
}

local api = {
   client     = client,
   beautiful  = require("beautiful"),
   wibox      = require("wibox"),
   awful      = require("awful"),
   screen     = require("awful.screen"),
   layout     = require("awful.layout"),
   naughty    = require("naughty"),
   gears      = require("gears"),
   lgi        = require("lgi"),
   dpi        = require("beautiful.xresources").apply_dpi,
}

local function min(a, b)
   if a < b then return a else return b end
end

local function max(a, b)
   if a < b then return b else return a end
end

local function with_alpha(col, alpha)
   local r, g, b
   _, r, g, b, _ = col:get_rgba()
   return api.lgi.cairo.SolidPattern.create_rgba(r, g, b, alpha)
end


local function start(c)
   local tablist_font_desc = api.beautiful.get_merged_font(
      api.beautiful.mono_font or api.beautiful.font, api.dpi(10))
   local font_color = with_alpha(api.gears.color(api.beautiful.fg_normal), 1)
   local font_color_hl = with_alpha(api.gears.color(api.beautiful.fg_focus), 1)
   local label_size = api.dpi(30)
   local border_color = with_alpha(api.gears.color(api.beautiful.border_focus), 0.75)
   local fill_color = with_alpha(api.gears.color(api.beautiful.bg_normal), 0.5)
   local fill_color_hl = with_alpha(api.gears.color(api.beautiful.bg_focus), 1)
   -- for comparing floats
   local threshold = 0.1
   local traverse_radius = api.dpi(5)

   local screen = c.screen
   local start_x = screen.workarea.x
   local start_y = screen.workarea.y

   local layout = api.layout.get(screen)
   if c.floating or layout.machi_get_regions == nil then return end

   local regions, draft_mode = layout.machi_get_regions(c.screen.workarea, c.screen.selected_tag)

   local infobox = api.wibox({
         screen = screen,
         x = screen.workarea.x,
         y = screen.workarea.y,
         width = screen.workarea.width,
         height = screen.workarea.height,
         bg = "#ffffff00",
         opacity = 1,
         ontop = true
   })
   infobox.visible = true

   local tablist_region = nil
   local tablist = nil
   local tablist_index = nil

   local traverse_x = c.x + traverse_radius
   local traverse_y = c.y + traverse_radius

   local function ensure_tablist()
      if tablist == nil then
         tablist = {}
         for _, tc in ipairs(screen.tiled_clients) do
            if not (tc.floating or tc.maximized or tc.maximized_horizontal or tc.maximized_vertical)
            then
               if tc.x <= traverse_x and traverse_x < tc.x + tc.width and
                  tc.y <= traverse_y and traverse_y < tc.y + tc.height
               then
                  tablist[#tablist + 1] = tc
               end
            end
         end

         tablist_index = 1
      end
   end

   local function draw_info(context, cr, width, height)
      ensure_tablist()

      cr:set_source_rgba(0, 0, 0, 0)
      cr:rectangle(0, 0, width, height)
      cr:fill()

      local msg, ext
      for i, a in ipairs(regions) do
         cr:rectangle(a.x - start_x, a.y - start_y, a.width, a.height)
         cr:clip()

         if a.x <= traverse_x and traverse_x < a.x + a.width and
            a.y <= traverse_y and traverse_y < a.y + a.height then

            local pl = api.lgi.Pango.Layout.create(cr)
            pl:set_font_description(tablist_font_desc)

            local vpadding = api.dpi(10)
            local list_height = vpadding
            local exts = {}

            for index, tc in ipairs(tablist) do
               local label = tc.name
               pl:set_text(label)
               local w, h
               w, h = pl:get_size()
               w = w / api.lgi.Pango.SCALE
               h = h / api.lgi.Pango.SCALE
               local ext = { width = w, height = h, x_bearing = 0, y_bearing = 0 }
               exts[#exts + 1] = ext
               list_height = list_height + ext.height + vpadding
            end

            local x_offset = a.x + a.width / 2 - start_x
            local y_offset = a.y + a.height / 2 - list_height / 2 + vpadding - start_y

            -- cr:rectangle(a.x - start_x, y_offset - vpadding - start_y, a.width, list_height)
            -- cover the entire region
            cr:rectangle(a.x - start_x, a.y - start_y, a.width, a.height)
            cr:set_source(fill_color)
            cr:fill()

            for index, tc in ipairs(tablist) do
               local label = tc.name
               local ext = exts[index]
               if index == tablist_index then
                  cr:rectangle(x_offset - ext.width / 2 - vpadding / 2, y_offset - vpadding / 2, ext.width + vpadding, ext.height + vpadding)
                  cr:set_source(fill_color_hl)
                  cr:fill()
                  pl:set_text(label)
                  cr:move_to(x_offset - ext.width / 2 - ext.x_bearing, y_offset - ext.y_bearing)
                  cr:set_source(font_color_hl)
                  cr:show_layout(pl)
               else
                  pl:set_text(label)
                  cr:move_to(x_offset - ext.width / 2 - ext.x_bearing, y_offset - ext.y_bearing)
                  cr:set_source(font_color)
                  cr:show_layout(pl)
               end

               y_offset = y_offset + ext.height + vpadding
            end
         end

         -- cr:set_source(fill_color)
         -- cr:rectangle(a.x, a.y, a.width, a.height)
         -- cr:fill()
         cr:set_source(border_color)
         cr:rectangle(a.x - start_x, a.y - start_y, a.width, a.height)
         cr:set_line_width(10.0)
         cr:stroke()
         cr:reset_clip()
      end

      -- show the traverse point
      cr:rectangle(traverse_x - start_x - traverse_radius, traverse_y - start_y - traverse_radius, traverse_radius * 2, traverse_radius * 2)
      cr:set_source_rgba(1, 1, 1, 1)
      cr:fill()
   end

   infobox.bgimage = draw_info

   local kg
   kg = api.awful.keygrabber.run(
      function (mod, key, event)
         if event == "release" then return end
         if key == "Tab" then
            ensure_tablist()

            if #tablist > 0 then
               tablist_index = tablist_index % #tablist + 1
               c = tablist[tablist_index]
               c:emit_signal("request::activate", "mouse.move", {raise=false})
               c:raise()

               infobox.bgimage = draw_info
            end
         elseif key == "Up" or key == "Down" or key == "Left" or key == "Right" then
            local shift = false
            local ctrl = false
            for i, m in ipairs(mod) do
               if m == "Shift" then shift = true
               elseif m == "Control" then ctrl = true
               end
            end

            if shift then
               traverse_x = c.x + traverse_radius
               traverse_y = c.y + traverse_radius
            elseif ctrl then
               traverse_x = c.x + c.width - c.border_width * 2 - traverse_radius
               traverse_y = c.y + c.height - c.border_width * 2 - traverse_radius
            end

            local choice = nil
            local choice_value
            local current_region = nil

            for i, a in ipairs(regions) do
               if a.x <= traverse_x and traverse_x < a.x + a.width and
                  a.y <= traverse_y and traverse_y < a.y + a.height
               then
                  current_region = i
               end

               local v
               if key == "Up" then
                  if a.x < traverse_x + threshold
                  and traverse_x < a.x + a.width + threshold then
                     v = traverse_y - a.y - a.height
                  else
                     v = -1
                  end
               elseif key == "Down" then
                  if a.x < traverse_x + threshold
                  and traverse_x < a.x + a.width + threshold then
                     v = a.y - traverse_y
                  else
                     v = -1
                  end
               elseif key == "Left" then
                  if a.y < traverse_y + threshold
                  and traverse_y < a.y + a.height + threshold then
                     v = traverse_x - a.x - a.width
                  else
                     v = -1
                  end
               elseif key == "Right" then
                  if a.y < traverse_y + threshold
                  and traverse_y < a.y + a.height + threshold then
                     v = a.x - traverse_x
                  else
                     v = -1
                  end
               end

               if (v > threshold) and (choice_value == nil or choice_value > v) then
                  choice = i
                  choice_value = v
               end
            end

            if choice == nil then
               choice = current_region
               if key == "Up" then
                  traverse_y = screen.workarea.y
               elseif key == "Down" then
                  traverse_y = screen.workarea.y + screen.workarea.height
               elseif key == "Left" then
                  traverse_x = screen.workarea.x
               else
                  traverse_x = screen.workarea.x + screen.workarea.width
               end
            end

            if choice ~= nil then
               traverse_x = max(regions[choice].x + traverse_radius, min(regions[choice].x + regions[choice].width - traverse_radius, traverse_x))
               traverse_y = max(regions[choice].y + traverse_radius, min(regions[choice].y + regions[choice].height - traverse_radius, traverse_y))
               tablist = nil

               if shift then
                  if draft_mode then
                     -- move the left-up region
                     local lu = choice
                     local rd = c.machi_rd
                     if regions[rd].x + regions[rd].width <= regions[lu].x or
                        regions[rd].y + regions[rd].height <= regions[lu].y
                     then
                        rd = lu
                     end
                     machi.layout.set_geometry(c, regions[lu], regions[rd], 0, c.border_width)
                     c.machi_lu = lu
                     c.machi_rd = rd
                  else
                     -- move the window
                     machi.layout.set_geometry(c, regions[choice], regions[choice], 0, c.border_width)
                     c.machi_region = choice
                  end
                  c:emit_signal("request::activate", "mouse.move", {raise=false})
                  c:raise()
                  api.layout.arrange(screen)

                  tablist = nil
               elseif ctrl and draft_mode then
                  -- move the right-down region
                  local lu = c.machi_lu
                  local rd = choice
                  if regions[rd].x + regions[rd].width <= regions[lu].x or
                     regions[rd].y + regions[rd].height <= regions[lu].y
                  then
                     lu = rd
                  end
                  machi.layout.set_geometry(c, regions[lu], regions[rd], 0, c.border_width)
                  c.machi_lu = lu
                  c.machi_rd = rd

                  c:emit_signal("request::activate", "mouse.move", {raise=false})
                  c:raise()
                  api.layout.arrange(screen)
               else
                  -- move the focus
                  ensure_tablist()
                  if #tablist > 0 and tablist[1] ~= c then
                     c = tablist[1]
                     api.client.focus = c
                  end
               end

               infobox.bgimage = draw_info
            end
         elseif key == "Escape" or key == "Return" then
            infobox.visible = false
            api.awful.keygrabber.stop(kg)
         else
            print("Unhandled key " .. key)
         end
      end
   )
end

return {
   start = start,
}
