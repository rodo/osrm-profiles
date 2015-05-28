-- Truck profile

function find_access_tag(source,access_tags_hierachy)
    for i,v in ipairs(access_tags_hierachy) do
        local tag = source:get_value_by_key(v)
        if tag and tag ~= '' then
            return tag
        end
    end
    return ""
end

-- Begin of globals
barrier_whitelist = { ["cattle_grid"] = true, ["border_control"] = true, ["checkpoint"] = true, ["toll_booth"] = true, ["sally_port"] = true, ["gate"] = true, ["lift_gate"] = true, ["no"] = true, ["entrance"] = true }
access_tag_whitelist = { ["yes"] = true, ["motorcar"] = true, ["motor_vehicle"] = true, ["vehicle"] = true, ["permissive"] = true, ["designated"] = true }
access_tag_blacklist = { ["no"] = true, ["private"] = true, ["agricultural"] = true, ["forestry"] = true, ["emergency"] = true, ["psv"] = true }
access_tag_restricted = { ["destination"] = true, ["delivery"] = true }
access_tags = { "motorcar", "motor_vehicle", "vehicle" }
access_tags_hierachy = { "motorcar", "motor_vehicle", "vehicle", "access" }
service_tag_restricted = { ["parking_aisle"] = true }
ignore_in_grid = { ["ferry"] = true }
restriction_exception_tags = { "motorcar", "motor_vehicle", "vehicle" }

speed_profile = {
  ["motorway"] = 90,
  ["motorway_link"] = 45,
  ["trunk"] = 85,
  ["trunk_link"] = 45,
  ["primary"] = 65,
  ["primary_link"] = 30,
  ["secondary"] = 55,
  ["secondary_link"] = 25,
  ["tertiary"] = 40,
  ["tertiary_link"] = 20,
  ["unclassified"] = 20,
  ["residential"] = 15,
  ["living_street"] = 10,
  ["service"] = 15,
  ["track"] = 5,
  ["ferry"] = 5,
  ["movable"] = 5,
  ["shuttle_train"] = 10,
  ["default"] = 10
}


-- surface/trackype/smoothness
-- values were estimated from looking at the photos at the relevant wiki pages

-- max speed for surfaces
surface_speeds = {
  ["asphalt"] = nil,    -- nil mean no limit. removing the line has the same effect
  ["concrete"] = nil,
  ["concrete:plates"] = nil,
  ["concrete:lanes"] = nil,
  ["paved"] = nil,

  ["cement"] = 80,
  ["compacted"] = 50,
  ["fine_gravel"] = 50,

  ["paving_stones"] = 30,
  ["metal"] = 30,
  ["bricks"] = 30,

  ["grass"] = 20,
  ["wood"] = 20,
  ["sett"] = 20,
  ["grass_paver"] = 20,
  ["gravel"] = 20,
  ["unpaved"] = 20,
  ["ground"] = 20,
  ["dirt"] = 20,
  ["pebblestone"] = 20,
  ["tartan"] = 20,

  ["cobblestone"] = 20,
  ["clay"] = 20,

  ["earth"] = 20,
  ["stone"] = 20,
  ["rocky"] = 20,
  ["sand"] = 20,

  ["mud"] = 10
}

-- max speed for tracktypes
tracktype_speeds = {
  ["grade1"] =  60,
  ["grade2"] =  40,
  ["grade3"] =  30,
  ["grade4"] =  25,
  ["grade5"] =  20
}

-- max speed for smoothnesses
smoothness_speeds = {
  ["intermediate"]    =  80,
  ["bad"]             =  40,
  ["very_bad"]        =  20,
  ["horrible"]        =  10,
  ["very_horrible"]   =  5,
  ["impassable"]      =  0
}

-- http://wiki.openstreetmap.org/wiki/Speed_limits
maxspeed_table_default = {
  ["urban"] = 30,
  ["rural"] = 60,
  ["trunk"] = 80,
  ["motorway"] = 90
}

traffic_signal_penalty          = 2
use_turn_restrictions           = true

