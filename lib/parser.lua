--
--
--
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
