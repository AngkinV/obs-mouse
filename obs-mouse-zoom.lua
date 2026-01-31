--
-- OBS Mouse Zoom (Enhanced)
-- An optimized OBS lua script to zoom a display-capture source to focus on the mouse.
-- Based on obs-zoom-to-mouse by BlankSourceCode, optimized for macOS compatibility.
-- Version: 2.0
--

local obs = obslua
local ffi = require("ffi")
local VERSION = "4.0"
local CROP_FILTER_NAME = "obs-mouse-zoom-crop"
local VIGNETTE_FILTER_NAME = "obs-mouse-zoom-vignette"
local SPOTLIGHT_SOURCE_NAME = "obs-mouse-spotlight"
local PIP_SOURCE_PREFIX = "obs-mouse-pip-"
local PIP_BORDER_PREFIX = "obs-mouse-pip-border-"
local PIP_MAX_WINDOWS = 3

-- State variables
local source_name = ""
local source = nil
local sceneitem = nil
local sceneitem_info_orig = nil
local sceneitem_crop_orig = nil
local sceneitem_info = nil
local sceneitem_crop = nil
local crop_filter = nil
local crop_filter_temp = nil
local crop_filter_settings = nil
local crop_filter_info_orig = { x = 0, y = 0, w = 0, h = 0 }
local crop_filter_info = { x = 0, y = 0, w = 0, h = 0 }
local monitor_info = nil

local zoom_info = {
    source_size = { width = 0, height = 0 },
    source_crop = { x = 0, y = 0, w = 0, h = 0 },
    source_crop_filter = { x = 0, y = 0, w = 0, h = 0 },
    zoom_to = 2
}

local zoom_time = 0
local zoom_target = nil
local locked_center = nil
local locked_last_pos = nil
local hotkey_zoom_id = nil
local hotkey_follow_id = nil
local is_timer_running = false

-- Platform-specific variables
local win_point = nil
local x11_display = nil
local x11_root = nil
local x11_mouse = nil
local cg_event_lib = nil
local cg_get_location = nil
local mouse_api_method = "unknown"
local mouse_api_available = false

-- Settings
local use_auto_follow_mouse = true
local use_follow_outside_bounds = false
local is_following_mouse = false
local follow_speed = 0.15
local follow_border = 8
local follow_safezone_sensitivity = 6
local use_follow_auto_lock = false
local zoom_value = 2
local zoom_speed = 0.08
local allow_all_sources = false
local use_monitor_override = false
local monitor_override_x = 0
local monitor_override_y = 0
local monitor_override_w = 0
local monitor_override_h = 0
local monitor_override_sx = 1
local monitor_override_sy = 1
local monitor_override_dw = 0
local monitor_override_dh = 0
local debug_logs = false

-- Easing options
local use_smooth_easing = true
local easing_style = 1 -- 1=smooth, 2=elastic, 3=bounce

-- Vignette effect settings
local use_vignette_effect = true
local vignette_intensity = 0.5
local vignette_filter = nil
local vignette_filter_settings = nil
local vignette_progress = 0 -- 0=off, 1=full effect

-- Spotlight effect settings
local use_spotlight = true
local spotlight_radius = 200
local spotlight_opacity = 0.4
local spotlight_source = nil
local spotlight_sceneitem = nil
local spotlight_tga_path = nil
local hotkey_spotlight_id = nil
local is_spotlight_active = true -- can be toggled by hotkey

-- Character overlay effect settings
local use_magnifier_character = true
local magnifier_scale = 0.5 -- Scale of the character
local character_anchor_x = 0 -- Anchor point X (0-100%, 0=left, 50=center, 100=right)
local character_anchor_y = 0 -- Anchor point Y (0-100%, 0=top, 50=center, 100=bottom)

-- Character overlay sources and sceneitems
local magnifier_character_source = nil
local magnifier_character_sceneitem = nil

-- Magnifier animation state
local MagnifierAnimState = {
    Hidden = 0,
    EnteringSlide = 1,   -- Sliding in from edge
    EnteringBounce = 2,  -- Bounce/overshoot effect
    Visible = 3,
    Exiting = 4
}
local magnifier_anim_state = MagnifierAnimState.Hidden
local magnifier_anim_time = 0
local magnifier_anim_speed = 0.08
local magnifier_entry_direction = "right" -- Where character enters from
local magnifier_current_pos = { x = 0, y = 0 }
local magnifier_target_pos = { x = 0, y = 0 }
local MAGNIFIER_CHARACTER_NAME = "obs-mouse-character-overlay"

local ZoomState = {
    None = 0,
    ZoomingIn = 1,
    ZoomingOut = 2,
    ZoomedIn = 3,
}
local zoom_state = ZoomState.None

-- Picture-in-Picture (PiP) system
local PiPMode = {
    FollowMouse = 1,    -- Real-time follow mouse position
    FixedRegion = 2,    -- Monitor a fixed region
    Locked = 3,         -- Locked at current mouse position
}

local PiPPosition = {
    TopLeft = 1,
    TopCenter = 2,
    TopRight = 3,
    MiddleLeft = 4,
    MiddleRight = 5,
    BottomLeft = 6,
    BottomCenter = 7,
    BottomRight = 8,
    Custom = 9,
}

-- PiP settings
local use_pip = false
local pip_windows = {}  -- Array of PiP window configurations

-- Default PiP window configuration template
local function create_default_pip_config(id)
    return {
        id = id,
        enabled = false,
        mode = PiPMode.FollowMouse,

        -- Source region (area to magnify)
        source_x = 0,
        source_y = 0,
        source_width = 400,
        source_height = 300,
        source_offset_x = 0,   -- Offset from mouse position (FollowMouse mode)
        source_offset_y = 0,

        -- Display settings
        display_position = PiPPosition.TopRight,
        display_x = 0,          -- Custom position X
        display_y = 0,          -- Custom position Y
        display_width = 320,
        display_height = 240,
        zoom_factor = 2.5,

        -- Style settings
        border_enabled = true,
        border_width = 3,
        corner_radius = 8,
        opacity = 1.0,

        -- Animation settings
        smooth_follow = true,
        follow_speed = 0.15,

        -- Runtime state (not saved)
        source = nil,
        sceneitem = nil,
        crop_filter = nil,
        crop_settings = nil,
        border_source = nil,
        border_sceneitem = nil,
        current_crop = { x = 0, y = 0, w = 0, h = 0 },
        target_crop = { x = 0, y = 0, w = 0, h = 0 },
        is_visible = false,
    }
end

-- Initialize pip_windows array
for i = 1, PIP_MAX_WINDOWS do
    pip_windows[i] = create_default_pip_config(i)
end

-- PiP hotkeys
local pip_hotkey_toggle = {}    -- Toggle visibility for each window
local pip_hotkey_lock = {}      -- Lock position for each window
local pip_hotkey_all = nil      -- Toggle all windows

-- OBS version detection
local version = obs.obs_get_version_string()
local major = tonumber(version:match("(%d+%.%d+)")) or 0

-- API compatibility: OBS 31+ uses new transform API
local use_new_transform_api = (obs.obs_sceneitem_get_info2 ~= nil)

---
-- Helper functions for transform API compatibility
local function create_transform_info()
    -- Structure name stays obs_transform_info in all OBS versions
    return obs.obs_transform_info()
end

local function get_sceneitem_info(item, info)
    if use_new_transform_api then
        obs.obs_sceneitem_get_info2(item, info)
    else
        obs.obs_sceneitem_get_info(item, info)
    end
end

local function set_sceneitem_info(item, info)
    if use_new_transform_api then
        obs.obs_sceneitem_set_info2(item, info)
    else
        obs.obs_sceneitem_set_info(item, info)
    end
end