local obey_oneway               = true
local obey_bollards             = true
local ignore_areas              = true
local u_turn_penalty            = 20

local abs = math.abs
local min = math.min
local max = math.max

local speed_reduction = 0.85

nogoods_road_speed = 5 -- ok tested
school_speed = 2 --

turn_penalty      = 85 -- ok tested
turn_bias         = 1.4 -- ok tested

--modes
local mode_normal = 1
local mode_ferry = 2
local mode_movable_bridge = 3

-- Open PostGIS connection
print("Connecting...")
lua_sql = require "luasql.postgres"           -- we will connect to a postgresql database
sql_env = assert( lua_sql.postgres() )
sql_con = assert( sql_env:connect('gis', 'docker', 'docker', "postgis", 5432) ) -- you can add db user/password here if needed
print("PostGIS connection opened")

function get_exceptions(vector)
  for i,v in ipairs(restriction_exception_tags) do
    vector:Add(v)
  end
end

local function parse_maxspeed(source)
  if not source then
    return 0
  end
  local n = tonumber(source:match("%d*"))
  if n then
    if string.match(source, "mph") or string.match(source, "mp/h") then
      n = (n*1609)/1000;
    end
  end
  return n
end

function turn_function (angle)
  -- compute turn penalty as angle^2, with a left/right bias
  k = turn_penalty/(90.0*90.0)
  if angle>=0 then
    return angle*angle*k/turn_bias
  else
    return angle*angle*k*turn_bias
  end
end

function node_function (node, result)
  -- parse access and barrier tags
  local access = find_access_tag(node, access_tags_hierachy)
  if access and access ~= "" then
    if access_tag_blacklist[access] then
      result.barrier = true
    end
  else
    local barrier = node:get_value_by_key("barrier")
    if barrier and "" ~= barrier then
      if not barrier_whitelist[barrier] then
        result.barrier = true
      end
    end
  end

  -- check if node is a traffic light
  local tag = node:get_value_by_key("highway")
  if tag and "traffic_signals" == tag then
    result.traffic_lights = true;
  end
end

