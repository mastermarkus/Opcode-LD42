local Board                   = require "app.Board"
local Button                  = require "app.Button"
local Direction               = require "app.Direction"
local Global                  = require "app.Global"
local Images                  = require "app.Images"
local Map                     = require "app.Map"
local Opcode                  = require "app.Opcode"
local Robot                   = require "app.Robot"
local SaveData                = require "app.SaveData"

local contains_mouse          = require "app.util.contains_mouse"
local rgb                     = require "app.util.color.rgb"
local rgba                    = require "app.util.color.rgba"
local sandbox                 = require "app.util.sandbox"
local vec3                    = require "app.util.color.vec3"
local vec4                    = require "app.util.color.vec4"

local MB_LEFT   = 1
local MB_RIGHT  = 2
local MB_MIDDLE = 3

local TILE_SIZE      =  16
local CODE_FIELD_X   =  18
local CODE_FIELD_Y   =   3
local CODE_PALETTE_X = 185
local CODE_PALETTE_Y = CODE_FIELD_Y

local BUTTON_AREA_X  = CODE_PALETTE_X
local BUTTON_AREA_Y  = 134

local function r2l(x) return x/(TILE_SIZE*Global.SCALE) end
local function l2r(x) return math.floor(x*(TILE_SIZE*Global.SCALE)) end
local function r2t(x) return math.floor(x/(TILE_SIZE*Global.SCALE)) end

local code_editor = {}

local map, robot
local robot_dir
local board_setup

local _opcode_moving = nil
local _opcode_moving_dx = 0
local _opcode_moving_dy = 0
local _opcode_moving_prev_x = nil
local _opcode_moving_prev_y = nil
local _opcode_moving_can_place = true
local _opcode_moving_tile_x = 0
local _opcode_moving_tile_y = 0

local buttons = {}
do
  local x, y = BUTTON_AREA_X, BUTTON_AREA_Y
  local button
  button = Button{
    id       = "Compile";
    x        = x;
    y        = y;
    on_click = function (self)
      code_editor.compile_and_run()
    end;
  } table.insert(buttons, button) x = x + button.width

  button = Button{
    id       = "Reset"  ;
    x        = x;
    y        = y;
    on_click = function (self)
      code_editor.reset()
    end;
  } table.insert(buttons, button) x = x + button.width

  button = Button{
    id       = "Clear"  ;
    x        = x;
    y        = y;
    on_click = function (self)
      setScene("level-select")
    end;
  } table.insert(buttons, button) x = x + button.width
end

local function draw_image_direct(image_path, x, y, angle, ox, oy, scale)
  scale, ox, oy = scale or 1, ox or 0, oy or 0
  local img = Images.get(image_path)
  love.graphics.draw(img, x, y, angle or 0, scale, scale, ox, oy)
end

local function draw_image_tiled(image_path, x, y, angle, scale)
  draw_image_direct(image_path, l2r(x-.5), l2r(y-.5), angle, 8, 8, Global.SCALE)
end

local function draw_OPCODE (self, x, y)
  local scale = Global.SCALE
  if not (x and y) then
    x = l2r(self.x) + CODE_PALETTE_X*scale
    y = l2r(self.y) + CODE_PALETTE_Y*scale
  end

  local v = self:unlocked() and (code_editor.codeable and 1 or .5) or .25
  love.graphics.setColor(v,v,v,v)
  draw_image_direct("code-editor/opcode/"..self.id, x, y, 0, 0, 0, scale)
end

local function make_OPCODE (self)
  return Opcode {
    id      = self.id;
    tiles_x = self.tiles_x;
    tiles_y = self.tiles_y;
    board   = board;
  }
end

local function OPCODE_unlocked (self)
  return SaveData.get_bool(self.id.."-UNLOCKED")
end

local function OpcodeTemplate(opcode)
  local image = Images.get("code-editor/opcode/"..opcode.id)

  local img_w, img_h = image:getDimensions()
  opcode.is_template = true
  opcode.width    = img_w
  opcode.height   = img_h
  opcode.tiles_x  = r2t(img_w*Global.SCALE)
  opcode.tiles_y  = r2t(img_h*Global.SCALE)
  opcode.image    = image
  opcode.draw     = draw_OPCODE
  opcode.contains = contains_mouse
  opcode.make     = make_OPCODE
  opcode.unlocked = OPCODE_unlocked
  return opcode