---
-- Initialize mouse position API for each platform
local function init_mouse_api()
    if ffi.os == "Windows" then
        -- Windows: Use GetCursorPos
        local success, err = pcall(function()
            ffi.cdef([[
                typedef int BOOL;
                typedef struct{
                    long x;
                    long y;
                } POINT, *LPPOINT;
                BOOL GetCursorPos(LPPOINT);
            ]])
            win_point = ffi.new("POINT[1]")
        end)

        if success and win_point then
            mouse_api_method = "Windows GetCursorPos"
            mouse_api_available = true
        else
            obs.script_log(obs.OBS_LOG_WARNING, "Failed to initialize Windows mouse API: " .. tostring(err))
        end

    elseif ffi.os == "Linux" then
        -- Linux: Use X11
        local success, err = pcall(function()
            ffi.cdef([[
                typedef unsigned long XID;
                typedef XID Window;
                typedef void Display;
                Display* XOpenDisplay(char*);
                XID XDefaultRootWindow(Display *display);
                int XQueryPointer(Display*, Window, Window*, Window*, int*, int*, int*, int*, unsigned int*);
                int XCloseDisplay(Display*);
            ]])

            local x11_lib = ffi.load("X11.so.6")
            x11_display = x11_lib.XOpenDisplay(nil)
            if x11_display ~= nil then
                x11_root = x11_lib.XDefaultRootWindow(x11_display)
                x11_mouse = {
                    lib = x11_lib,
                    root_win = ffi.new("Window[1]"),
                    child_win = ffi.new("Window[1]"),
                    root_x = ffi.new("int[1]"),
                    root_y = ffi.new("int[1]"),
                    win_x = ffi.new("int[1]"),
                    win_y = ffi.new("int[1]"),
                    mask = ffi.new("unsigned int[1]")
                }
            end
        end)

        if success and x11_display then
            mouse_api_method = "Linux X11"
            mouse_api_available = true
        else
            obs.script_log(obs.OBS_LOG_WARNING, "Failed to initialize Linux mouse API: " .. tostring(err))
        end

    elseif ffi.os == "OSX" then
        -- macOS: Try multiple methods for better compatibility

        -- Method 1: Try CGEventGetLocation (most reliable on modern macOS)
        local success1, err1 = pcall(function()
            ffi.cdef([[
                typedef double CGFloat;
                typedef struct CGPoint { CGFloat x; CGFloat y; } CGPoint;
                typedef unsigned int CGEventType;
                typedef void* CGEventRef;
                typedef unsigned long long CGEventSourceStateID;

                CGEventRef CGEventCreate(void* source);
                CGPoint CGEventGetLocation(CGEventRef event);
                void CFRelease(void* cf);
            ]])

            cg_event_lib = ffi.load("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
        end)

        if success1 and cg_event_lib then
            -- Test if the API actually works
            local test_success = pcall(function()
                local event = cg_event_lib.CGEventCreate(nil)
                if event ~= nil then
                    local point = cg_event_lib.CGEventGetLocation(event)
                    cg_event_lib.CFRelease(event)
                end
            end)

            if test_success then
                mouse_api_method = "macOS CGEventGetLocation"
                mouse_api_available = true
                cg_get_location = function()
                    local event = cg_event_lib.CGEventCreate(nil)
                    if event ~= nil then
                        local point = cg_event_lib.CGEventGetLocation(event)
                        cg_event_lib.CFRelease(event)
                        return { x = tonumber(point.x), y = tonumber(point.y) }
                    end
                    return nil
                end
            end
        end

        -- Method 2: Try CoreGraphics directly if Method 1 failed
        if not mouse_api_available then
            local success2, err2 = pcall(function()
                ffi.cdef([[
                    typedef double CGFloat;
                    typedef struct { CGFloat x; CGFloat y; } CGPoint2;
                    typedef unsigned int CGDirectDisplayID;
                    CGDirectDisplayID CGMainDisplayID(void);
                    unsigned int CGDisplayPixelsHigh(CGDirectDisplayID display);
                ]])
            end)

            -- Try loading NSEvent via objc runtime as fallback
            local success3, err3 = pcall(function()
                local objc = ffi.load("libobjc")
                if objc then
                    ffi.cdef([[
                        typedef void* id;
                        typedef void* SEL;
                        typedef void* Method;
                        typedef void* Class;
                        typedef struct { double x; double y; } NSPoint;

                        SEL sel_registerName(const char *str);
                        Class objc_getClass(const char* name);
                        Method class_getClassMethod(Class cls, SEL name);
                        void* method_getImplementation(Method m);
                    ]])

                    local nsevent_class = objc.objc_getClass("NSEvent")
                    local mouse_location_sel = objc.sel_registerName("mouseLocation")

                    if nsevent_class ~= nil and mouse_location_sel ~= nil then
                        local method = objc.class_getClassMethod(nsevent_class, mouse_location_sel)
                        if method ~= nil then
                            local imp = objc.method_getImplementation(method)
                            if imp ~= nil then
                                local get_mouse = ffi.cast("NSPoint(*)(id, SEL)", imp)
                                cg_get_location = function()
                                    local point = get_mouse(nsevent_class, mouse_location_sel)
                                    local screen_height = 1080 -- Will be updated from monitor_info
                                    if monitor_info and monitor_info.display_height > 0 then
                                        screen_height = monitor_info.display_height
                                    elseif monitor_info and monitor_info.height > 0 then
                                        screen_height = monitor_info.height
                                    end
                                    -- NSEvent uses flipped Y coordinate
                                    return { x = tonumber(point.x), y = screen_height - tonumber(point.y) }
                                end
                                mouse_api_method = "macOS NSEvent (fallback)"
                                mouse_api_available = true
                            end
                        end
                    end
                end
            end)
        end

        if not mouse_api_available then
            obs.script_log(obs.OBS_LOG_ERROR,
                "Failed to initialize macOS mouse API.\n" ..
                "Please enable 'Set manual source position' and configure monitor settings.\n" ..
                "You may also need to grant OBS accessibility permissions in System Preferences.")
        end
    end

    if mouse_api_available then
        obs.script_log(obs.OBS_LOG_INFO, "Mouse API initialized: " .. mouse_api_method)
    end

    -- Log transform API version
    if use_new_transform_api then
        obs.script_log(obs.OBS_LOG_INFO, "Transform API: v2 (OBS 31+)")
    else
        obs.script_log(obs.OBS_LOG_INFO, "Transform API: v1 (legacy)")
    end

    return mouse_api_available
end

---
-- Get the current mouse position
function get_mouse_pos()
    local mouse = { x = 0, y = 0 }

    if ffi.os == "Windows" then
        if win_point and ffi.C.GetCursorPos(win_point) ~= 0 then
            mouse.x = win_point[0].x
            mouse.y = win_point[0].y
        end
    elseif ffi.os == "Linux" then
        if x11_mouse and x11_display and x11_root then
            if x11_mouse.lib.XQueryPointer(x11_display, x11_root,
                x11_mouse.root_win, x11_mouse.child_win,
                x11_mouse.root_x, x11_mouse.root_y,
                x11_mouse.win_x, x11_mouse.win_y,
                x11_mouse.mask) ~= 0 then
                mouse.x = tonumber(x11_mouse.win_x[0])
                mouse.y = tonumber(x11_mouse.win_y[0])
            end
        end
    elseif ffi.os == "OSX" then
        if cg_get_location then
            local point = cg_get_location()
            if point then
                mouse.x = point.x
                mouse.y = point.y
            end
        end
    end

    return mouse
end

---
-- Get the information about display capture sources for the current platform
function get_dc_info()
    if ffi.os == "Windows" then
        return {
            source_id = "monitor_capture",
            prop_id = "monitor_id",
            prop_type = "string"
        }
    elseif ffi.os == "Linux" then
        return {
            source_id = "xshm_input",
            prop_id = "screen",
            prop_type = "int"
        }
    elseif ffi.os == "OSX" then
        if major >= 28 then
            return {
                source_id = "screen_capture",
                prop_id = "display_uuid",
                prop_type = "string"
            }
        else
            return {
                source_id = "display_capture",
                prop_id = "display",
                prop_type = "int"
            }
        end
    end

    return nil
end

---
-- Logs a message to the OBS script console
function log(msg)
    if debug_logs then
        obs.script_log(obs.OBS_LOG_INFO, msg)
    end
end

---
-- Format the given lua table into a string
function format_table(tbl, indent)
    if not indent then
        indent = 0
    end

    local str = "{\n"
    for key, value in pairs(tbl) do
        local tabs = string.rep("  ", indent + 1)
        if type(value) == "table" then
            str = str .. tabs .. key .. " = " .. format_table(value, indent + 1) .. ",\n"
        else
            str = str .. tabs .. key .. " = " .. tostring(value) .. ",\n"
        end
    end
    str = str .. string.rep("  ", indent) .. "}"

    return str
end

---
-- Linear interpolate between v0 and v1
function lerp(v0, v1, t)
    return v0 * (1 - t) + v1 * t
end

---
-- Smooth step easing (modern, smooth animation)
function smoothstep(t)
    return t * t * (3 - 2 * t)
end

---
-- Smoother step easing (even smoother animation)
function smootherstep(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

---
-- Elastic easing out
function elastic_out(t)
    if t == 0 or t == 1 then return t end
    local p = 0.3
    local s = p / 4
    return math.pow(2, -10 * t) * math.sin((t - s) * (2 * math.pi) / p) + 1
end

---
-- Bounce easing out
function bounce_out(t)
    if t < 1/2.75 then
        return 7.5625 * t * t
    elseif t < 2/2.75 then
        t = t - 1.5/2.75
        return 7.5625 * t * t + 0.75
    elseif t < 2.5/2.75 then
        t = t - 2.25/2.75
        return 7.5625 * t * t + 0.9375
    else
        t = t - 2.625/2.75
        return 7.5625 * t * t + 0.984375
    end
end

---
-- Get the appropriate easing function based on settings
function get_easing(t)
    if not use_smooth_easing then
        -- Classic cubic ease in/out
        t = t * 2
        if t < 1 then
            return 0.5 * t * t * t
        else
            t = t - 2
            return 0.5 * (t * t * t + 2)
        end
    else
        if easing_style == 1 then
            return smootherstep(t)
        elseif easing_style == 2 then
            return elastic_out(t)
        elseif easing_style == 3 then
            return bounce_out(t)
        else
            return smootherstep(t)
        end
    end
end

---
-- Clamps a given value between min and max
function clamp(min, max, value)
    return math.max(min, math.min(max, value))
end

---
-- Get mouse position converted to OBS canvas coordinates
-- This position should match where the user sees the mouse in preview/recording
function get_mouse_canvas_pos()
    local raw_mouse = get_mouse_pos()

    -- Step 1: Get canvas dimensions
    local video_info = obs.obs_video_info()
    obs.obs_get_video_info(video_info)
    local canvas_width = video_info.base_width
    local canvas_height = video_info.base_height

    -- Step 2: Calculate mouse position in source pixel space
    local monitor_x = (monitor_info and monitor_info.x) or 0
    local monitor_y = (monitor_info and monitor_info.y) or 0
    local sx = (monitor_info and monitor_info.scale_x) or 1
    local sy = (monitor_info and monitor_info.scale_y) or 1

    -- Mouse relative to monitor logical coords -> source pixel coords
    local source_mouse_x = (raw_mouse.x - monitor_x) * sx
    local source_mouse_y = (raw_mouse.y - monitor_y) * sy

    -- Step 3: Get current crop region (this region shrinks when zoomed in)
    local crop_x = (crop_filter_info and crop_filter_info.x) or 0
    local crop_y = (crop_filter_info and crop_filter_info.y) or 0
    local crop_w = (crop_filter_info and crop_filter_info.w) or 0
    local crop_h = (crop_filter_info and crop_filter_info.h) or 0

    -- If no crop info, use original source size
    if crop_w == 0 or crop_h == 0 then
        crop_w = (zoom_info and zoom_info.source_size.width) or canvas_width
        crop_h = (zoom_info and zoom_info.source_size.height) or canvas_height
    end

    -- Step 4: Calculate mouse relative position within crop region (0-1)
    local rel_x = (source_mouse_x - crop_x) / crop_w
    local rel_y = (source_mouse_y - crop_y) / crop_h

    -- Step 5: Map to canvas coordinates
    local canvas_x = rel_x * canvas_width
    local canvas_y = rel_y * canvas_height

    -- Debug logging
    log(string.format("[SPOTLIGHT] raw=(%d,%d) source=(%d,%d) crop=(%d,%d,%d,%d) rel=(%.2f,%.2f) canvas=(%d,%d)",
        raw_mouse.x, raw_mouse.y,
        source_mouse_x, source_mouse_y,
        crop_x, crop_y, crop_w, crop_h,
        rel_x, rel_y,
        canvas_x, canvas_y))

    return { x = canvas_x, y = canvas_y }
end

---
-- Get the script directory path
function get_script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*/)")
end

---
-- Generate a radial gradient TGA image for the spotlight effect
-- TGA format: 18-byte header + raw BGRA pixel data
function generate_spotlight_tga(filepath, size, inner_radius_ratio, edge_opacity)
    local file = io.open(filepath, "wb")
    if not file then
        log("ERROR: Failed to create spotlight TGA file: " .. filepath)
        return false
    end

    -- TGA Header (18 bytes)
    local header = string.char(
        0,          -- ID length
        0,          -- Color map type (none)
        2,          -- Image type (uncompressed true-color)
        0, 0,       -- Color map origin
        0, 0,       -- Color map length
        0,          -- Color map depth
        0, 0,       -- X origin
        0, 0,       -- Y origin
        size % 256, math.floor(size / 256),  -- Width (little-endian)
        size % 256, math.floor(size / 256),  -- Height (little-endian)
        32,         -- Bits per pixel (BGRA)
        0x28        -- Image descriptor (top-left origin, 8 alpha bits)
    )
    file:write(header)

    -- Generate pixel data (BGRA format)
    local center = size / 2
    local inner_radius = center * inner_radius_ratio
    local outer_radius = center

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local dx = x - center
            local dy = y - center
            local dist = math.sqrt(dx * dx + dy * dy)

            local alpha = 0
            if dist >= outer_radius then
                alpha = math.floor(edge_opacity * 255)
            elseif dist > inner_radius then
                -- Smooth gradient from inner to outer
                local t = (dist - inner_radius) / (outer_radius - inner_radius)
                -- Use smoothstep for nicer falloff
                t = t * t * (3 - 2 * t)
                alpha = math.floor(t * edge_opacity * 255)
            end

            -- BGRA: Blue, Green, Red, Alpha (black with varying alpha)
            file:write(string.char(0, 0, 0, alpha))
        end
    end

    file:close()
    log("Spotlight TGA generated: " .. filepath)
    return true
end

---
-- Create and add vignette effect filter to the source
function create_vignette_filter()
    if source == nil or vignette_filter ~= nil then
        return
    end

    vignette_filter_settings = obs.obs_data_create()
    -- Start with neutral values (no effect)
    obs.obs_data_set_double(vignette_filter_settings, "contrast", 0)
    obs.obs_data_set_double(vignette_filter_settings, "brightness", 0)
    obs.obs_data_set_double(vignette_filter_settings, "saturation", 0)
    obs.obs_data_set_double(vignette_filter_settings, "gamma", 0)

    vignette_filter = obs.obs_source_create_private("color_correction_filter", VIGNETTE_FILTER_NAME, vignette_filter_settings)
    if vignette_filter then
        obs.obs_source_filter_add(source, vignette_filter)
        log("Vignette filter created")
    end
end

---
-- Update vignette filter based on current progress (0-1)
function update_vignette_filter(progress)
    if vignette_filter == nil or vignette_filter_settings == nil then
        return
    end

    -- Target values at full effect (progress = 1)
    local target_contrast = 0.15 * vignette_intensity
    local target_brightness = -0.03 * vignette_intensity
    local target_saturation = 0.08 * vignette_intensity

    -- Interpolate from 0 to target based on progress
    obs.obs_data_set_double(vignette_filter_settings, "contrast", target_contrast * progress)
    obs.obs_data_set_double(vignette_filter_settings, "brightness", target_brightness * progress)
    obs.obs_data_set_double(vignette_filter_settings, "saturation", target_saturation * progress)

    obs.obs_source_update(vignette_filter, vignette_filter_settings)
end

---
-- Remove vignette filter
function remove_vignette_filter()
    if vignette_filter ~= nil and source ~= nil then
        obs.obs_source_filter_remove(source, vignette_filter)
        obs.obs_source_release(vignette_filter)
        vignette_filter = nil
        log("Vignette filter removed")
    end
    if vignette_filter_settings ~= nil then
        obs.obs_data_release(vignette_filter_settings)
        vignette_filter_settings = nil
    end
    vignette_progress = 0
end

---
-- Create spotlight source and add to scene
function create_spotlight_source()
    if spotlight_source ~= nil then
        return -- Already exists
    end

    -- Generate TGA if needed
    if spotlight_tga_path == nil then
        local script_dir = get_script_path()
        if script_dir then
            spotlight_tga_path = script_dir .. "spotlight_overlay.tga"
        else
            spotlight_tga_path = "spotlight_overlay.tga"
        end
    end

    -- Generate the TGA file with current settings
    local tga_size = 512
    local inner_ratio = 0.3 -- Center 30% is fully transparent
    if not generate_spotlight_tga(spotlight_tga_path, tga_size, inner_ratio, spotlight_opacity) then
        return
    end

    -- Create image source
    local settings = obs.obs_data_create()
    obs.obs_data_set_string(settings, "file", spotlight_tga_path)
    spotlight_source = obs.obs_source_create_private("image_source", SPOTLIGHT_SOURCE_NAME, settings)
    obs.obs_data_release(settings)

    if spotlight_source then
        log("Spotlight source created")
    end
end

---
-- Add spotlight to current scene
function add_spotlight_to_scene()
    if spotlight_source == nil or spotlight_sceneitem ~= nil then
        return
    end

    local scene_source = obs.obs_frontend_get_current_scene()
    if scene_source == nil then
        return
    end

    local scene = obs.obs_scene_from_source(scene_source)
    if scene then
        spotlight_sceneitem = obs.obs_scene_add(scene, spotlight_source)
        if spotlight_sceneitem then
            -- Scale the spotlight to desired size
            local target_size = spotlight_radius * 4 -- TGA is 512, we scale to radius * 4 pixels
            local scale = target_size / 512 -- TGA is 512 pixels, calculate scale factor

            local info = create_transform_info()
            get_sceneitem_info(spotlight_sceneitem, info)
            info.scale.x = scale
            info.scale.y = scale
            set_sceneitem_info(spotlight_sceneitem, info)

            -- Move to top of scene
            obs.obs_sceneitem_set_order(spotlight_sceneitem, obs.OBS_ORDER_MOVE_TOP)
            obs.obs_sceneitem_set_visible(spotlight_sceneitem, false) -- Start hidden

            log("Spotlight added to scene")
        end
    end

    obs.obs_source_release(scene_source)
end

---
-- Show spotlight and position it
function show_spotlight()
    if spotlight_sceneitem == nil then
        add_spotlight_to_scene()
    end
    if spotlight_sceneitem ~= nil then
        obs.obs_sceneitem_set_visible(spotlight_sceneitem, true)
    end
end

---
-- Hide spotlight
function hide_spotlight()
    if spotlight_sceneitem ~= nil then
        obs.obs_sceneitem_set_visible(spotlight_sceneitem, false)
    end
end

---
-- Update spotlight position to follow mouse (always center on mouse)
function update_spotlight_position()
    if spotlight_sceneitem == nil or not is_spotlight_active then
        return
    end

    -- Use canvas coordinates for scene item positioning
    local mouse = get_mouse_canvas_pos()

    -- Get canvas dimensions for boundary detection
    local video_info = obs.obs_video_info()
    obs.obs_get_video_info(video_info)
    local canvas_width = video_info.base_width
    local canvas_height = video_info.base_height

    -- Check if mouse is within visible area (allow some margin)
    local margin = spotlight_radius * 2
    local in_bounds = mouse.x >= -margin and mouse.x <= canvas_width + margin
                  and mouse.y >= -margin and mouse.y <= canvas_height + margin

    if not in_bounds then
        -- Mouse is outside the frame, hide spotlight
        obs.obs_sceneitem_set_visible(spotlight_sceneitem, false)
        return
    else
        obs.obs_sceneitem_set_visible(spotlight_sceneitem, true)
    end

    -- Center the spotlight on mouse position
    local target_size = spotlight_radius * 4
    local pos = obs.vec2()
    pos.x = mouse.x - target_size / 2
    pos.y = mouse.y - target_size / 2

    obs.obs_sceneitem_set_pos(spotlight_sceneitem, pos)
end

---
-- Remove spotlight from scene and cleanup
function remove_spotlight()
    if spotlight_sceneitem ~= nil then
        -- Get the scene to remove from
        local scene_source = obs.obs_frontend_get_current_scene()
        if scene_source then
            local scene = obs.obs_scene_from_source(scene_source)
            if scene then
                obs.obs_sceneitem_remove(spotlight_sceneitem)
            end
            obs.obs_source_release(scene_source)
        end
        spotlight_sceneitem = nil
        log("Spotlight removed from scene")
    end

    if spotlight_source ~= nil then
        obs.obs_source_release(spotlight_source)
        spotlight_source = nil
    end
end

---
-- Hotkey callback for toggling spotlight
function on_toggle_spotlight(pressed)
    if pressed then
        is_spotlight_active = not is_spotlight_active
        log("Spotlight is " .. (is_spotlight_active and "on" or "off"))

        if zoom_state == ZoomState.ZoomedIn then
            if is_spotlight_active and use_spotlight then
                show_spotlight()
            else
                hide_spotlight()
            end
        end
    end
end

---
-- Anime-style easing functions for magnifier character
function anime_overshoot(t)
    -- Overshoots target then settles back (anime impact feel)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
end

function anime_elastic_out(t)
    -- Strong elastic bounce for dramatic entrance
    if t == 0 or t == 1 then return t end
    local p = 0.4
    return math.pow(2, -10 * t) * math.sin((t - p / 4) * (2 * math.pi) / p) + 1
end

function anime_back_out(t)
    -- Slight overshoot and settle
    local c1 = 1.70158
    return 1 + (c1 + 1) * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
end

---
-- Get the path for the cute character PNG
function get_character_path()
    local script_dir = get_script_path()
    if script_dir then
        return script_dir .. "Cute.png"
    end
    return nil
end

---
-- Create the character image source (loads Cute.png)
function create_magnifier_character_source()
    if magnifier_character_source ~= nil then
        return -- Already exists
    end

    -- Get path to Cute.png
    local char_path = get_character_path()
    if not char_path then
        log("ERROR: Could not determine script path for character")
        return
    end

    -- Check if file exists
    local f = io.open(char_path, "r")
    if f == nil then
        log("ERROR: Character file not found: " .. char_path)
        return
    end
    f:close()

    -- Create image source for the character
    local settings = obs.obs_data_create()
    obs.obs_data_set_string(settings, "file", char_path)
    magnifier_character_source = obs.obs_source_create_private("image_source", MAGNIFIER_CHARACTER_NAME, settings)
    obs.obs_data_release(settings)

    if magnifier_character_source then
        log("Character source created: " .. char_path)
    else
        log("ERROR: Failed to create character source")
    end
end

---
-- Add magnifier character to the current scene (purely decorative)
function add_magnifier_to_scene()
    if magnifier_character_sceneitem ~= nil then
        return -- Already added
    end

    local scene_source = obs.obs_frontend_get_current_scene()
    if scene_source == nil then
        return
    end

    local scene = obs.obs_scene_from_source(scene_source)
    if scene == nil then
        obs.obs_source_release(scene_source)
        return
    end

    -- Add character to scene
    if magnifier_character_source ~= nil then
        magnifier_character_sceneitem = obs.obs_scene_add(scene, magnifier_character_source)
        if magnifier_character_sceneitem then
            -- Get actual source dimensions for proper scaling
            local src_width = obs.obs_source_get_width(magnifier_character_source)
            local src_height = obs.obs_source_get_height(magnifier_character_source)

            -- Use source dimensions if available, otherwise default to 512
            if src_width == 0 then src_width = 512 end
            if src_height == 0 then src_height = 512 end

            local char_width = src_width * magnifier_scale
            local char_height = src_height * magnifier_scale

            local info = create_transform_info()
            get_sceneitem_info(magnifier_character_sceneitem, info)
            info.scale.x = magnifier_scale
            info.scale.y = magnifier_scale
            set_sceneitem_info(magnifier_character_sceneitem, info)

            obs.obs_sceneitem_set_order(magnifier_character_sceneitem, obs.OBS_ORDER_MOVE_TOP)
            obs.obs_sceneitem_set_visible(magnifier_character_sceneitem, false)

            log("Character added to scene: " .. src_width .. "x" .. src_height .. " scaled to " .. char_width .. "x" .. char_height)
        end
    end

    obs.obs_source_release(scene_source)
end

---
-- Calculate off-screen position for entrance animation
function get_magnifier_offscreen_pos(direction)
    local video_info = obs.obs_video_info()
    obs.obs_get_video_info(video_info)
    local canvas_width = video_info.base_width
    local canvas_height = video_info.base_height

    -- Get actual character dimensions
    local char_width = 512 * magnifier_scale
    local char_height = 512 * magnifier_scale

    if magnifier_character_source ~= nil then
        local src_w = obs.obs_source_get_width(magnifier_character_source)
        local src_h = obs.obs_source_get_height(magnifier_character_source)
        if src_w > 0 then char_width = src_w * magnifier_scale end
        if src_h > 0 then char_height = src_h * magnifier_scale end
    end

    if direction == "right" then
        return { x = canvas_width + 100, y = canvas_height / 2 - char_height / 2 }
    elseif direction == "left" then
        return { x = -char_width - 100, y = canvas_height / 2 - char_height / 2 }
    elseif direction == "top" then
        return { x = canvas_width / 2 - char_width / 2, y = -char_height - 100 }
    elseif direction == "bottom" then
        return { x = canvas_width / 2 - char_width / 2, y = canvas_height + 100 }
    end
    return { x = canvas_width + 100, y = canvas_height / 2 }
end

---
-- Start the magnifier entrance animation
function start_magnifier_entrance()
    if not use_magnifier_character then
        return
    end

    -- Create source if needed
    create_magnifier_character_source()
    add_magnifier_to_scene()

    if magnifier_character_sceneitem == nil then
        return
    end

    -- Set initial position off-screen
    local offscreen = get_magnifier_offscreen_pos(magnifier_entry_direction)
    magnifier_current_pos.x = offscreen.x
    magnifier_current_pos.y = offscreen.y

    -- Update position
    update_magnifier_sceneitem_pos(magnifier_current_pos.x, magnifier_current_pos.y)

    -- Make visible
    obs.obs_sceneitem_set_visible(magnifier_character_sceneitem, true)

    -- Start animation
    magnifier_anim_state = MagnifierAnimState.EnteringSlide
    magnifier_anim_time = 0

    log("Magnifier entrance started from " .. magnifier_entry_direction)
end

---
-- Start the magnifier exit animation
function start_magnifier_exit()
    if magnifier_anim_state == MagnifierAnimState.Hidden then
        return
    end

    magnifier_anim_state = MagnifierAnimState.Exiting
    magnifier_anim_time = 0

    -- Set target to off-screen
    magnifier_target_pos = get_magnifier_offscreen_pos(magnifier_entry_direction)

    log("Magnifier exit started")
end

---
-- Update magnifier sceneitem position (purely decorative)
function update_magnifier_sceneitem_pos(x, y)
    if magnifier_character_sceneitem == nil then
        return
    end

    -- Position the character
    local char_pos = obs.vec2()
    char_pos.x = x
    char_pos.y = y
    obs.obs_sceneitem_set_pos(magnifier_character_sceneitem, char_pos)
end

---
-- Update magnifier animation and position each frame
function update_magnifier_animation()
    if magnifier_anim_state == MagnifierAnimState.Hidden then
        return
    end

    -- Use canvas coordinates for scene item positioning
    local mouse = get_mouse_canvas_pos()

    -- Get actual character dimensions
    local char_width = 512 * magnifier_scale
    local char_height = 512 * magnifier_scale

    if magnifier_character_source ~= nil then
        local src_w = obs.obs_source_get_width(magnifier_character_source)
        local src_h = obs.obs_source_get_height(magnifier_character_source)
        if src_w > 0 then char_width = src_w * magnifier_scale end
        if src_h > 0 then char_height = src_h * magnifier_scale end
    end

    -- Calculate target position: anchor point follows mouse
    -- anchor 0% = left/top edge, 50% = center, 100% = right/bottom edge
    magnifier_target_pos.x = mouse.x - char_width * (character_anchor_x / 100)
    magnifier_target_pos.y = mouse.y - char_height * (character_anchor_y / 100)

    -- Clamp to screen bounds (allow partial off-screen)
    local video_info = obs.obs_video_info()
    obs.obs_get_video_info(video_info)
    magnifier_target_pos.x = clamp(-char_width * 0.3, video_info.base_width - char_width * 0.7, magnifier_target_pos.x)
    magnifier_target_pos.y = clamp(-char_height * 0.3, video_info.base_height - char_height * 0.7, magnifier_target_pos.y)

    if magnifier_anim_state == MagnifierAnimState.EnteringSlide then
        magnifier_anim_time = magnifier_anim_time + magnifier_anim_speed * 1.5 -- Faster slide

        local t = math.min(magnifier_anim_time, 1)
        local eased_t = anime_back_out(t)

        magnifier_current_pos.x = lerp(get_magnifier_offscreen_pos(magnifier_entry_direction).x, magnifier_target_pos.x, eased_t)
        magnifier_current_pos.y = lerp(get_magnifier_offscreen_pos(magnifier_entry_direction).y, magnifier_target_pos.y, eased_t)

        if magnifier_anim_time >= 1 then
            magnifier_anim_state = MagnifierAnimState.EnteringBounce
            magnifier_anim_time = 0
        end

    elseif magnifier_anim_state == MagnifierAnimState.EnteringBounce then
        magnifier_anim_time = magnifier_anim_time + magnifier_anim_speed * 2 -- Quick bounce

        if magnifier_anim_time >= 1 then
            magnifier_anim_state = MagnifierAnimState.Visible
            magnifier_current_pos.x = magnifier_target_pos.x
            magnifier_current_pos.y = magnifier_target_pos.y
        else
            -- Small elastic bounce
            local bounce = math.sin(magnifier_anim_time * math.pi * 2) * (1 - magnifier_anim_time) * 10
            magnifier_current_pos.x = magnifier_target_pos.x + bounce
            magnifier_current_pos.y = magnifier_target_pos.y
        end

    elseif magnifier_anim_state == MagnifierAnimState.Visible then
        -- Smooth follow mouse
        magnifier_current_pos.x = lerp(magnifier_current_pos.x, magnifier_target_pos.x, 0.15)
        magnifier_current_pos.y = lerp(magnifier_current_pos.y, magnifier_target_pos.y, 0.15)

    elseif magnifier_anim_state == MagnifierAnimState.Exiting then
        magnifier_anim_time = magnifier_anim_time + magnifier_anim_speed * 2 -- Fast exit

        local t = math.min(magnifier_anim_time, 1)
        -- Use ease-in for exit (accelerating out)
        local eased_t = t * t * t

        local exit_pos = get_magnifier_offscreen_pos(magnifier_entry_direction)
        local start_x = magnifier_current_pos.x
        local start_y = magnifier_current_pos.y

        if magnifier_anim_time < 0.1 then
            -- Store starting position
            magnifier_target_pos.x = magnifier_current_pos.x
            magnifier_target_pos.y = magnifier_current_pos.y
        end

        magnifier_current_pos.x = lerp(magnifier_target_pos.x, exit_pos.x, eased_t)
        magnifier_current_pos.y = lerp(magnifier_target_pos.y, exit_pos.y, eased_t)

        if magnifier_anim_time >= 1 then
            hide_magnifier()
            return
        end
    end

    -- Update position
    update_magnifier_sceneitem_pos(magnifier_current_pos.x, magnifier_current_pos.y)
end

---
-- Hide magnifier (make invisible, don't remove)
function hide_magnifier()
    if magnifier_character_sceneitem ~= nil then
        obs.obs_sceneitem_set_visible(magnifier_character_sceneitem, false)
    end
    magnifier_anim_state = MagnifierAnimState.Hidden
    log("Magnifier hidden")
end

---
-- Remove magnifier from scene and cleanup
function remove_magnifier()
    if magnifier_character_sceneitem ~= nil then
        obs.obs_sceneitem_remove(magnifier_character_sceneitem)
        magnifier_character_sceneitem = nil
    end

    if magnifier_character_source ~= nil then
        obs.obs_source_release(magnifier_character_source)
        magnifier_character_source = nil
    end

    magnifier_anim_state = MagnifierAnimState.Hidden
    log("Magnifier removed")
end

---
-- ============================================================================
-- Picture-in-Picture (PiP) System
-- ============================================================================

---
-- Calculate preset position coordinates based on canvas size
function get_pip_preset_position(preset, window_width, window_height)
    local video_info = obs.obs_video_info()
    obs.obs_get_video_info(video_info)
    local canvas_w = video_info.base_width
    local canvas_h = video_info.base_height
    local margin = 20

    local positions = {
        [PiPPosition.TopLeft] = { x = margin, y = margin },
        [PiPPosition.TopCenter] = { x = (canvas_w - window_width) / 2, y = margin },
        [PiPPosition.TopRight] = { x = canvas_w - window_width - margin, y = margin },
        [PiPPosition.MiddleLeft] = { x = margin, y = (canvas_h - window_height) / 2 },
        [PiPPosition.MiddleRight] = { x = canvas_w - window_width - margin, y = (canvas_h - window_height) / 2 },
        [PiPPosition.BottomLeft] = { x = margin, y = canvas_h - window_height - margin },
        [PiPPosition.BottomCenter] = { x = (canvas_w - window_width) / 2, y = canvas_h - window_height - margin },
        [PiPPosition.BottomRight] = { x = canvas_w - window_width - margin, y = canvas_h - window_height - margin },
    }

    return positions[preset] or { x = margin, y = margin }
end

---
-- Generate a border frame TGA image for PiP window
function generate_pip_border_tga(filepath, width, height, border_width, corner_radius)
    local file = io.open(filepath, "wb")
    if not file then
        log("ERROR: Failed to create PiP border TGA file: " .. filepath)
        return false
    end

    -- TGA Header (18 bytes)
    local header = string.char(
        0,          -- ID length
        0,          -- Color map type (none)
        2,          -- Image type (uncompressed true-color)
        0, 0,       -- Color map origin
        0, 0,       -- Color map length
        0,          -- Color map depth
        0, 0,       -- X origin
        0, 0,       -- Y origin
        width % 256, math.floor(width / 256),   -- Width (little-endian)
        height % 256, math.floor(height / 256), -- Height (little-endian)
        32,         -- Bits per pixel (BGRA)
        0x28        -- Image descriptor (top-left origin, 8 alpha bits)
    )
    file:write(header)

    -- Generate pixel data (BGRA format) - white border with rounded corners
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local is_border = false
            local alpha = 0

            -- Check if pixel is on the border
            local on_left = x < border_width
            local on_right = x >= width - border_width
            local on_top = y < border_width
            local on_bottom = y >= height - border_width

            if on_left or on_right or on_top or on_bottom then
                -- Check corner radius
                local in_corner = false
                local corner_dist = 0

                -- Top-left corner
                if x < corner_radius and y < corner_radius then
                    corner_dist = math.sqrt((corner_radius - x)^2 + (corner_radius - y)^2)
                    in_corner = corner_dist > corner_radius
                -- Top-right corner
                elseif x >= width - corner_radius and y < corner_radius then
                    corner_dist = math.sqrt((x - (width - corner_radius - 1))^2 + (corner_radius - y)^2)
                    in_corner = corner_dist > corner_radius
                -- Bottom-left corner
                elseif x < corner_radius and y >= height - corner_radius then
                    corner_dist = math.sqrt((corner_radius - x)^2 + (y - (height - corner_radius - 1))^2)
                    in_corner = corner_dist > corner_radius
                -- Bottom-right corner
                elseif x >= width - corner_radius and y >= height - corner_radius then
                    corner_dist = math.sqrt((x - (width - corner_radius - 1))^2 + (y - (height - corner_radius - 1))^2)
                    in_corner = corner_dist > corner_radius
                end

                if not in_corner then
                    is_border = true
                    alpha = 255
                end
            end

            if is_border then
                -- White border with full alpha
                file:write(string.char(255, 255, 255, alpha))
            else
                -- Transparent
                file:write(string.char(0, 0, 0, 0))
            end
        end
    end

    file:close()
    log("PiP border TGA generated: " .. filepath)
    return true
end

---
-- Create a PiP window source and add to scene
function create_pip_window(window)
    if window.source ~= nil then
        return -- Already exists
    end

    if source == nil then
        log("ERROR: Cannot create PiP window - main source not available")
        return
    end

    local window_id = window.id
    local pip_source_name = PIP_SOURCE_PREFIX .. window_id

    -- Clone the main source settings to create PiP source
    local main_source_id = obs.obs_source_get_id(source)
    local main_settings = obs.obs_source_get_settings(source)

    window.source = obs.obs_source_create_private(main_source_id, pip_source_name, main_settings)
    obs.obs_data_release(main_settings)

    if window.source == nil then
        log("ERROR: Failed to create PiP source " .. window_id)
        return
    end

    -- Create crop filter for this PiP window
    window.crop_settings = obs.obs_data_create()
    obs.obs_data_set_bool(window.crop_settings, "relative", false)
    window.crop_filter = obs.obs_source_create_private("crop_filter", pip_source_name .. "-crop", window.crop_settings)

    if window.crop_filter then
        obs.obs_source_filter_add(window.source, window.crop_filter)
    end

    log("PiP window " .. window_id .. " source created")
end

---
-- Add PiP window to the current scene
function add_pip_to_scene(window)
    if window.source == nil or window.sceneitem ~= nil then
        return
    end

    local scene_source = obs.obs_frontend_get_current_scene()
    if scene_source == nil then
        return
    end

    local scene = obs.obs_scene_from_source(scene_source)
    if scene == nil then
        obs.obs_source_release(scene_source)
        return
    end

    -- Add PiP source to scene
    window.sceneitem = obs.obs_scene_add(scene, window.source)

    if window.sceneitem then
        -- Calculate display position
        local pos = { x = window.display_x, y = window.display_y }
        if window.display_position ~= PiPPosition.Custom then
            pos = get_pip_preset_position(window.display_position, window.display_width, window.display_height)
        end

        -- Calculate scale based on source region and display size
        local scale_x = window.display_width / window.source_width
        local scale_y = window.display_height / window.source_height

        -- Set transform
        local info = create_transform_info()
        get_sceneitem_info(window.sceneitem, info)
        info.pos.x = pos.x
        info.pos.y = pos.y
        info.scale.x = scale_x
        info.scale.y = scale_y
        info.bounds_type = obs.OBS_BOUNDS_SCALE_INNER
        info.bounds.x = window.display_width
        info.bounds.y = window.display_height
        set_sceneitem_info(window.sceneitem, info)

        -- Move to top
        obs.obs_sceneitem_set_order(window.sceneitem, obs.OBS_ORDER_MOVE_TOP)
        obs.obs_sceneitem_set_visible(window.sceneitem, false)

        log("PiP window " .. window.id .. " added to scene at (" .. pos.x .. ", " .. pos.y .. ")")
    end

    -- Create and add border if enabled
    if window.border_enabled then
        create_pip_border(window)
    end

    obs.obs_source_release(scene_source)
end

---
-- Create border overlay for PiP window
function create_pip_border(window)
    if window.border_source ~= nil then
        return
    end

    local script_dir = get_script_path()
    if not script_dir then
        return
    end

    local border_path = script_dir .. "pip_border_" .. window.id .. ".tga"

    -- Generate border TGA
    if not generate_pip_border_tga(border_path,
                                    math.floor(window.display_width),
                                    math.floor(window.display_height),
                                    window.border_width,
                                    window.corner_radius) then
        return
    end

    -- Create image source for border
    local border_settings = obs.obs_data_create()
    obs.obs_data_set_string(border_settings, "file", border_path)
    window.border_source = obs.obs_source_create_private("image_source", PIP_BORDER_PREFIX .. window.id, border_settings)
    obs.obs_data_release(border_settings)

    if window.border_source == nil then
        return
    end

    -- Add to scene
    local scene_source = obs.obs_frontend_get_current_scene()
    if scene_source then
        local scene = obs.obs_scene_from_source(scene_source)
        if scene then
            window.border_sceneitem = obs.obs_scene_add(scene, window.border_source)

            if window.border_sceneitem then
                -- Position border at same location as PiP window
                local pos = { x = window.display_x, y = window.display_y }
                if window.display_position ~= PiPPosition.Custom then
                    pos = get_pip_preset_position(window.display_position, window.display_width, window.display_height)
                end

                local border_pos = obs.vec2()
                border_pos.x = pos.x
                border_pos.y = pos.y
                obs.obs_sceneitem_set_pos(window.border_sceneitem, border_pos)

                obs.obs_sceneitem_set_order(window.border_sceneitem, obs.OBS_ORDER_MOVE_TOP)
                obs.obs_sceneitem_set_visible(window.border_sceneitem, false)
            end
        end
        obs.obs_source_release(scene_source)
    end

    log("PiP border " .. window.id .. " created")
end

---
-- Update PiP window crop region based on mode
function update_pip_crop(window)
    if window.crop_filter == nil or window.crop_settings == nil then
        return
    end

    local target = window.target_crop

    if window.mode == PiPMode.FollowMouse then
        -- Get mouse position in source coordinates
        local mouse = get_mouse_pos()

        -- Apply monitor offset and scaling
        local monitor_x = (monitor_info and monitor_info.x) or 0
        local monitor_y = (monitor_info and monitor_info.y) or 0
        local sx = (monitor_info and monitor_info.scale_x) or 1
        local sy = (monitor_info and monitor_info.scale_y) or 1

        local source_mouse_x = (mouse.x - monitor_x) * sx
        local source_mouse_y = (mouse.y - monitor_y) * sy

        -- Apply offset from settings (allows each window to show different areas)
        source_mouse_x = source_mouse_x + window.source_offset_x
        source_mouse_y = source_mouse_y + window.source_offset_y

        -- Center the source region on the offset mouse position
        local half_w = window.source_width / 2
        local half_h = window.source_height / 2

        target.x = source_mouse_x - half_w
        target.y = source_mouse_y - half_h
        target.w = window.source_width
        target.h = window.source_height

        -- Clamp to source bounds
        local max_x = (zoom_info.source_size.width or 1920) - window.source_width
        local max_y = (zoom_info.source_size.height or 1080) - window.source_height
        target.x = clamp(0, max_x, target.x)
        target.y = clamp(0, max_y, target.y)

    elseif window.mode == PiPMode.FixedRegion then
        -- Use fixed source coordinates
        target.x = window.source_x
        target.y = window.source_y
        target.w = window.source_width
        target.h = window.source_height

    elseif window.mode == PiPMode.Locked then
        -- Keep current target (locked position)
        target.w = window.source_width
        target.h = window.source_height
    end

    -- Smooth interpolation
    local current = window.current_crop
    if window.smooth_follow and window.mode == PiPMode.FollowMouse then
        current.x = lerp(current.x, target.x, window.follow_speed)
        current.y = lerp(current.y, target.y, window.follow_speed)
    else
        current.x = target.x
        current.y = target.y
    end
    current.w = target.w
    current.h = target.h

    -- Apply crop filter settings
    obs.obs_data_set_int(window.crop_settings, "left", math.floor(current.x))
    obs.obs_data_set_int(window.crop_settings, "top", math.floor(current.y))
    obs.obs_data_set_int(window.crop_settings, "cx", math.floor(current.w))
    obs.obs_data_set_int(window.crop_settings, "cy", math.floor(current.h))
    obs.obs_source_update(window.crop_filter, window.crop_settings)
end

---
-- Show a PiP window
function show_pip_window(window)
    if window.sceneitem == nil then
        create_pip_window(window)
        add_pip_to_scene(window)
    end

    if window.sceneitem then
        obs.obs_sceneitem_set_visible(window.sceneitem, true)
        window.is_visible = true
    end

    if window.border_sceneitem then
        obs.obs_sceneitem_set_visible(window.border_sceneitem, true)
    end

    log("PiP window " .. window.id .. " shown")
end

---
-- Hide a PiP window
function hide_pip_window(window)
    if window.sceneitem then
        obs.obs_sceneitem_set_visible(window.sceneitem, false)
        window.is_visible = false
    end

    if window.border_sceneitem then
        obs.obs_sceneitem_set_visible(window.border_sceneitem, false)
    end

    log("PiP window " .. window.id .. " hidden")
end

---
-- Remove a PiP window completely
function remove_pip_window(window)
    -- Remove border
    if window.border_sceneitem then
        obs.obs_sceneitem_remove(window.border_sceneitem)
        window.border_sceneitem = nil
    end

    if window.border_source then
        obs.obs_source_release(window.border_source)
        window.border_source = nil
    end

    -- Remove crop filter
    if window.crop_filter and window.source then
        obs.obs_source_filter_remove(window.source, window.crop_filter)
        obs.obs_source_release(window.crop_filter)
        window.crop_filter = nil
    end

    if window.crop_settings then
        obs.obs_data_release(window.crop_settings)
        window.crop_settings = nil
    end

    -- Remove sceneitem
    if window.sceneitem then
        obs.obs_sceneitem_remove(window.sceneitem)
        window.sceneitem = nil
    end

    -- Release source
    if window.source then
        obs.obs_source_release(window.source)
        window.source = nil
    end

    window.is_visible = false
    log("PiP window " .. window.id .. " removed")
end

---
-- Show all enabled PiP windows
function show_all_pip_windows()
    if not use_pip then
        return
    end

    for i = 1, PIP_MAX_WINDOWS do
        local window = pip_windows[i]
        if window.enabled then
            show_pip_window(window)
        end
    end
end

---
-- Hide all PiP windows
function hide_all_pip_windows()
    for i = 1, PIP_MAX_WINDOWS do
        hide_pip_window(pip_windows[i])
    end
end

---
-- Remove all PiP windows
function remove_all_pip_windows()
    for i = 1, PIP_MAX_WINDOWS do
        remove_pip_window(pip_windows[i])
    end
end

---
-- Update all visible PiP windows
function update_all_pip_windows()
    if not use_pip then
        return
    end

    for i = 1, PIP_MAX_WINDOWS do
        local window = pip_windows[i]
        if window.enabled and window.is_visible then
            update_pip_crop(window)
        end
    end
end

---
-- Lock a PiP window at current mouse position
function lock_pip_window(window)
    if window.mode == PiPMode.FollowMouse then
        window.mode = PiPMode.Locked
        -- Current target becomes the locked position
        window.target_crop.x = window.current_crop.x
        window.target_crop.y = window.current_crop.y
        log("PiP window " .. window.id .. " locked at (" .. window.target_crop.x .. ", " .. window.target_crop.y .. ")")
    else
        -- Unlock - return to follow mouse
        window.mode = PiPMode.FollowMouse
        log("PiP window " .. window.id .. " unlocked")
    end
end

---
-- Hotkey callback for toggling individual PiP window
function create_pip_toggle_callback(window_id)
    return function(pressed)
        if pressed then
            local window = pip_windows[window_id]
            if window.is_visible then
                hide_pip_window(window)
            else
                show_pip_window(window)
            end
        end
    end
end

---
-- Hotkey callback for locking individual PiP window
function create_pip_lock_callback(window_id)
    return function(pressed)
        if pressed then
            lock_pip_window(pip_windows[window_id])
        end
    end
end

---
-- Hotkey callback for toggling all PiP windows
function on_toggle_all_pip(pressed)
    if pressed then
        local any_visible = false
        for i = 1, PIP_MAX_WINDOWS do
            if pip_windows[i].is_visible then
                any_visible = true
                break
            end
        end

        if any_visible then
            hide_all_pip_windows()
        else
            show_all_pip_windows()
        end
    end
end

---
-- ============================================================================
-- End of PiP System
-- ============================================================================

---
-- Get the size and position of the monitor
function get_monitor_info(source_to_check)
    local info = nil

    -- Only do the expensive look up if we are using automatic calculations on a display source
    if is_display_capture(source_to_check) and not use_monitor_override then
        local dc_info = get_dc_info()
        if dc_info ~= nil then
            local props = obs.obs_source_properties(source_to_check)
            if props ~= nil then
                local monitor_id_prop = obs.obs_properties_get(props, dc_info.prop_id)
                if monitor_id_prop then
                    local found = nil
                    local settings = obs.obs_source_get_settings(source_to_check)
                    if settings ~= nil then
                        local to_match
                        if dc_info.prop_type == "string" then
                            to_match = obs.obs_data_get_string(settings, dc_info.prop_id)
                        elseif dc_info.prop_type == "int" then
                            to_match = obs.obs_data_get_int(settings, dc_info.prop_id)
                        end

                        local item_count = obs.obs_property_list_item_count(monitor_id_prop)
                        for i = 0, item_count do
                            local name = obs.obs_property_list_item_name(monitor_id_prop, i)
                            local value
                            if dc_info.prop_type == "string" then
                                value = obs.obs_property_list_item_string(monitor_id_prop, i)
                            elseif dc_info.prop_type == "int" then
                                value = obs.obs_property_list_item_int(monitor_id_prop, i)
                            end

                            if value == to_match then
                                found = name
                                break
                            end
                        end
                        obs.obs_data_release(settings)
                    end

                    if found then
                        log("Parsing display name: " .. found)
                        local x, y = found:match("(-?%d+),(-?%d+)")
                        local width, height = found:match("(%d+)x(%d+)")

                        info = { x = 0, y = 0, width = 0, height = 0 }
                        info.x = tonumber(x, 10) or 0
                        info.y = tonumber(y, 10) or 0
                        info.width = tonumber(width, 10) or 0
                        info.height = tonumber(height, 10) or 0
                        info.scale_x = 1
                        info.scale_y = 1
                        info.display_width = info.width
                        info.display_height = info.height

                        log("Parsed display information\n" .. format_table(info))

                        if info.width == 0 and info.height == 0 then
                            info = nil
                        end
                    end
                end

                obs.obs_properties_destroy(props)
            end
        end
    end

    if use_monitor_override then
        info = {
            x = monitor_override_x,
            y = monitor_override_y,
            width = monitor_override_w,
            height = monitor_override_h,
            scale_x = monitor_override_sx,
            scale_y = monitor_override_sy,
            display_width = monitor_override_dw,
            display_height = monitor_override_dh
        }
    end

    if not info then
        log("WARNING: Could not auto calculate zoom source position and size.\n" ..
            "         Try using the 'Set manual source position' option and adding override values")
    end

    return info
end

---
-- Check to see if the specified source is a display capture source
function is_display_capture(source_to_check)
    if source_to_check ~= nil then
        local dc_info = get_dc_info()
        if dc_info ~= nil then
            if allow_all_sources then
                local source_type = obs.obs_source_get_id(source_to_check)
                if source_type == dc_info.source_id then
                    return true
                end
            else
                return true
            end
        end
    end

    return false
end

---
-- Releases the current sceneitem and resets data back to default
function release_sceneitem()
    if is_timer_running then
        obs.timer_remove(on_timer)
        is_timer_running = false
    end

    zoom_state = ZoomState.None

    if sceneitem ~= nil then
        if crop_filter ~= nil and source ~= nil then
            log("Zoom crop filter removed")
            obs.obs_source_filter_remove(source, crop_filter)
            obs.obs_source_release(crop_filter)
            crop_filter = nil
        end

        if crop_filter_temp ~= nil and source ~= nil then
            log("Conversion crop filter removed")
            obs.obs_source_filter_remove(source, crop_filter_temp)
            obs.obs_source_release(crop_filter_temp)
            crop_filter_temp = nil
        end

        if crop_filter_settings ~= nil then
            obs.obs_data_release(crop_filter_settings)
            crop_filter_settings = nil
        end

        if sceneitem_info_orig ~= nil then
            log("Transform info reset back to original")
            get_sceneitem_info(sceneitem, sceneitem_info_orig)
            sceneitem_info_orig = nil
        end

        if sceneitem_crop_orig ~= nil then
            log("Transform crop reset back to original")
            obs.obs_sceneitem_set_crop(sceneitem, sceneitem_crop_orig)
            sceneitem_crop_orig = nil
        end

        obs.obs_sceneitem_release(sceneitem)
        sceneitem = nil
    end

    if source ~= nil then
        obs.obs_source_release(source)
        source = nil
    end
end

---
-- Updates the current sceneitem with a refreshed set of data from the source
function refresh_sceneitem(find_newest)
    local source_raw = { width = 0, height = 0 }

    if find_newest then
        release_sceneitem()

        if source_name == "obs-mouse-zoom-none" then
            return
        end

        log("Finding sceneitem for Zoom Source '" .. source_name .. "'")
        if source_name ~= nil then
            source = obs.obs_get_source_by_name(source_name)
            if source ~= nil then
                source_raw.width = obs.obs_source_get_width(source)
                source_raw.height = obs.obs_source_get_height(source)

                local scene_source = obs.obs_frontend_get_current_scene()
                if scene_source ~= nil then
                    local function find_scene_item_by_name(root_scene)
                        local queue = {}
                        table.insert(queue, root_scene)

                        while #queue > 0 do
                            local s = table.remove(queue, 1)
                            log("Looking in scene '" .. obs.obs_source_get_name(obs.obs_scene_get_source(s)) .. "'")

                            local found = obs.obs_scene_find_source(s, source_name)
                            if found ~= nil then
                                log("Found sceneitem '" .. source_name .. "'")
                                obs.obs_sceneitem_addref(found)
                                return found
                            end

                            local all_items = obs.obs_scene_enum_items(s)
                            if all_items then
                                for _, item in pairs(all_items) do
                                    local nested = obs.obs_sceneitem_get_source(item)
                                    if nested ~= nil and obs.obs_source_is_scene(nested) then
                                        local nested_scene = obs.obs_scene_from_source(nested)
                                        table.insert(queue, nested_scene)
                                    end
                                end
                                obs.sceneitem_list_release(all_items)
                            end
                        end

                        return nil
                    end

                    local current = obs.obs_scene_from_source(scene_source)
                    sceneitem = find_scene_item_by_name(current)

                    obs.obs_source_release(scene_source)
                end

                if not sceneitem then
                    log("WARNING: Source not part of the current scene hierarchy.")
                    obs.obs_sceneitem_release(sceneitem)
                    obs.obs_source_release(source)

                    sceneitem = nil
                    source = nil
                    return
                end
            end
        end
    end

    if not monitor_info then
        monitor_info = get_monitor_info(source)
    end

    local is_non_display_capture = not is_display_capture(source)
    if is_non_display_capture then
        if not use_monitor_override then
            log("ERROR: Selected Zoom Source is not a display capture source.\n" ..
                "       You MUST enable 'Set manual source position' and set the correct override values.")
        end
    end

    if sceneitem ~= nil then
        sceneitem_info_orig = create_transform_info()
        get_sceneitem_info(sceneitem, sceneitem_info_orig)

        sceneitem_crop_orig = obs.obs_sceneitem_crop()
        obs.obs_sceneitem_get_crop(sceneitem, sceneitem_crop_orig)

        sceneitem_info = create_transform_info()
        get_sceneitem_info(sceneitem, sceneitem_info)

        sceneitem_crop = obs.obs_sceneitem_crop()
        obs.obs_sceneitem_get_crop(sceneitem, sceneitem_crop)

        if is_non_display_capture then
            sceneitem_crop_orig.left = 0
            sceneitem_crop_orig.top = 0
            sceneitem_crop_orig.right = 0
            sceneitem_crop_orig.bottom = 0
        end

        if not source then
            log("ERROR: Could not get source for sceneitem (" .. source_name .. ")")
        end

        local source_width = obs.obs_source_get_base_width(source)
        local source_height = obs.obs_source_get_base_height(source)

        if source_width == 0 then
            source_width = source_raw.width
        end
        if source_height == 0 then
            source_height = source_raw.height
        end

        if source_width == 0 or source_height == 0 then
            log("ERROR: Something went wrong determining source size.")
            if monitor_info ~= nil then
                source_width = monitor_info.width
                source_height = monitor_info.height
            end
        else
            log("Using source size: " .. source_width .. ", " .. source_height)
        end

        -- Auto-detect Retina scaling: if source pixels > display logical points, calculate scale factor
        if monitor_info ~= nil and monitor_info.width > 0 and monitor_info.height > 0 then
            local detected_scale_x = source_width / monitor_info.width
            local detected_scale_y = source_height / monitor_info.height

            -- Only apply if we detect a reasonable Retina scale (1.5x, 2x, 3x, etc.)
            if detected_scale_x >= 1.4 and detected_scale_x <= 3.5 then
                monitor_info.scale_x = detected_scale_x
                monitor_info.scale_y = detected_scale_y
                log(string.format("Retina scaling detected: %.2fx%.2f (source %dx%d / display %dx%d)",
                    detected_scale_x, detected_scale_y,
                    source_width, source_height,
                    monitor_info.width, monitor_info.height))
            end
        end

        -- Set up bounding box so cropped content scales to fill the original space
        if sceneitem_info.bounds_type == obs.OBS_BOUNDS_NONE then
            sceneitem_info.bounds_type = obs.OBS_BOUNDS_SCALE_INNER
            sceneitem_info.bounds_alignment = 0 -- OBS_ALIGN_CENTER
            sceneitem_info.bounds.x = source_width * sceneitem_info.scale.x
            sceneitem_info.bounds.y = source_height * sceneitem_info.scale.y

            set_sceneitem_info(sceneitem, sceneitem_info)

            log("Bounding box configured for zoom scaling: " .. sceneitem_info.bounds.x .. "x" .. sceneitem_info.bounds.y)
        end

        zoom_info.source_crop_filter = { x = 0, y = 0, w = 0, h = 0 }
        local found_crop_filter = false
        local filters = obs.obs_source_enum_filters(source)
        if filters ~= nil then
            for k, v in pairs(filters) do
                local id = obs.obs_source_get_id(v)
                if id == "crop_filter" then
                    local name = obs.obs_source_get_name(v)
                    if name ~= CROP_FILTER_NAME and name ~= "temp_" .. CROP_FILTER_NAME then
                        found_crop_filter = true
                        local settings = obs.obs_source_get_settings(v)
                        if settings ~= nil then
                            if not obs.obs_data_get_bool(settings, "relative") then
                                zoom_info.source_crop_filter.x =
                                    zoom_info.source_crop_filter.x + obs.obs_data_get_int(settings, "left")
                                zoom_info.source_crop_filter.y =
                                    zoom_info.source_crop_filter.y + obs.obs_data_get_int(settings, "top")
                                zoom_info.source_crop_filter.w =
                                    zoom_info.source_crop_filter.w + obs.obs_data_get_int(settings, "cx")
                                zoom_info.source_crop_filter.h =
                                    zoom_info.source_crop_filter.h + obs.obs_data_get_int(settings, "cy")
                                log("Found existing relative crop/pad filter (" .. name .. ")")
                            else
                                log("WARNING: Found existing non-relative crop/pad filter (" .. name .. ").")
                            end
                            obs.obs_data_release(settings)
                        end
                    end
                end
            end

            obs.source_list_release(filters)
        end

        if not found_crop_filter and (sceneitem_crop_orig.left ~= 0 or sceneitem_crop_orig.top ~= 0 or sceneitem_crop_orig.right ~= 0 or sceneitem_crop_orig.bottom ~= 0) then
            log("Creating new crop filter")

            source_width = source_width - (sceneitem_crop_orig.left + sceneitem_crop_orig.right)
            source_height = source_height - (sceneitem_crop_orig.top + sceneitem_crop_orig.bottom)

            zoom_info.source_crop_filter.x = sceneitem_crop_orig.left
            zoom_info.source_crop_filter.y = sceneitem_crop_orig.top
            zoom_info.source_crop_filter.w = source_width
            zoom_info.source_crop_filter.h = source_height

            local settings = obs.obs_data_create()
            obs.obs_data_set_bool(settings, "relative", false)
            obs.obs_data_set_int(settings, "left", zoom_info.source_crop_filter.x)
            obs.obs_data_set_int(settings, "top", zoom_info.source_crop_filter.y)
            obs.obs_data_set_int(settings, "cx", zoom_info.source_crop_filter.w)
            obs.obs_data_set_int(settings, "cy", zoom_info.source_crop_filter.h)
            crop_filter_temp = obs.obs_source_create_private("crop_filter", "temp_" .. CROP_FILTER_NAME, settings)
            obs.obs_source_filter_add(source, crop_filter_temp)
            obs.obs_data_release(settings)

            sceneitem_crop.left = 0
            sceneitem_crop.top = 0
            sceneitem_crop.right = 0
            sceneitem_crop.bottom = 0
            obs.obs_sceneitem_set_crop(sceneitem, sceneitem_crop)

            log("WARNING: Found existing transform crop. Auto converted to relative crop/pad filter.")
        elseif found_crop_filter then
            source_width = zoom_info.source_crop_filter.w
            source_height = zoom_info.source_crop_filter.h
        end

        zoom_info.source_size = { width = source_width, height = source_height }
        zoom_info.source_crop = {
            l = sceneitem_crop_orig.left,
            t = sceneitem_crop_orig.top,
            r = sceneitem_crop_orig.right,
            b = sceneitem_crop_orig.bottom
        }

        crop_filter_info_orig = { x = 0, y = 0, w = zoom_info.source_size.width, h = zoom_info.source_size.height }
        crop_filter_info = {
            x = crop_filter_info_orig.x,
            y = crop_filter_info_orig.y,
            w = crop_filter_info_orig.w,
            h = crop_filter_info_orig.h
        }

        crop_filter = obs.obs_source_get_filter_by_name(source, CROP_FILTER_NAME)
        if crop_filter == nil then
            crop_filter_settings = obs.obs_data_create()
            obs.obs_data_set_bool(crop_filter_settings, "relative", false)
            crop_filter = obs.obs_source_create_private("crop_filter", CROP_FILTER_NAME, crop_filter_settings)
            obs.obs_source_filter_add(source, crop_filter)
        else
            crop_filter_settings = obs.obs_source_get_settings(crop_filter)
        end

        obs.obs_source_filter_set_order(source, crop_filter, obs.OBS_ORDER_MOVE_BOTTOM)
        set_crop_settings(crop_filter_info_orig)
    end
end

---
-- Get the target position that we will attempt to zoom towards
function get_target_position(zoom)
    local mouse = get_mouse_pos()
    local raw_mouse_x, raw_mouse_y = mouse.x, mouse.y

    if monitor_info then
        mouse.x = mouse.x - monitor_info.x
        mouse.y = mouse.y - monitor_info.y
    end

    mouse.x = mouse.x - zoom.source_crop_filter.x
    mouse.y = mouse.y - zoom.source_crop_filter.y

    if monitor_info and monitor_info.scale_x and monitor_info.scale_y then
        mouse.x = mouse.x * monitor_info.scale_x
        mouse.y = mouse.y * monitor_info.scale_y
    end

    local new_size = {
        width = zoom.source_size.width / zoom.zoom_to,
        height = zoom.source_size.height / zoom.zoom_to
    }

    local pos = {
        x = mouse.x - new_size.width * 0.5,
        y = mouse.y - new_size.height * 0.5
    }

    local crop = {
        x = pos.x,
        y = pos.y,
        w = new_size.width,
        h = new_size.height,
    }

    crop.x = math.floor(clamp(0, (zoom.source_size.width - new_size.width), crop.x))
    crop.y = math.floor(clamp(0, (zoom.source_size.height - new_size.height), crop.y))

    log(string.format("[DIAG] raw_mouse=(%d,%d) adjusted=(%d,%d) source_size=(%d,%d) zoom_to=%.1f crop=(%d,%d,%d,%d)",
        raw_mouse_x, raw_mouse_y, mouse.x, mouse.y,
        zoom.source_size.width, zoom.source_size.height, zoom.zoom_to,
        crop.x, crop.y, crop.w, crop.h))

    return { crop = crop, raw_center = mouse, clamped_center = { x = math.floor(crop.x + crop.w * 0.5), y = math.floor(crop.y + crop.h * 0.5) } }
end

function on_toggle_follow(pressed)
    if pressed then
        is_following_mouse = not is_following_mouse
        log("Tracking mouse is " .. (is_following_mouse and "on" or "off"))

        if is_following_mouse and zoom_state == ZoomState.ZoomedIn then
            if is_timer_running == false then
                is_timer_running = true
                local timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
                obs.timer_add(on_timer, timer_interval)
            end
        end
    end
end

function on_toggle_zoom(pressed)
    if pressed then
        if zoom_state == ZoomState.ZoomedIn or zoom_state == ZoomState.None then
            if zoom_state == ZoomState.ZoomedIn then
                log("Zooming out")
                zoom_state = ZoomState.ZoomingOut
                zoom_time = 0
                locked_center = nil
                locked_last_pos = nil
                zoom_target = { crop = crop_filter_info_orig, c = sceneitem_crop_orig }
                if is_following_mouse then
                    is_following_mouse = false
                    log("Tracking mouse is off (due to zoom out)")
                end
                -- Hide spotlight when zooming out
                if use_spotlight then
                    hide_spotlight()
                end
                -- Start magnifier exit animation
                if use_magnifier_character then
                    start_magnifier_exit()
                end
                -- Hide PiP windows when zooming out
                if use_pip then
                    hide_all_pip_windows()
                end
            else
                log("Zooming in")
                log(string.format("[DIAG] zoom_info.source_size=(%d,%d) zoom_value=%.1f sceneitem=%s source=%s",
                    zoom_info.source_size.width, zoom_info.source_size.height, zoom_value,
                    tostring(sceneitem), tostring(source)))
                zoom_state = ZoomState.ZoomingIn
                zoom_info.zoom_to = zoom_value
                zoom_time = 0
                locked_center = nil
                locked_last_pos = nil
                zoom_target = get_target_position(zoom_info)

                -- Create vignette effect when zooming in
                if use_vignette_effect then
                    create_vignette_filter()
                end
                -- Create spotlight when zooming in
                if use_spotlight and is_spotlight_active then
                    create_spotlight_source()
                    add_spotlight_to_scene()
                end
                -- Start magnifier character entrance animation
                if use_magnifier_character then
                    start_magnifier_entrance()
                end
                -- Show PiP windows when zooming in
                if use_pip then
                    show_all_pip_windows()
                end
            end

            if is_timer_running == false then
                is_timer_running = true
                local timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
                obs.timer_add(on_timer, timer_interval)
            end
        end
    end
end

function on_timer()
    if crop_filter_info ~= nil and zoom_target ~= nil then
        zoom_time = zoom_time + zoom_speed

        if zoom_state == ZoomState.ZoomingOut or zoom_state == ZoomState.ZoomingIn then
            if zoom_time <= 1 then
                if zoom_state == ZoomState.ZoomingIn and use_auto_follow_mouse then
                    zoom_target = get_target_position(zoom_info)
                end
                local eased_time = get_easing(zoom_time)
                crop_filter_info.x = lerp(crop_filter_info.x, zoom_target.crop.x, eased_time)
                crop_filter_info.y = lerp(crop_filter_info.y, zoom_target.crop.y, eased_time)
                crop_filter_info.w = lerp(crop_filter_info.w, zoom_target.crop.w, eased_time)
                crop_filter_info.h = lerp(crop_filter_info.h, zoom_target.crop.h, eased_time)
                set_crop_settings(crop_filter_info)

                -- Update vignette effect during zoom animation
                if use_vignette_effect then
                    if zoom_state == ZoomState.ZoomingIn then
                        vignette_progress = eased_time
                    else
                        vignette_progress = 1 - eased_time
                    end
                    update_vignette_filter(vignette_progress)
                end

                -- Update spotlight position during zoom animation
                if use_spotlight and is_spotlight_active and zoom_state == ZoomState.ZoomingIn then
                    show_spotlight()
                    update_spotlight_position()
                end

                -- Update magnifier character animation during zoom
                if use_magnifier_character then
                    update_magnifier_animation()
                end
            end
        else
            if is_following_mouse then
                zoom_target = get_target_position(zoom_info)

                local skip_frame = false
                if not use_follow_outside_bounds then
                    if zoom_target.raw_center.x < zoom_target.crop.x or
                        zoom_target.raw_center.x > zoom_target.crop.x + zoom_target.crop.w or
                        zoom_target.raw_center.y < zoom_target.crop.y or
                        zoom_target.raw_center.y > zoom_target.crop.y + zoom_target.crop.h then
                        skip_frame = true
                    end
                end

                if not skip_frame then
                    if locked_center ~= nil then
                        local diff = {
                            x = zoom_target.raw_center.x - locked_center.x,
                            y = zoom_target.raw_center.y - locked_center.y
                        }

                        local track = {
                            x = zoom_target.crop.w * (0.5 - (follow_border * 0.01)),
                            y = zoom_target.crop.h * (0.5 - (follow_border * 0.01))
                        }

                        if math.abs(diff.x) > track.x or math.abs(diff.y) > track.y then
                            locked_center = nil
                            locked_last_pos = {
                                x = zoom_target.raw_center.x,
                                y = zoom_target.raw_center.y,
                                diff_x = diff.x,
                                diff_y = diff.y
                            }
                            log("Locked area exited - resume tracking")
                        end
                    end

                    if locked_center == nil and (zoom_target.crop.x ~= crop_filter_info.x or zoom_target.crop.y ~= crop_filter_info.y) then
                        crop_filter_info.x = lerp(crop_filter_info.x, zoom_target.crop.x, follow_speed)
                        crop_filter_info.y = lerp(crop_filter_info.y, zoom_target.crop.y, follow_speed)
                        set_crop_settings(crop_filter_info)

                        if is_following_mouse and locked_center == nil and locked_last_pos ~= nil then
                            local diff = {
                                x = math.abs(crop_filter_info.x - zoom_target.crop.x),
                                y = math.abs(crop_filter_info.y - zoom_target.crop.y),
                                auto_x = zoom_target.raw_center.x - locked_last_pos.x,
                                auto_y = zoom_target.raw_center.y - locked_last_pos.y
                            }

                            locked_last_pos.x = zoom_target.raw_center.x
                            locked_last_pos.y = zoom_target.raw_center.y

                            local lock = false
                            if math.abs(locked_last_pos.diff_x) > math.abs(locked_last_pos.diff_y) then
                                if (diff.auto_x < 0 and locked_last_pos.diff_x > 0) or (diff.auto_x > 0 and locked_last_pos.diff_x < 0) then
                                    lock = true
                                end
                            else
                                if (diff.auto_y < 0 and locked_last_pos.diff_y > 0) or (diff.auto_y > 0 and locked_last_pos.diff_y < 0) then
                                    lock = true
                                end
                            end

                            if (lock and use_follow_auto_lock) or (diff.x <= follow_safezone_sensitivity and diff.y <= follow_safezone_sensitivity) then
                                locked_center = {
                                    x = math.floor(crop_filter_info.x + zoom_target.crop.w * 0.5),
                                    y = math.floor(crop_filter_info.y + zoom_target.crop.h * 0.5)
                                }
                                log("Cursor stopped. Tracking locked to " .. locked_center.x .. ", " .. locked_center.y)
                            end
                        end
                    end
                end
            end

            -- Update spotlight position while zoomed in (regardless of mouse tracking)
            if use_spotlight and is_spotlight_active then
                update_spotlight_position()
            end

            -- Update magnifier character position while zoomed in
            if use_magnifier_character then
                update_magnifier_animation()
            end

            -- Update PiP windows while zoomed in
            if use_pip then
                update_all_pip_windows()
            end
        end

        if zoom_time >= 1 then
            local should_stop_timer = false
            if zoom_state == ZoomState.ZoomingOut then
                log("Zoomed out")
                zoom_state = ZoomState.None
                should_stop_timer = true

                -- Remove vignette effect when fully zoomed out
                if use_vignette_effect then
                    remove_vignette_filter()
                end
                -- Remove spotlight when fully zoomed out
                if use_spotlight then
                    remove_spotlight()
                end
                -- Remove magnifier character when fully zoomed out
                if use_magnifier_character then
                    remove_magnifier()
                end
                -- Remove PiP windows when fully zoomed out
                if use_pip then
                    remove_all_pip_windows()
                end
            elseif zoom_state == ZoomState.ZoomingIn then
                log("Zoomed in")
                zoom_state = ZoomState.ZoomedIn
                -- Keep timer running if mouse tracking OR spotlight OR magnifier OR PiP is active
                should_stop_timer = (not use_auto_follow_mouse) and (not is_following_mouse) and (not (use_spotlight and is_spotlight_active)) and (not use_magnifier_character) and (not use_pip)

                if use_auto_follow_mouse then
                    is_following_mouse = true
                    log("Tracking mouse is " .. (is_following_mouse and "on" or "off") .. " (due to auto follow)")
                end

                if is_following_mouse and follow_border < 50 then
                    zoom_target = get_target_position(zoom_info)
                    locked_center = { x = zoom_target.clamped_center.x, y = zoom_target.clamped_center.y }
                    log("Cursor stopped. Tracking locked to " .. locked_center.x .. ", " .. locked_center.y)
                end
            end

            -- Keep timer running if magnifier animation is still in progress
            if use_magnifier_character and magnifier_anim_state ~= MagnifierAnimState.Hidden and magnifier_anim_state ~= MagnifierAnimState.Visible then
                should_stop_timer = false
            end

            if should_stop_timer then
                is_timer_running = false
                obs.timer_remove(on_timer)
            end
        end
    end
end

function set_crop_settings(crop)
    if crop_filter ~= nil and crop_filter_settings ~= nil then
        obs.obs_data_set_int(crop_filter_settings, "left", math.floor(crop.x))
        obs.obs_data_set_int(crop_filter_settings, "top", math.floor(crop.y))
        obs.obs_data_set_int(crop_filter_settings, "cx", math.floor(crop.w))
        obs.obs_data_set_int(crop_filter_settings, "cy", math.floor(crop.h))
        obs.obs_source_update(crop_filter, crop_filter_settings)
    end
end

function on_transition_start(t)
    log("Transition started")
    -- Clean up spotlight before transition
    if spotlight_sceneitem ~= nil then
        hide_spotlight()
        spotlight_sceneitem = nil -- Will be re-added to new scene if needed
    end
    -- Clean up magnifier character before transition
    if magnifier_character_sceneitem ~= nil then
        hide_magnifier()
        magnifier_character_sceneitem = nil
    end
    -- Clean up PiP windows before transition
    for i = 1, PIP_MAX_WINDOWS do
        local window = pip_windows[i]
        if window.sceneitem ~= nil then
            window.sceneitem = nil
        end
        if window.border_sceneitem ~= nil then
            window.border_sceneitem = nil
        end
    end
    release_sceneitem()
end

function on_frontend_event(event)
    if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
        log("Scene changed")
        -- Clean up spotlight from old scene
        if spotlight_sceneitem ~= nil then
            spotlight_sceneitem = nil -- Old reference is invalid in new scene
        end
        -- Clean up magnifier from old scene
        if magnifier_character_sceneitem ~= nil then
            magnifier_character_sceneitem = nil
        end
        refresh_sceneitem(true)
        -- Re-add spotlight to new scene if we're zoomed in
        if zoom_state == ZoomState.ZoomedIn and use_spotlight and is_spotlight_active then
            add_spotlight_to_scene()
            show_spotlight()
        end
        -- Re-add magnifier to new scene if we're zoomed in
        if zoom_state == ZoomState.ZoomedIn and use_magnifier_character then
            add_magnifier_to_scene()
            if magnifier_character_sceneitem then
                obs.obs_sceneitem_set_visible(magnifier_character_sceneitem, true)
            end
            magnifier_anim_state = MagnifierAnimState.Visible
        end
        -- Re-add PiP windows to new scene if we're zoomed in
        if zoom_state == ZoomState.ZoomedIn and use_pip then
            for i = 1, PIP_MAX_WINDOWS do
                local window = pip_windows[i]
                if window.enabled and window.source ~= nil then
                    add_pip_to_scene(window)
                    if window.is_visible then
                        show_pip_window(window)
                    end
                end
            end
        end
    end
end

function on_settings_modified(props, prop, settings)
    local name = obs.obs_property_name(prop)

    if name == "use_monitor_override" then
        local visible = obs.obs_data_get_bool(settings, "use_monitor_override")
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_x"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_y"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_w"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_h"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_sx"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_sy"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_dw"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_dh"), visible)
        return true
    elseif name == "allow_all_sources" then
        local sources_list = obs.obs_properties_get(props, "source")
        populate_zoom_sources(sources_list)
        return true
    elseif name == "use_smooth_easing" then
        local visible = obs.obs_data_get_bool(settings, "use_smooth_easing")
        obs.obs_property_set_visible(obs.obs_properties_get(props, "easing_style"), visible)
        return true
    elseif name == "use_vignette_effect" then
        local visible = obs.obs_data_get_bool(settings, "use_vignette_effect")
        obs.obs_property_set_visible(obs.obs_properties_get(props, "vignette_intensity"), visible)
        return true
    elseif name == "use_spotlight" then
        local visible = obs.obs_data_get_bool(settings, "use_spotlight")
        obs.obs_property_set_visible(obs.obs_properties_get(props, "spotlight_radius"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "spotlight_opacity"), visible)
        return true
    elseif name == "use_magnifier_character" then
        local visible = obs.obs_data_get_bool(settings, "use_magnifier_character")
        obs.obs_property_set_visible(obs.obs_properties_get(props, "magnifier_scale"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "character_anchor_x"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "character_anchor_y"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "magnifier_entry_direction"), visible)
        return true
    elseif name == "debug_logs" then
        if obs.obs_data_get_bool(settings, "debug_logs") then
            log_current_settings()
        end
    end

    return false
