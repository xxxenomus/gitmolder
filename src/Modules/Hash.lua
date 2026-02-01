local Hash = {}

--im using fnv1a32 cuz its fast and good enough for change checks
function Hash.fnv1a32(str)
	local hash = 2166136261
	for i = 1, #str do
		hash = bit32.bxor(hash, string.byte(str, i))
		hash = (hash * 16777619) % 4294967296
	end
	return hash
end

return Hash
