-- Some super function to test
function my_super_function( arg1, arg2 ) return arg1 + arg2 end

-- Unit testing starts
local LuaUnit = require('luaunit')

require('lib/parser')

TestMaxWeight = {} --class
TestMaxHeight = {} --class


function TestMaxWeight:testWithoutUnit()

   result = parse_maxweight("150")
   assertEquals( type(result), 'number' )
   assertEquals( result, 150 )
end

function TestMaxWeight:testWithUnitNoSpace()

   result = parse_maxweight("30t")
   assertEquals( type(result), 'number' )
   assertEquals( result, 30 )
end

function TestMaxWeight:testWithUnitMeterSpace()

   result = parse_maxheight("3 m")
   assertEquals( type(result), 'number' )
   assertEquals( result, 3 )
end
--
-- maxheight
--
function TestMaxHeight:testWithUnitMeterNoSpace()

   result = parse_maxheight("30m")
   assertEquals( type(result), 'number' )
   assertEquals( result, 30 )
end

function TestMaxHeight:testWithUnitMeterSpace()

   result = parse_maxheight("30 m")
   assertEquals( type(result), 'number' )
   assertEquals( result, 30 )
end


function TestMaxHeight:testWithUnitFootInch()

   result = parse_maxheight("13'3\"")
   assertEquals( type(result), 'number' )
   assertEquals( result, 4.5 )
end

function TestMaxHeight:testWithUnitFootInch2()
   result = parse_maxheight("11'6\"")
   assertEquals( type(result), 'number' )
   assertEquals( result, 3.9 )
end

-- class TestMyStuff

LuaUnit:run()