end

function log_current_settings()
    local settings = {
        zoom_value = zoom_value,
        zoom_speed = zoom_speed,
        use_auto_follow_mouse = use_auto_follow_mouse,
        use_follow_outside_bounds = use_follow_outside_bounds,
        follow_speed = follow_speed,
        follow_border = follow_border,
        follow_safezone_sensitivity = follow_safezone_sensitivity,
        use_follow_auto_lock = use_follow_auto_lock,
        use_smooth_easing = use_smooth_easing,
        easing_style = easing_style,
        use_monitor_override = use_monitor_override,
        monitor_override_x = monitor_override_x,
        monitor_override_y = monitor_override_y,
        monitor_override_w = monitor_override_w,
        monitor_override_h = monitor_override_h,
        debug_logs = debug_logs,
        mouse_api_method = mouse_api_method,
        mouse_api_available = mouse_api_available,
        transform_api = use_new_transform_api and "v2 (OBS 31+)" or "v1 (legacy)"
    }

    log("OBS Version: " .. string.format("%.1f", major))
    log("Script Version: " .. VERSION)
    log("Transform API: " .. (use_new_transform_api and "v2 (OBS 31+)" or "v1 (legacy)"))
    log("Current settings:")
    log(format_table(settings))
end

function on_print_help()
    local help = "\n----------------------------------------------------\n" ..
        "Help Information for OBS Mouse Zoom v" .. VERSION .. "\n" ..
        "Enhanced version with macOS compatibility fixes\n" ..
        "----------------------------------------------------\n" ..
        "This script will zoom the selected display-capture source to focus on the mouse\n\n" ..
        "Mouse API Status: " .. mouse_api_method .. " (" .. (mouse_api_available and "Available" or "NOT Available") .. ")\n\n" ..
        "Zoom Source: The display capture in the current scene to use for zooming\n" ..
        "Zoom Factor: How much to zoom in by\n" ..
        "Zoom Speed: The speed of the zoom in/out animation\n" ..
        "Auto follow mouse: True to track the cursor while you are zoomed in\n" ..
        "Follow outside bounds: True to track the cursor even when it is outside the bounds of the source\n" ..
        "Follow Speed: The speed at which the zoomed area will follow the mouse when tracking\n" ..
        "Follow Border: The %distance from the edge of the source that will re-enable mouse tracking\n" ..
        "Lock Sensitivity: How close the tracking needs to get before it locks into position\n" ..
        "Smooth Easing: Use modern smooth easing animations\n" ..
        "Easing Style: Choose the type of animation curve (Smooth/Elastic/Bounce)\n" ..
        "Set manual source position: Override the calculated x/y, width/height for the selected source\n\n" ..
        "For macOS users:\n" ..
        "If the mouse API is not available, you may need to:\n" ..
        "1. Grant OBS accessibility permissions in System Preferences > Security & Privacy > Privacy > Accessibility\n" ..
        "2. Use 'Set manual source position' to configure your monitor settings manually\n\n"

    obs.script_log(obs.OBS_LOG_INFO, help)