end

local yoff = 2
local opcode_templates = {
  --OpcodeTemplate { id = "UP"         ; x = 0; y = 0-yoff; };
  --OpcodeTemplate { id = "RIGHT"      ; x = 2; y = 0-yoff; };
  --OpcodeTemplate { id = "DOWN"       ; x = 0; y = 1-yoff; };
  --OpcodeTemplate { id = "LEFT"       ; x = 2; y = 1-yoff; };
  OpcodeTemplate { id = "MOVE_1"     ; x = 0; y = 2-yoff; };
  OpcodeTemplate { id = "TURN_LEFT"  ; x = 1; y = 2-yoff; };
  OpcodeTemplate { id = "TURN_AROUND"; x = 2; y = 2-yoff; };
  OpcodeTemplate { id = "TURN_RIGHT" ; x = 3; y = 2-yoff; };
  OpcodeTemplate { id = "MOVE"       ; x = 0; y = 3-yoff; };
  OpcodeTemplate { id = "INSPECT"    ; x = 2; y = 3-yoff; };
  OpcodeTemplate { id = "GOAL"       ; x = 3; y = 3-yoff; };
  OpcodeTemplate { id = "ADD"        ; x = 0; y = 4-yoff; };
  OpcodeTemplate { id = "SUB"        ; x = 2; y = 4-yoff; };
  OpcodeTemplate { id = "MUL"        ; x = 0; y = 5-yoff; };
  OpcodeTemplate { id = "DIV"        ; x = 2; y = 5-yoff; };
  OpcodeTemplate { id = "JUMP_LEQ"   ; x = 0; y = 6-yoff; };
  OpcodeTemplate { id = "SET"        ; x = 2; y = 6-yoff; };
  OpcodeTemplate { id = "JUMP"       ; x = 0; y = 7-yoff; };
}
for _, template in ipairs(opcode_templates) do
  opcode_templates[template.id] = template
end

function code_editor.on_enter(level_id)
  code_editor.level_id = level_id
  local setup = sandbox("app/level/"..level_id..".lua", {
    unlockOpcode = unlockOpcode;
    instructions = instructions;
    isAndroid    = love.system.getOS() == "Android";
    unpack       = unpack;
  })
  robot_dir = type(setup) == "string" and Direction.from(setup) or nil
  board_setup = type(setup) == "table" and setup or nil
  if type(board_setup) == "table" then
    robot_dir = board_setup.dir and Direction.from(board_setup.dir) or nil
  end
  code_editor.clear()
end

function code_editor.reset()
  map = Map.load_png(code_editor.level_id)

  robot = Robot {
    x = map.start_x[1];
    y = map.start_y[1];
    dir = robot_dir
  }
  code_editor.codeable = true
end

function code_editor.compile_and_run()
  code_editor.reset()
  code_editor.codeable = false
  board.active_input = nil
  if _opcode_moving then
    if not _opcode_moving.is_template then
      board:place(_opcode_moving, _opcode_moving_prev_x, _opcode_moving_prev_y)
    end
    _opcode_moving = nil
  end
  robot:execute (board:compile())
end

function code_editor.clear()
  code_editor.reset()
  board = Board {
    tiles_x = map.tiles_x;
    tiles_y = map.tiles_y;
  }
  if board_setup then
    robot_dir = board_setup.dir and Direction.from(board_setup.dir)
    for _, v in ipairs(board_setup) do
      local id, x, y = unpack(v)
      board:place(opcode_templates[id], x, y)
    end
  end
  robot.dir = robot_dir or robot.dir
end

function code_editor.update(dt)
  robot:update(map, dt)

  if robot:has_won() then
    setPopup("won", self, robot, map)
    code_editor.reset()
  end
end