function way_function (way, result)
  local highway = way:get_value_by_key("highway")
  local route = way:get_value_by_key("route")
  local bridge = way:get_value_by_key("bridge")

  if not ((highway and highway ~= "") or (route and route ~= "") or (bridge and bridge ~= "")) then
    return
  end

  -- we dont route over areas
  local area = way:get_value_by_key("area")
  if ignore_areas and area and "yes" == area then
    return
  end

  -- check if oneway tag is unsupported
  local oneway = way:get_value_by_key("oneway")
  if oneway and "reversible" == oneway then
    return
  end

  local impassable = way:get_value_by_key("impassable")
  if impassable and "yes" == impassable then
    return
  end

  local status = way:get_value_by_key("status")
  if status and "impassable" == status then
    return
  end

  local width = math.huge
  local width_string = way:get_value_by_key("width")
  if width_string and tonumber(width_string:match("%d*")) then
    width = tonumber(width_string:match("%d*"))
  end

  -- Check if we are allowed to access the way
  local access = find_access_tag(way, access_tags_hierachy)
  if access_tag_blacklist[access] then
    return
  end

  -- handling ferries and piers
  local route_speed = speed_profile[route]
  if (route_speed and route_speed > 0) then
    highway = route;
    local duration  = way:get_value_by_key("duration")
    if duration and durationIsValid(duration) then
      result.duration = max( parseDuration(duration), 1 );
    end
    result.forward_mode = mode_ferry
    result.backward_mode = mode_ferry
    result.forward_speed = route_speed
    result.backward_speed = route_speed
  end

  -- handling movable bridges
  local bridge_speed = speed_profile[bridge]
  local capacity_car = way:get_value_by_key("capacity:car")
  if (bridge_speed and bridge_speed > 0) and (capacity_car ~= 0) then
    highway = bridge;
    local duration  = way:get_value_by_key("duration")
    if duration and durationIsValid(duration) then
      result.duration = max( parseDuration(duration), 1 );
    end
    result.forward_mode = mode_movable_bridge
    result.backward_mode = mode_movable_bridge
    result.forward_speed = bridge_speed
    result.backward_speed = bridge_speed
  end

  -- We don't route over route with maxweight=3.5 or less
  local maxweight = parse_maxweight(way:get_value_by_key("maxweight"))
  if 0 < maxweight then
     if 3.5 >= maxweight then
  return
     end
  end

  -- We don't route over route with maxheight=4 or less
  local maxheight = parse_maxheight(way:get_value_by_key("maxheight"))
  if 0 < maxheight then
     if 4 >= maxheight then
  return
     end
  end

  -- avoid goods=no road
  local goods = way:get_value_by_key("goods")
  if goods and ("no" ==  goods or "delivery" == goods or "destination" == goods) then
    result.forward_speed = nogoods_road_speed
    result.backward_speed = nogoods_road_speed
  end

  -- hgv is from truck - 
  local hgv = way:get_value_by_key("hgv")
  if hgv and ("no" ==  hgv or "delivery" == hgv or "destination" == hgv) then
    result.forward_speed = nogoods_road_speed
    result.backward_speed = nogoods_road_speed
  end

  -- leave early of this way is not accessible
  if "" == highway then
    return
  end

  if result.forward_speed == -1 then
    local highway_speed = speed_profile[highway]
    local max_speed = parse_maxspeed( way:get_value_by_key("maxspeed") )
    -- Set the avg speed on the way if it is accessible by road class
    if highway_speed then
      if max_speed and max_speed > highway_speed then
        result.forward_speed = max_speed
        result.backward_speed = max_speed
        -- max_speed = math.huge
      else
        result.forward_speed = highway_speed
        result.backward_speed = highway_speed
      end
      result.forward_speed = min(result.forward_speed, highway_speed)
      result.backward_speed = min(result.backward_speed, highway_speed)
    else
      -- Set the avg speed on ways that are marked accessible
      if access_tag_whitelist[access] then
        result.forward_speed = speed_profile["default"]
        result.backward_speed = speed_profile["default"]
      end
    end
    if 0 == max_speed then
      max_speed = math.huge
    end
  end

  if -1 == result.forward_speed and -1 == result.backward_speed then
    return
  end

  -- reduce speed on bad surfaces
  local surface = way:get_value_by_key("surface")
  local tracktype = way:get_value_by_key("tracktype")
  local smoothness = way:get_value_by_key("smoothness")

  if surface and surface_speeds[surface] then
    result.forward_speed = math.min(surface_speeds[surface], result.forward_speed)
    result.backward_speed = math.min(surface_speeds[surface], result.backward_speed)
  end
  if tracktype and tracktype_speeds[tracktype] then
    result.forward_speed = math.min(tracktype_speeds[tracktype], result.forward_speed)
    result.backward_speed = math.min(tracktype_speeds[tracktype], result.backward_speed)
  end
  if smoothness and smoothness_speeds[smoothness] then
    result.forward_speed = math.min(smoothness_speeds[smoothness], result.forward_speed)
    result.backward_speed = math.min(smoothness_speeds[smoothness], result.backward_speed)
  end

  -- parse the remaining tags
  local name = way:get_value_by_key("name")
  local ref = way:get_value_by_key("ref")
  local junction = way:get_value_by_key("junction")
  -- local barrier = way:get_value_by_key("barrier", "")
  -- local cycleway = way:get_value_by_key("cycleway", "")
  local service = way:get_value_by_key("service")

  -- Set the name that will be used for instructions
  if ref and "" ~= ref then
    result.name = ref
  elseif name and "" ~= name then
    result.name = name