end

function script_description()
    local status = mouse_api_available and "Ready" or "API NOT Available - Manual config required"
    return "Enhanced zoom script with mouse tracking (" .. mouse_api_method .. " - " .. status .. ")"
end

function script_properties()
    local props = obs.obs_properties_create()

    -- Status group
    local status_text = mouse_api_available and
        "Mouse API: " .. mouse_api_method .. " (Ready)" or
        "Mouse API: NOT AVAILABLE\nPlease enable 'Set manual source position' below."
    obs.obs_properties_add_text(props, "status_info", status_text, obs.OBS_TEXT_INFO)

    -- Source selection
    local sources_list = obs.obs_properties_add_list(props, "source", "Zoom Source", obs.OBS_COMBO_TYPE_LIST,
        obs.OBS_COMBO_FORMAT_STRING)
    populate_zoom_sources(sources_list)

    local refresh_sources = obs.obs_properties_add_button(props, "refresh", "Refresh zoom sources",
        function()
            populate_zoom_sources(sources_list)
            monitor_info = get_monitor_info(source)
            return true
        end)

    -- Zoom settings
    obs.obs_properties_add_float(props, "zoom_value", "Zoom Factor", 1.5, 8, 0.5)
    obs.obs_properties_add_float_slider(props, "zoom_speed", "Zoom Speed", 0.02, 0.5, 0.01)

    -- Follow settings
    local follow = obs.obs_properties_add_bool(props, "follow", "Auto follow mouse")
    obs.obs_property_set_long_description(follow,
        "When enabled, mouse tracking will auto-start when zoomed in")

    local follow_outside_bounds = obs.obs_properties_add_bool(props, "follow_outside_bounds", "Follow outside bounds")
    obs.obs_properties_add_float_slider(props, "follow_speed", "Follow Speed", 0.05, 0.5, 0.01)
    obs.obs_properties_add_int_slider(props, "follow_border", "Follow Border", 0, 50, 1)
    obs.obs_properties_add_int_slider(props, "follow_safezone_sensitivity", "Lock Sensitivity", 1, 20, 1)

    local follow_auto_lock = obs.obs_properties_add_bool(props, "follow_auto_lock", "Auto Lock on reverse direction")
    obs.obs_property_set_long_description(follow_auto_lock,
        "When enabled, moving mouse back towards center will stop tracking similar to RTS camera panning")

    -- Animation settings
    local smooth = obs.obs_properties_add_bool(props, "use_smooth_easing", "Use smooth modern easing")
    obs.obs_property_set_long_description(smooth, "Enable modern smooth animation curves")

    local easing = obs.obs_properties_add_list(props, "easing_style", "Easing Style", obs.OBS_COMBO_TYPE_LIST,
        obs.OBS_COMBO_FORMAT_INT)
    obs.obs_property_list_add_int(easing, "Smooth (Recommended)", 1)
    obs.obs_property_list_add_int(easing, "Elastic", 2)
    obs.obs_property_list_add_int(easing, "Bounce", 3)

    -- Visual Effects section
    obs.obs_properties_add_text(props, "effects_header", "--- Visual Effects ---", obs.OBS_TEXT_INFO)

    -- Vignette effect settings
    local vignette = obs.obs_properties_add_bool(props, "use_vignette_effect", "Enable focus effect (vignette)")
    obs.obs_property_set_long_description(vignette,
        "When zoomed in, increase contrast and saturation for a cinematic focus effect")

    local vignette_slider = obs.obs_properties_add_float_slider(props, "vignette_intensity", "Focus effect intensity", 0, 1, 0.1)
    obs.obs_property_set_long_description(vignette_slider, "How strong the contrast/saturation boost is")

    -- Spotlight effect settings (hidden - feature disabled)
    local spotlight = obs.obs_properties_add_bool(props, "use_spotlight", "Enable mouse spotlight")
    obs.obs_property_set_visible(spotlight, false)

    local spotlight_r = obs.obs_properties_add_int_slider(props, "spotlight_radius", "Spotlight radius", 100, 500, 10)
    obs.obs_property_set_visible(spotlight_r, false)

    local spotlight_o = obs.obs_properties_add_float_slider(props, "spotlight_opacity", "Spotlight darkness", 0.1, 0.8, 0.05)
    obs.obs_property_set_visible(spotlight_o, false)

    -- Magnifier Character section
    obs.obs_properties_add_text(props, "magnifier_header", "--- Character Overlay ---", obs.OBS_TEXT_INFO)

    local magnifier_char = obs.obs_properties_add_bool(props, "use_magnifier_character", "Enable character overlay")
    obs.obs_property_set_long_description(magnifier_char,
        "Show a cute character that follows the mouse during zoom (uses Cute.png)")

    local magnifier_scale_prop = obs.obs_properties_add_float_slider(props, "magnifier_scale", "Character scale", 0.1, 2.0, 0.05)
    obs.obs_property_set_long_description(magnifier_scale_prop, "Size of the character overlay")

    local anchor_x_prop = obs.obs_properties_add_int_slider(props, "character_anchor_x", "Anchor X (%)", 0, 100, 5)
    obs.obs_property_set_long_description(anchor_x_prop, "Which horizontal position of the character aligns with mouse (0=left, 50=center, 100=right)")

    local anchor_y_prop = obs.obs_properties_add_int_slider(props, "character_anchor_y", "Anchor Y (%)", 0, 100, 5)
    obs.obs_property_set_long_description(anchor_y_prop, "Which vertical position of the character aligns with mouse (0=top, 50=center, 100=bottom)")

    local magnifier_entry = obs.obs_properties_add_list(props, "magnifier_entry_direction", "Entry direction", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(magnifier_entry, "From Right", "right")
    obs.obs_property_list_add_string(magnifier_entry, "From Left", "left")
    obs.obs_property_list_add_string(magnifier_entry, "From Top", "top")
    obs.obs_property_list_add_string(magnifier_entry, "From Bottom", "bottom")
    obs.obs_property_set_long_description(magnifier_entry, "Direction from which the character enters")

    -- Picture-in-Picture section
    obs.obs_properties_add_text(props, "pip_header", "--- Picture-in-Picture ---", obs.OBS_TEXT_INFO)

    local pip_enable = obs.obs_properties_add_bool(props, "use_pip", "Enable Picture-in-Picture")
    obs.obs_property_set_long_description(pip_enable,
        "Show magnified PiP windows when zoomed in")

    -- PiP Window 1
    obs.obs_properties_add_text(props, "pip1_header", "PiP Window 1", obs.OBS_TEXT_INFO)

    local pip1_enabled = obs.obs_properties_add_bool(props, "pip1_enabled", "Enable Window 1")

    local pip1_mode = obs.obs_properties_add_list(props, "pip1_mode", "Mode", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    obs.obs_property_list_add_int(pip1_mode, "Follow Mouse", 1)
    obs.obs_property_list_add_int(pip1_mode, "Fixed Region", 2)

    local pip1_position = obs.obs_properties_add_list(props, "pip1_position", "Display Position", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    obs.obs_property_list_add_int(pip1_position, "Top Left", 1)
    obs.obs_property_list_add_int(pip1_position, "Top Center", 2)
    obs.obs_property_list_add_int(pip1_position, "Top Right", 3)
    obs.obs_property_list_add_int(pip1_position, "Middle Left", 4)
    obs.obs_property_list_add_int(pip1_position, "Middle Right", 5)
    obs.obs_property_list_add_int(pip1_position, "Bottom Left", 6)
    obs.obs_property_list_add_int(pip1_position, "Bottom Center", 7)
    obs.obs_property_list_add_int(pip1_position, "Bottom Right", 8)

    local pip1_zoom = obs.obs_properties_add_float_slider(props, "pip1_zoom", "Zoom Factor", 1.5, 5, 0.5)
    local pip1_width = obs.obs_properties_add_int(props, "pip1_width", "Display Width", 100, 800, 10)
    local pip1_height = obs.obs_properties_add_int(props, "pip1_height", "Display Height", 100, 600, 10)

    local pip1_offset_x = obs.obs_properties_add_int(props, "pip1_offset_x", "Offset X (Follow Mouse)", -5000, 5000, 50)
    obs.obs_property_set_long_description(pip1_offset_x, "Horizontal offset from mouse position (pixels in source coordinates)")
    local pip1_offset_y = obs.obs_properties_add_int(props, "pip1_offset_y", "Offset Y (Follow Mouse)", -5000, 5000, 50)
    obs.obs_property_set_long_description(pip1_offset_y, "Vertical offset from mouse position (pixels in source coordinates)")

    local pip1_source_x = obs.obs_properties_add_int(props, "pip1_source_x", "Source X (Fixed Region)", 0, 10000, 10)
    obs.obs_property_set_long_description(pip1_source_x, "X position of the fixed region to monitor")
    local pip1_source_y = obs.obs_properties_add_int(props, "pip1_source_y", "Source Y (Fixed Region)", 0, 10000, 10)
    obs.obs_property_set_long_description(pip1_source_y, "Y position of the fixed region to monitor")

    local pip1_border = obs.obs_properties_add_bool(props, "pip1_border", "Show Border")

    -- PiP Window 2
    obs.obs_properties_add_text(props, "pip2_header", "PiP Window 2", obs.OBS_TEXT_INFO)

    local pip2_enabled = obs.obs_properties_add_bool(props, "pip2_enabled", "Enable Window 2")

    local pip2_mode = obs.obs_properties_add_list(props, "pip2_mode", "Mode", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    obs.obs_property_list_add_int(pip2_mode, "Follow Mouse", 1)
    obs.obs_property_list_add_int(pip2_mode, "Fixed Region", 2)

    local pip2_position = obs.obs_properties_add_list(props, "pip2_position", "Display Position", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    obs.obs_property_list_add_int(pip2_position, "Top Left", 1)
    obs.obs_property_list_add_int(pip2_position, "Top Center", 2)
    obs.obs_property_list_add_int(pip2_position, "Top Right", 3)
    obs.obs_property_list_add_int(pip2_position, "Middle Left", 4)
    obs.obs_property_list_add_int(pip2_position, "Middle Right", 5)
    obs.obs_property_list_add_int(pip2_position, "Bottom Left", 6)
    obs.obs_property_list_add_int(pip2_position, "Bottom Center", 7)
    obs.obs_property_list_add_int(pip2_position, "Bottom Right", 8)

    local pip2_zoom = obs.obs_properties_add_float_slider(props, "pip2_zoom", "Zoom Factor", 1.5, 5, 0.5)
    local pip2_width = obs.obs_properties_add_int(props, "pip2_width", "Display Width", 100, 800, 10)
    local pip2_height = obs.obs_properties_add_int(props, "pip2_height", "Display Height", 100, 600, 10)

    local pip2_offset_x = obs.obs_properties_add_int(props, "pip2_offset_x", "Offset X (Follow Mouse)", -5000, 5000, 50)
    obs.obs_property_set_long_description(pip2_offset_x, "Horizontal offset from mouse position (pixels in source coordinates)")
    local pip2_offset_y = obs.obs_properties_add_int(props, "pip2_offset_y", "Offset Y (Follow Mouse)", -5000, 5000, 50)
    obs.obs_property_set_long_description(pip2_offset_y, "Vertical offset from mouse position (pixels in source coordinates)")

    local pip2_source_x = obs.obs_properties_add_int(props, "pip2_source_x", "Source X (Fixed Region)", 0, 10000, 10)
    obs.obs_property_set_long_description(pip2_source_x, "X position of the fixed region to monitor")
    local pip2_source_y = obs.obs_properties_add_int(props, "pip2_source_y", "Source Y (Fixed Region)", 0, 10000, 10)
    obs.obs_property_set_long_description(pip2_source_y, "Y position of the fixed region to monitor")

    local pip2_border = obs.obs_properties_add_bool(props, "pip2_border", "Show Border")

    -- PiP Window 3
    obs.obs_properties_add_text(props, "pip3_header", "PiP Window 3", obs.OBS_TEXT_INFO)

    local pip3_enabled = obs.obs_properties_add_bool(props, "pip3_enabled", "Enable Window 3")

    local pip3_mode = obs.obs_properties_add_list(props, "pip3_mode", "Mode", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    obs.obs_property_list_add_int(pip3_mode, "Follow Mouse", 1)
    obs.obs_property_list_add_int(pip3_mode, "Fixed Region", 2)

    local pip3_position = obs.obs_properties_add_list(props, "pip3_position", "Display Position", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    obs.obs_property_list_add_int(pip3_position, "Top Left", 1)
    obs.obs_property_list_add_int(pip3_position, "Top Center", 2)
    obs.obs_property_list_add_int(pip3_position, "Top Right", 3)
    obs.obs_property_list_add_int(pip3_position, "Middle Left", 4)
    obs.obs_property_list_add_int(pip3_position, "Middle Right", 5)
    obs.obs_property_list_add_int(pip3_position, "Bottom Left", 6)
    obs.obs_property_list_add_int(pip3_position, "Bottom Center", 7)
    obs.obs_property_list_add_int(pip3_position, "Bottom Right", 8)

    local pip3_zoom = obs.obs_properties_add_float_slider(props, "pip3_zoom", "Zoom Factor", 1.5, 5, 0.5)
    local pip3_width = obs.obs_properties_add_int(props, "pip3_width", "Display Width", 100, 800, 10)
    local pip3_height = obs.obs_properties_add_int(props, "pip3_height", "Display Height", 100, 600, 10)

    local pip3_offset_x = obs.obs_properties_add_int(props, "pip3_offset_x", "Offset X (Follow Mouse)", -5000, 5000, 50)
    obs.obs_property_set_long_description(pip3_offset_x, "Horizontal offset from mouse position (pixels in source coordinates)")
    local pip3_offset_y = obs.obs_properties_add_int(props, "pip3_offset_y", "Offset Y (Follow Mouse)", -5000, 5000, 50)
    obs.obs_property_set_long_description(pip3_offset_y, "Vertical offset from mouse position (pixels in source coordinates)")

    local pip3_source_x = obs.obs_properties_add_int(props, "pip3_source_x", "Source X (Fixed Region)", 0, 10000, 10)
    obs.obs_property_set_long_description(pip3_source_x, "X position of the fixed region to monitor")
    local pip3_source_y = obs.obs_properties_add_int(props, "pip3_source_y", "Source Y (Fixed Region)", 0, 10000, 10)
    obs.obs_property_set_long_description(pip3_source_y, "Y position of the fixed region to monitor")

    local pip3_border = obs.obs_properties_add_bool(props, "pip3_border", "Show Border")

    -- Source settings
    local allow_all = obs.obs_properties_add_bool(props, "allow_all_sources", "Allow any zoom source")

    local override = obs.obs_properties_add_bool(props, "use_monitor_override", "Set manual source position")
    obs.obs_property_set_long_description(override,
        "REQUIRED if mouse API is not available or using non-display capture sources")

    local override_x = obs.obs_properties_add_int(props, "monitor_override_x", "X", -10000, 10000, 1)
    local override_y = obs.obs_properties_add_int(props, "monitor_override_y", "Y", -10000, 10000, 1)
    local override_w = obs.obs_properties_add_int(props, "monitor_override_w", "Width", 0, 10000, 1)
    local override_h = obs.obs_properties_add_int(props, "monitor_override_h", "Height", 0, 10000, 1)
    local override_sx = obs.obs_properties_add_float(props, "monitor_override_sx", "Scale X", 0, 100, 0.01)
    local override_sy = obs.obs_properties_add_float(props, "monitor_override_sy", "Scale Y", 0, 100, 0.01)
    local override_dw = obs.obs_properties_add_int(props, "monitor_override_dw", "Monitor Width", 0, 10000, 1)
    local override_dh = obs.obs_properties_add_int(props, "monitor_override_dh", "Monitor Height", 0, 10000, 1)

    -- Help and debug
    local help = obs.obs_properties_add_button(props, "help_button", "More Info", on_print_help)
    local debug = obs.obs_properties_add_bool(props, "debug_logs", "Enable debug logging")

    -- Set visibility
    obs.obs_property_set_visible(override_x, use_monitor_override)
    obs.obs_property_set_visible(override_y, use_monitor_override)
    obs.obs_property_set_visible(override_w, use_monitor_override)
    obs.obs_property_set_visible(override_h, use_monitor_override)
    obs.obs_property_set_visible(override_sx, use_monitor_override)
    obs.obs_property_set_visible(override_sy, use_monitor_override)
    obs.obs_property_set_visible(override_dw, use_monitor_override)
    obs.obs_property_set_visible(override_dh, use_monitor_override)
    obs.obs_property_set_visible(easing, use_smooth_easing)
    obs.obs_property_set_visible(vignette_slider, use_vignette_effect)
    obs.obs_property_set_visible(spotlight_r, use_spotlight)
    obs.obs_property_set_visible(spotlight_o, use_spotlight)
    obs.obs_property_set_visible(magnifier_scale_prop, use_magnifier_character)
    obs.obs_property_set_visible(anchor_x_prop, use_magnifier_character)
    obs.obs_property_set_visible(anchor_y_prop, use_magnifier_character)
    obs.obs_property_set_visible(magnifier_entry, use_magnifier_character)

    -- Set callbacks
    obs.obs_property_set_modified_callback(override, on_settings_modified)
    obs.obs_property_set_modified_callback(allow_all, on_settings_modified)
    obs.obs_property_set_modified_callback(smooth, on_settings_modified)
    obs.obs_property_set_modified_callback(debug, on_settings_modified)
    obs.obs_property_set_modified_callback(vignette, on_settings_modified)
    obs.obs_property_set_modified_callback(spotlight, on_settings_modified)
    obs.obs_property_set_modified_callback(magnifier_char, on_settings_modified)

    return props
end

function script_load(settings)
    sceneitem_info_orig = nil

    -- Initialize mouse API first
    init_mouse_api()

    -- Add hotkeys
    hotkey_zoom_id = obs.obs_hotkey_register_frontend("toggle_zoom_hotkey", "Toggle zoom to mouse",
        on_toggle_zoom)

    hotkey_follow_id = obs.obs_hotkey_register_frontend("toggle_follow_hotkey", "Toggle follow mouse during zoom",
        on_toggle_follow)

    hotkey_spotlight_id = obs.obs_hotkey_register_frontend("toggle_spotlight_hotkey", "Toggle spotlight during zoom",
        on_toggle_spotlight)

    -- Register PiP hotkeys
    for i = 1, PIP_MAX_WINDOWS do
        pip_hotkey_toggle[i] = obs.obs_hotkey_register_frontend(
            "toggle_pip_window_" .. i,
            "Toggle PiP Window " .. i,
            create_pip_toggle_callback(i))
        pip_hotkey_lock[i] = obs.obs_hotkey_register_frontend(
            "lock_pip_window_" .. i,
            "Lock PiP Window " .. i,
            create_pip_lock_callback(i))
    end
    pip_hotkey_all = obs.obs_hotkey_register_frontend("toggle_all_pip", "Toggle All PiP Windows", on_toggle_all_pip)

    -- Load hotkey bindings
    local hotkey_save_array = obs.obs_data_get_array(settings, "obs_mouse_zoom.hotkey.zoom")
    obs.obs_hotkey_load(hotkey_zoom_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_data_get_array(settings, "obs_mouse_zoom.hotkey.follow")
    obs.obs_hotkey_load(hotkey_follow_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_data_get_array(settings, "obs_mouse_zoom.hotkey.spotlight")
    obs.obs_hotkey_load(hotkey_spotlight_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    -- Load PiP hotkey bindings
    for i = 1, PIP_MAX_WINDOWS do
        hotkey_save_array = obs.obs_data_get_array(settings, "obs_mouse_zoom.hotkey.pip_toggle_" .. i)
        if pip_hotkey_toggle[i] then
            obs.obs_hotkey_load(pip_hotkey_toggle[i], hotkey_save_array)
        end
        obs.obs_data_array_release(hotkey_save_array)

        hotkey_save_array = obs.obs_data_get_array(settings, "obs_mouse_zoom.hotkey.pip_lock_" .. i)
        if pip_hotkey_lock[i] then
            obs.obs_hotkey_load(pip_hotkey_lock[i], hotkey_save_array)
        end
        obs.obs_data_array_release(hotkey_save_array)
    end
    hotkey_save_array = obs.obs_data_get_array(settings, "obs_mouse_zoom.hotkey.pip_all")
    if pip_hotkey_all then
        obs.obs_hotkey_load(pip_hotkey_all, hotkey_save_array)
    end
    obs.obs_data_array_release(hotkey_save_array)

    -- Load settings
    zoom_value = obs.obs_data_get_double(settings, "zoom_value")
    zoom_speed = obs.obs_data_get_double(settings, "zoom_speed")
    use_auto_follow_mouse = obs.obs_data_get_bool(settings, "follow")
    use_follow_outside_bounds = obs.obs_data_get_bool(settings, "follow_outside_bounds")
    follow_speed = obs.obs_data_get_double(settings, "follow_speed")
    follow_border = obs.obs_data_get_int(settings, "follow_border")
    follow_safezone_sensitivity = obs.obs_data_get_int(settings, "follow_safezone_sensitivity")
    use_follow_auto_lock = obs.obs_data_get_bool(settings, "follow_auto_lock")
    use_smooth_easing = obs.obs_data_get_bool(settings, "use_smooth_easing")
    easing_style = obs.obs_data_get_int(settings, "easing_style")

    -- Load effect settings
    use_vignette_effect = obs.obs_data_get_bool(settings, "use_vignette_effect")
    vignette_intensity = obs.obs_data_get_double(settings, "vignette_intensity")
    use_spotlight = obs.obs_data_get_bool(settings, "use_spotlight")
    spotlight_radius = obs.obs_data_get_int(settings, "spotlight_radius")
    spotlight_opacity = obs.obs_data_get_double(settings, "spotlight_opacity")

    -- Load magnifier character settings
    use_magnifier_character = obs.obs_data_get_bool(settings, "use_magnifier_character")
    magnifier_scale = obs.obs_data_get_double(settings, "magnifier_scale")
    character_anchor_x = obs.obs_data_get_int(settings, "character_anchor_x")
    character_anchor_y = obs.obs_data_get_int(settings, "character_anchor_y")
    magnifier_entry_direction = obs.obs_data_get_string(settings, "magnifier_entry_direction")

    -- Load PiP settings
    use_pip = obs.obs_data_get_bool(settings, "use_pip")
    for i = 1, PIP_MAX_WINDOWS do
        local window = pip_windows[i]
        local prefix = "pip" .. i .. "_"
        window.enabled = obs.obs_data_get_bool(settings, prefix .. "enabled")
        window.mode = obs.obs_data_get_int(settings, prefix .. "mode")
        window.display_position = obs.obs_data_get_int(settings, prefix .. "position")
        window.zoom_factor = obs.obs_data_get_double(settings, prefix .. "zoom")
        window.display_width = obs.obs_data_get_int(settings, prefix .. "width")
        window.display_height = obs.obs_data_get_int(settings, prefix .. "height")
        window.border_enabled = obs.obs_data_get_bool(settings, prefix .. "border")
        window.source_offset_x = obs.obs_data_get_int(settings, prefix .. "offset_x")
        window.source_offset_y = obs.obs_data_get_int(settings, prefix .. "offset_y")
        window.source_x = obs.obs_data_get_int(settings, prefix .. "source_x")
        window.source_y = obs.obs_data_get_int(settings, prefix .. "source_y")
        window.source_width = window.display_width * window.zoom_factor
        window.source_height = window.display_height * window.zoom_factor
    end

    allow_all_sources = obs.obs_data_get_bool(settings, "allow_all_sources")
    use_monitor_override = obs.obs_data_get_bool(settings, "use_monitor_override")
    monitor_override_x = obs.obs_data_get_int(settings, "monitor_override_x")
    monitor_override_y = obs.obs_data_get_int(settings, "monitor_override_y")
    monitor_override_w = obs.obs_data_get_int(settings, "monitor_override_w")
    monitor_override_h = obs.obs_data_get_int(settings, "monitor_override_h")
    monitor_override_sx = obs.obs_data_get_double(settings, "monitor_override_sx")
    monitor_override_sy = obs.obs_data_get_double(settings, "monitor_override_sy")
    monitor_override_dw = obs.obs_data_get_int(settings, "monitor_override_dw")
    monitor_override_dh = obs.obs_data_get_int(settings, "monitor_override_dh")
    debug_logs = obs.obs_data_get_bool(settings, "debug_logs")

    obs.obs_frontend_add_event_callback(on_frontend_event)

    if debug_logs then
        log_current_settings()
    end

    -- Add transition handlers
    local transitions = obs.obs_frontend_get_transitions()
    if transitions ~= nil then
        for i, s in pairs(transitions) do
            local name = obs.obs_source_get_name(s)
            log("Adding transition_start listener to " .. name)
            local handler = obs.obs_source_get_signal_handler(s)
            obs.signal_handler_connect(handler, "transition_start", on_transition_start)
        end
        obs.source_list_release(transitions)
    end

    -- Log status
    if not mouse_api_available then
        obs.script_log(obs.OBS_LOG_WARNING,
            "Mouse API not available. Please enable 'Set manual source position' and configure your monitor settings.")
    end
end

function script_unload()
    -- Clean up effects first
    remove_vignette_filter()
    remove_spotlight()
    remove_magnifier()
    remove_all_pip_windows()

    if major > 29.0 then
        local transitions = obs.obs_frontend_get_transitions()
        if transitions ~= nil then
            for i, s in pairs(transitions) do
                local handler = obs.obs_source_get_signal_handler(s)
                obs.signal_handler_disconnect(handler, "transition_start", on_transition_start)
            end
            obs.source_list_release(transitions)
        end

        obs.obs_hotkey_unregister(on_toggle_zoom)
        obs.obs_hotkey_unregister(on_toggle_follow)
        obs.obs_hotkey_unregister(on_toggle_spotlight)
        obs.obs_frontend_remove_event_callback(on_frontend_event)
        release_sceneitem()
    end

    if x11_mouse and x11_mouse.lib and x11_display then
        x11_mouse.lib.XCloseDisplay(x11_display)
    end
end

function script_defaults(settings)
    obs.obs_data_set_default_double(settings, "zoom_value", 2)
    obs.obs_data_set_default_double(settings, "zoom_speed", 0.08)
    obs.obs_data_set_default_bool(settings, "follow", true)
    obs.obs_data_set_default_bool(settings, "follow_outside_bounds", false)
    obs.obs_data_set_default_double(settings, "follow_speed", 0.15)
    obs.obs_data_set_default_int(settings, "follow_border", 8)
    obs.obs_data_set_default_int(settings, "follow_safezone_sensitivity", 6)
    obs.obs_data_set_default_bool(settings, "follow_auto_lock", false)
    obs.obs_data_set_default_bool(settings, "use_smooth_easing", true)
    obs.obs_data_set_default_int(settings, "easing_style", 1)

    -- Effect defaults
    obs.obs_data_set_default_bool(settings, "use_vignette_effect", true)
    obs.obs_data_set_default_double(settings, "vignette_intensity", 0.5)
    obs.obs_data_set_default_bool(settings, "use_spotlight", false)
    obs.obs_data_set_default_int(settings, "spotlight_radius", 200)
    obs.obs_data_set_default_double(settings, "spotlight_opacity", 0.4)

    -- Magnifier character defaults
    obs.obs_data_set_default_bool(settings, "use_magnifier_character", true)
    obs.obs_data_set_default_double(settings, "magnifier_scale", 0.5)
    obs.obs_data_set_default_int(settings, "character_anchor_x", 0)
    obs.obs_data_set_default_int(settings, "character_anchor_y", 0)
    obs.obs_data_set_default_string(settings, "magnifier_entry_direction", "right")

    -- PiP defaults
    obs.obs_data_set_default_bool(settings, "use_pip", false)

    -- PiP Window 1 defaults
    obs.obs_data_set_default_bool(settings, "pip1_enabled", true)
    obs.obs_data_set_default_int(settings, "pip1_mode", 1)
    obs.obs_data_set_default_int(settings, "pip1_position", 3)  -- Top Right
    obs.obs_data_set_default_double(settings, "pip1_zoom", 2.5)
    obs.obs_data_set_default_int(settings, "pip1_width", 320)
    obs.obs_data_set_default_int(settings, "pip1_height", 240)
    obs.obs_data_set_default_int(settings, "pip1_offset_x", 0)
    obs.obs_data_set_default_int(settings, "pip1_offset_y", 0)
    obs.obs_data_set_default_int(settings, "pip1_source_x", 0)
    obs.obs_data_set_default_int(settings, "pip1_source_y", 0)
    obs.obs_data_set_default_bool(settings, "pip1_border", true)

    -- PiP Window 2 defaults (offset to the right of mouse)
    obs.obs_data_set_default_bool(settings, "pip2_enabled", false)
    obs.obs_data_set_default_int(settings, "pip2_mode", 1)
    obs.obs_data_set_default_int(settings, "pip2_position", 6)  -- Bottom Left
    obs.obs_data_set_default_double(settings, "pip2_zoom", 2.0)
    obs.obs_data_set_default_int(settings, "pip2_width", 320)
    obs.obs_data_set_default_int(settings, "pip2_height", 240)
    obs.obs_data_set_default_int(settings, "pip2_offset_x", 500)
    obs.obs_data_set_default_int(settings, "pip2_offset_y", 0)
    obs.obs_data_set_default_int(settings, "pip2_source_x", 0)
    obs.obs_data_set_default_int(settings, "pip2_source_y", 0)
    obs.obs_data_set_default_bool(settings, "pip2_border", true)

    -- PiP Window 3 defaults (offset below mouse)
    obs.obs_data_set_default_bool(settings, "pip3_enabled", false)
    obs.obs_data_set_default_int(settings, "pip3_mode", 1)
    obs.obs_data_set_default_int(settings, "pip3_position", 8)  -- Bottom Right
    obs.obs_data_set_default_double(settings, "pip3_zoom", 2.0)
    obs.obs_data_set_default_int(settings, "pip3_width", 320)
    obs.obs_data_set_default_int(settings, "pip3_height", 240)
    obs.obs_data_set_default_int(settings, "pip3_offset_x", 0)
    obs.obs_data_set_default_int(settings, "pip3_offset_y", 500)
    obs.obs_data_set_default_int(settings, "pip3_source_x", 0)
    obs.obs_data_set_default_int(settings, "pip3_source_y", 0)
    obs.obs_data_set_default_bool(settings, "pip3_border", true)

    obs.obs_data_set_default_bool(settings, "allow_all_sources", false)
    obs.obs_data_set_default_bool(settings, "use_monitor_override", false)
    obs.obs_data_set_default_int(settings, "monitor_override_x", 0)
    obs.obs_data_set_default_int(settings, "monitor_override_y", 0)
    obs.obs_data_set_default_int(settings, "monitor_override_w", 1920)
    obs.obs_data_set_default_int(settings, "monitor_override_h", 1080)
    obs.obs_data_set_default_double(settings, "monitor_override_sx", 1)
    obs.obs_data_set_default_double(settings, "monitor_override_sy", 1)
    obs.obs_data_set_default_int(settings, "monitor_override_dw", 1920)
    obs.obs_data_set_default_int(settings, "monitor_override_dh", 1080)
    obs.obs_data_set_default_bool(settings, "debug_logs", false)
end

function script_save(settings)
    if hotkey_zoom_id ~= nil then
        local hotkey_save_array = obs.obs_hotkey_save(hotkey_zoom_id)
        obs.obs_data_set_array(settings, "obs_mouse_zoom.hotkey.zoom", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

    if hotkey_follow_id ~= nil then
        local hotkey_save_array = obs.obs_hotkey_save(hotkey_follow_id)
        obs.obs_data_set_array(settings, "obs_mouse_zoom.hotkey.follow", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

    if hotkey_spotlight_id ~= nil then
        local hotkey_save_array = obs.obs_hotkey_save(hotkey_spotlight_id)
        obs.obs_data_set_array(settings, "obs_mouse_zoom.hotkey.spotlight", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

    -- Save PiP hotkey bindings
    for i = 1, PIP_MAX_WINDOWS do
        if pip_hotkey_toggle[i] then
            local hotkey_save_array = obs.obs_hotkey_save(pip_hotkey_toggle[i])
            obs.obs_data_set_array(settings, "obs_mouse_zoom.hotkey.pip_toggle_" .. i, hotkey_save_array)
            obs.obs_data_array_release(hotkey_save_array)
        end
        if pip_hotkey_lock[i] then
            local hotkey_save_array = obs.obs_hotkey_save(pip_hotkey_lock[i])
            obs.obs_data_set_array(settings, "obs_mouse_zoom.hotkey.pip_lock_" .. i, hotkey_save_array)
            obs.obs_data_array_release(hotkey_save_array)
        end
    end
    if pip_hotkey_all then
        local hotkey_save_array = obs.obs_hotkey_save(pip_hotkey_all)
        obs.obs_data_set_array(settings, "obs_mouse_zoom.hotkey.pip_all", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end
end

function script_update(settings)
    local old_source_name = source_name
    local old_override = use_monitor_override
    local old_x = monitor_override_x
    local old_y = monitor_override_y
    local old_w = monitor_override_w
    local old_h = monitor_override_h
    local old_sx = monitor_override_sx
    local old_sy = monitor_override_sy
    local old_dw = monitor_override_dw
    local old_dh = monitor_override_dh

    source_name = obs.obs_data_get_string(settings, "source")
    zoom_value = obs.obs_data_get_double(settings, "zoom_value")
    zoom_speed = obs.obs_data_get_double(settings, "zoom_speed")
    use_auto_follow_mouse = obs.obs_data_get_bool(settings, "follow")
    use_follow_outside_bounds = obs.obs_data_get_bool(settings, "follow_outside_bounds")
    follow_speed = obs.obs_data_get_double(settings, "follow_speed")
    follow_border = obs.obs_data_get_int(settings, "follow_border")
    follow_safezone_sensitivity = obs.obs_data_get_int(settings, "follow_safezone_sensitivity")
    use_follow_auto_lock = obs.obs_data_get_bool(settings, "follow_auto_lock")
    use_smooth_easing = obs.obs_data_get_bool(settings, "use_smooth_easing")
    easing_style = obs.obs_data_get_int(settings, "easing_style")

    -- Effect settings
    use_vignette_effect = obs.obs_data_get_bool(settings, "use_vignette_effect")
    vignette_intensity = obs.obs_data_get_double(settings, "vignette_intensity")
    use_spotlight = obs.obs_data_get_bool(settings, "use_spotlight")
    spotlight_radius = obs.obs_data_get_int(settings, "spotlight_radius")
    spotlight_opacity = obs.obs_data_get_double(settings, "spotlight_opacity")

    -- Magnifier character settings
    use_magnifier_character = obs.obs_data_get_bool(settings, "use_magnifier_character")
    magnifier_scale = obs.obs_data_get_double(settings, "magnifier_scale")
    character_anchor_x = obs.obs_data_get_int(settings, "character_anchor_x")
    character_anchor_y = obs.obs_data_get_int(settings, "character_anchor_y")
    magnifier_entry_direction = obs.obs_data_get_string(settings, "magnifier_entry_direction")

    -- PiP settings
    use_pip = obs.obs_data_get_bool(settings, "use_pip")

    -- Load PiP window settings
    for i = 1, PIP_MAX_WINDOWS do
        local window = pip_windows[i]
        local prefix = "pip" .. i .. "_"

        window.enabled = obs.obs_data_get_bool(settings, prefix .. "enabled")
        window.mode = obs.obs_data_get_int(settings, prefix .. "mode")
        window.display_position = obs.obs_data_get_int(settings, prefix .. "position")
        window.zoom_factor = obs.obs_data_get_double(settings, prefix .. "zoom")
        window.display_width = obs.obs_data_get_int(settings, prefix .. "width")
        window.display_height = obs.obs_data_get_int(settings, prefix .. "height")
        window.border_enabled = obs.obs_data_get_bool(settings, prefix .. "border")
        window.source_offset_x = obs.obs_data_get_int(settings, prefix .. "offset_x")
        window.source_offset_y = obs.obs_data_get_int(settings, prefix .. "offset_y")
        window.source_x = obs.obs_data_get_int(settings, prefix .. "source_x")
        window.source_y = obs.obs_data_get_int(settings, prefix .. "source_y")

        -- Calculate source region based on display size and zoom
        window.source_width = window.display_width * window.zoom_factor
        window.source_height = window.display_height * window.zoom_factor
    end

    allow_all_sources = obs.obs_data_get_bool(settings, "allow_all_sources")
    use_monitor_override = obs.obs_data_get_bool(settings, "use_monitor_override")
    monitor_override_x = obs.obs_data_get_int(settings, "monitor_override_x")
    monitor_override_y = obs.obs_data_get_int(settings, "monitor_override_y")
    monitor_override_w = obs.obs_data_get_int(settings, "monitor_override_w")
    monitor_override_h = obs.obs_data_get_int(settings, "monitor_override_h")
    monitor_override_sx = obs.obs_data_get_double(settings, "monitor_override_sx")
    monitor_override_sy = obs.obs_data_get_double(settings, "monitor_override_sy")
    monitor_override_dw = obs.obs_data_get_int(settings, "monitor_override_dw")
    monitor_override_dh = obs.obs_data_get_int(settings, "monitor_override_dh")
    debug_logs = obs.obs_data_get_bool(settings, "debug_logs")

    if source_name ~= old_source_name then
        refresh_sceneitem(true)
    end

    if source_name ~= old_source_name or
        use_monitor_override ~= old_override or
        monitor_override_x ~= old_x or
        monitor_override_y ~= old_y or
        monitor_override_w ~= old_w or
        monitor_override_h ~= old_h or
        monitor_override_sx ~= old_sx or
        monitor_override_sy ~= old_sy or
        monitor_override_dw ~= old_dw or
        monitor_override_dh ~= old_dh then
        monitor_info = get_monitor_info(source)
    end
end

function populate_zoom_sources(list)
    obs.obs_property_list_clear(list)

    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        local dc_info = get_dc_info()
        obs.obs_property_list_add_string(list, "<None>", "obs-mouse-zoom-none")
        for _, source in ipairs(sources) do
            local source_type = obs.obs_source_get_id(source)
            if source_type == dc_info.source_id or allow_all_sources then
                local name = obs.obs_source_get_name(source)
                obs.obs_property_list_add_string(list, name, name)
            end
        end

        obs.source_list_release(sources)
    end
end