function code_editor.mousepressed(mx, my, button, isTouch)
  _opcode_moving = nil

  local scale = Global.SCALE
  local code_palette_x = CODE_PALETTE_X*scale
  local code_palette_y = CODE_PALETTE_Y*scale

  if mx >= code_palette_x and my >= code_palette_y then
    if button == MB_LEFT then
      for _, btn in ipairs(buttons) do
        btn:mousepressed(mx, my, button, isTouch)
      end
    end

    if code_editor.codeable then
      local mx2 = mx - code_palette_x
      local my2 = my - code_palette_y

      for _, template in ipairs(opcode_templates) do
        if template:unlocked() then
          local dx = mx2 - l2r(template.x)
          local dy = my2 - l2r(template.y)
          if template:contains(dx, dy) then
            _opcode_moving = template
            _opcode_moving_prev_x = nil
            _opcode_moving_prev_y = nil
            _opcode_moving_dx = dx
            _opcode_moving_dy = dy
            return
          end
        end
      end
    end
  elseif code_editor.codeable then
    local field_mx = mx - CODE_FIELD_X*scale
    local field_my = my - CODE_FIELD_Y*scale
    local tile_x = 1 + r2t(field_mx)
    local tile_y = 1 + r2t(field_my)
    local opcode, opcode_x, opcode_y = board:try_locate(tile_x, tile_y)
    if not opcode then
      board.active_input = nil
      return
    end

    local local_mx = math.floor((field_mx - l2r(opcode_x - 1))/scale)
    local local_my = math.floor((field_my - l2r(opcode_y - 1))/scale)
    if opcode:on_click(local_mx, local_my, button, isTouch) then
      local dx = local_mx*scale
      local dy = local_my*scale
      _opcode_moving = opcode

      board:remove(opcode_x, opcode_y)
      _opcode_moving_prev_x = opcode_x
      _opcode_moving_prev_y = opcode_y

      _opcode_moving_dx = dx
      _opcode_moving_dy = dy
    end
  end
end

function code_editor.mousereleased(mx, my, button, isTouch)
  if not code_editor.codeable then return end

  local to_place = _opcode_moving; _opcode_moving = nil
  if not to_place then return end
  if not _opcode_moving_can_place then
    if to_place.is_template then return end
    local delete = mx >= (CODE_PALETTE_X*Global.SCALE)
    if delete then return end

    _opcode_moving_tile_x = _opcode_moving_prev_x
    _opcode_moving_tile_y = _opcode_moving_prev_y
  end
  board:place(to_place, _opcode_moving_tile_x, _opcode_moving_tile_y)
end

function code_editor.keypressed(key, scancode, isrepeat)
  if key == "escape" and not isrepeat then
    setScene("level-select")
    return
  elseif robot:is_idle() and key == "return" and not isrepeat then
    code_editor.compile_and_run()
  elseif code_editor.codeable then
    board:keypressed(key, scancode, isrepeat)
  end
end

function code_editor.draw()
  local scale = Global.SCALE

  love.graphics.push()
  love.graphics.setColor(1,1,1)
  love.graphics.draw(Images.get("code-editor/Board"), 0, 0, 0, scale, scale)

  love.graphics.translate(scale*CODE_FIELD_X, scale*CODE_FIELD_Y)
  code_editor.draw_tiles()
  --code_editor.draw_start_tiles()
  code_editor.draw_robot()
  code_editor.draw_tint_shade()
  love.graphics.pop()

  code_editor.draw_opcode_templates()
  code_editor.draw_buttons()
  code_editor.try_draw_opcode_moving()
end

function code_editor.draw_opcode_templates()
  for _, template in ipairs(opcode_templates) do
    if template ~= _opcode_moving then
      template:draw()
    end
  end
end

function code_editor.draw_buttons()
  local scale = Global.SCALE
  for _, button in ipairs(buttons) do
    button:draw(scale)
  end
end

function code_editor.try_draw_opcode_moving()
  if not _opcode_moving then return end
  code_editor.draw_opcode_placement_indicator()
  local mx, my = love.mouse.getPosition()
  local x = mx - _opcode_moving_dx
  local y = my - _opcode_moving_dy
  love.graphics.setColor(vec4(1.0, 1.0, 1.0, 0.5))
  _opcode_moving:draw(x, y)
end