--  else
      --    result.name = highway  -- if no name exists, use way type
  end

  if junction and "roundabout" == junction then
    result.roundabout = true;
  end

  -- Set access restriction flag if access is allowed under certain restrictions only
  if access ~= "" and access_tag_restricted[access] then
    result.is_access_restricted = true
  end

  -- Set access restriction flag if service is allowed under certain restrictions only
  if service and service ~= "" and service_tag_restricted[service] then
    result.is_access_restricted = true
  end

  -- Set direction according to tags on way
  if obey_oneway then
    if oneway == "-1" then
      result.forward_mode = 0
    elseif oneway == "yes" or
    oneway == "1" or
    oneway == "true" or
    junction == "roundabout" or
    (highway == "motorway_link" and oneway ~="no") or
    (highway == "motorway" and oneway ~= "no") then
      result.backward_mode = 0
    end
  end

  -- Override general direction settings of there is a specific one for our mode of travel
  if ignore_in_grid[highway] then
    result.ignore_in_grid = true
  end  

  if highway~="motorway" and highway~="trunk" and highway~="primary" and highway~="residential" then
    -- Query PostGIS for residential areas close to the way, then group by way and sum the areas.
    -- We take the square root of the area to get a estimate of the length of the side of the area, 
    -- and thus a rough guess of how far we might be travelling along the area. 
    local sql_query = " " ..
      "SELECT SUM(SQRT(area.area)) AS val " ..
      "FROM osm_new_roads way " ..
      "LEFT JOIN osm_new_landusages area ON ST_DWithin(way.geometry, area.geometry, 50) " ..
      "WHERE area.type IN ('residential','school','university','college') AND way.osm_id=" .. way:id() .. " " ..
      "GROUP BY way.id"
    
    local cursor = assert( sql_con:execute(sql_query) )   -- execute query
    local row = cursor:fetch( {}, "a" )                   -- fetch first (and only) row
    if row then
     local val = tonumber(row.val)                       -- read 'val' from row 
     if val > 10 then      
       result.forward_speed = speed_profile["residential"]
       result.backward_speed = speed_profile["residential"]
       --result.forward_speed = result.forward_speed / math.log10(val)         -- reduce speed by amount of residential close by 
     end
    end
    
    -- look at school
    sql_query = " " ..
      "SELECT COUNT(amenity.id) AS val " ..
      "FROM osm_new_roads way " ..
      "LEFT JOIN osm_new_amenities amenity ON ST_DWithin(way.geometry, amenity.geometry, 50) " ..
      "WHERE amenity.type IN ('school','university','college') AND way.osm_id=" .. way:id()
    cursor = assert( sql_con:execute(sql_query) )   -- execute query        
    row = cursor:fetch( {}, "a" )                   -- fetch first (and only) row
    if row then
     local val = tonumber(row.val)                       -- read 'val' from row 
     if val > 0 then      
       print("school spotted @ " .. way:id())
       result.forward_speed = school_speed
       result.backward_speed = school_speed
     end
    end
    cursor:close()                                        -- done with this query
  end

  -- scale speeds to get better avg driving times
  if result.forward_speed > 0 then
    local scaled_speed = result.forward_speed*speed_reduction;
    local penalized_speed = math.huge
    if width <= 4 then
      penalized_speed = result.forward_speed / 2;
    end
    result.forward_speed = math.min(penalized_speed, scaled_speed)
  end

  if result.backward_speed > 0 then
    local scaled_speed = result.backward_speed*speed_reduction;
    local penalized_speed = math.huge
    if width <= 4 then
      penalized_speed = result.backward_speed / 2;
    end
    result.backward_speed = math.min(penalized_speed, scaled_speed)
  end
end

function parse_maxweight(source)
  if source == nil then
    return 0
  end
  local n = tonumber(source:match("%d.%d*"))
  if n == nil then
    n = 0
  end
  return math.abs(n)
end

function parse_maxheight(source)
  if source == nil then
          return 0
  end
  local n = tonumber(source:match("%d*"))
  if n == nil then
     n = 0
  end
  local inch = tonumber(source:match("(%d*)'%d"))
  local feet = tonumber(source:match("%d*'(%d*)"))
  if inch == nil then
     inch = 0
  end
  if feet == nil then
     feet = 0
  end
  if (feet + inch) > 0 then
     if inch > 0 then
        n = (inch * 3408)/100
     end
     if feet > 0 then
        n = n + (feet*254)/100
     end
     n = (math.floor(n)/100)
  end

  return math.abs(n)
end