function code_editor.draw_start_tiles()
  local half_scaled_tile_size = (TILE_SIZE*Global.SCALE)/2
  love.graphics.setColor(vec3(0.07, 0.68, 0.0))
  love.graphics.setLineWidth(4)
  for i = 1, #map.start_x do
    local x = map.start_x[i]
    local y = map.start_y[i]

    local render_x = l2r(x-0.75)
    local render_y = l2r(y-0.75)
    love.graphics.rectangle("line", render_x, render_y, half_scaled_tile_size, half_scaled_tile_size)
  end
  love.graphics.setLineWidth(1)
end

function code_editor.draw_tiles()
  local idle = robot:is_idle()
  local scale = Global.SCALE
  local render_tile_size = TILE_SIZE*scale
  for y = 1, map.tiles_y do
    for x = 1, map.tiles_x do
      code_editor.try_draw_tile(x, y)
      code_editor.try_draw_item(x, y)

      local opcode = board:opcode_at(x, y)
      if opcode then
        love.graphics.setColor(1, 1, 1, idle and (code_editor.codeable and 1 or 0.5) or 0.25)
        opcode:draw(l2r(x-1), l2r(y-1))
      end
    end
  end
end

function code_editor.draw_tint_shade()
  if not robot:is_idle() then return end

  love.graphics.setColor(vec4(0.0, 0.0, 0.0, 0.5))
  local scale = Global.SCALE
  local render_tile_size = TILE_SIZE*scale
  for y = 1, map.tiles_y do
    for x = 1, map.tiles_x do
      local shade = map:is_start(x, y)
                 or map:get_tile_at(x,y)
                 or map:get_item_at(x,y)
      if shade then
        love.graphics.rectangle("fill", l2r(x-1), l2r(y-1), render_tile_size, render_tile_size)
      end
    end
  end
end

function code_editor.try_draw_tile(x, y)
  local tile = map:get_tile_at(x, y) if not tile then return end
  love.graphics.setColor(1,1,1)
  if tile == "WALL" then
    draw_image_tiled("game/wall", x, y)
  elseif tile == "GOAL" then
    draw_image_tiled("game/goal", x, y)
  end
  return true
end

function code_editor.try_draw_item(x, y)
  local item = map:get_item_at(x, y) if not item then return end

  if item == "FLOPPY" then
    love.graphics.setColor(1,1,1)
    draw_image_tiled("game/floppy", x, y)
  end
  return true
end

function code_editor.draw_robot()
  local anim = 1 + math.floor(robot.anim*TILE_SIZE)%4

  local x, y = robot.x, robot.y
  love.graphics.setColor(1,1,1)
  draw_image_tiled("game/robot/"..anim, x, y, Direction.angle(robot.dir))
end

function code_editor.draw_opcode_placement_indicator()
  local scale = Global.SCALE
  local code_field_x = CODE_FIELD_X*scale
  local code_field_y = CODE_FIELD_Y*scale
  local mx, my = love.mouse.getPosition()
  local tile_dx = r2t((mx - _opcode_moving_dx) - code_field_x)
  local tile_dy = r2t((my - _opcode_moving_dy) - code_field_y)
  local tiles_x = _opcode_moving.tiles_x
  local tiles_y = _opcode_moving.tiles_y

  local render_tile_size = TILE_SIZE*scale

  _opcode_moving_can_place = true
  _opcode_moving_tile_x = 1 + tile_dx
  _opcode_moving_tile_y = 1 + tile_dy

  for yi = 1, tiles_y do
    local y = yi + tile_dy
    for xi = 1, tiles_x do
      local x = xi + tile_dx
      local render_x = l2r(x-1) + code_field_x
      local render_y = l2r(y-1) + code_field_y

      local valid = board:empty_at(x, y)
                and not map:get_item_at(x, y)
                and not map:get_tile_at(x, y)
                and not map:is_start(x, y)

      _opcode_moving_can_place = _opcode_moving_can_place and valid

      local color = valid and vec4(0.15, 0.8, 0.23, 0.7)
                           or vec4(0.69, 0.18, 0.17, 0.7)

      love.graphics.setColor(color)
      love.graphics.rectangle("fill", render_x, render_y, render_tile_size, render_tile_size)
    end
  end
end

return code_editor
