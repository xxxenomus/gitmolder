local alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/"
local base = {}

for i = 0, 63 do
	base[i] = alphabet:sub(i+1,i+1)
	base[alphabet:sub(i+1,i+1)] = i
end

--standard base64 for github compatibility
local stdAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local stdBase = {}
for i = 0, 63 do
	stdBase[i] = stdAlphabet:sub(i+1, i+1)
end

local S1, S2, S3, S4, S5 = {}, {}, {}, {}, {}

for C1 = 0, 255 do
	for C2 = 0, 255 do
		local Sum = C2 * 256 + C1
		local B1 = base[bit32.extract(Sum, 0, 6)]
		local B2 = base[bit32.extract(Sum, 6, 6)]
		S1[string.char(C1, C2)] = B1 .. B2
		S3[B1 .. B2] = string.char(C1)
	end
end

for C2 = 0, 255 do
	for C3 = 0, 255 do
		local Sum = C3 * 65536 + C2 * 256
		local B3 = base[bit32.extract(Sum, 12, 6)]
		local B4 = base[bit32.extract(Sum, 18, 6)]
		S2[string.char(C2, C3)] = B3 .. B4
		S5[B3 .. B4] = string.char(C3)
	end
end

for C1 = 0, 192, 64 do
	for C2 = 0, 255 do
		for C3 = 0, 3 do
			local Sum = C3 * 65536 + C2 * 256 + C1
			local B2 = base[bit32.extract(Sum, 6, 6)]
			local B3 = base[bit32.extract(Sum, 12, 6)]
			S4[B2 .. B3] = string.char(C2)
		end
	end
end

local function FastDecode(data)
	if data == "" or data == "E" then return "" end
	local padding = base[data:sub(1,1)]
	local result = table.create((#data-1)/4*3)

	local idx = 1
	for i = 2, #data, 4 do
		result[idx] = S3[data:sub(i, i+1)]
		result[idx+1] = S4[data:sub(i+1, i+2)]
		result[idx+2] = S5[data:sub(i+2, i+3)]
		idx += 3
	end

	local concat = table.concat(result)
	return concat:sub(1, #concat-padding)
end

--github needs STANDARD base64 alphabet
local function StdEncode(data)
	if #data == 0 then return "" end

	local padding = -#data % 3
	data = data .. string.rep("\0", padding)

	local out = table.create(math.ceil(#data * 4 / 3))
	local j = 1

	for i = 1, #data, 3 do
		local b1 = string.byte(data, i)
		local b2 = string.byte(data, i+1) or 0
		local b3 = string.byte(data, i+2) or 0

		local n = b1 * 65536 + b2 * 256 + b3

		out[j] = stdBase[bit32.rshift(n, 18) % 64]
		out[j+1] = stdBase[bit32.rshift(n, 12) % 64]
		out[j+2] = (i+1 <= #data - padding) and stdBase[bit32.rshift(n, 6) % 64] or "="
		out[j+3] = (i+2 <= #data - padding) and stdBase[n % 64] or "="
		j += 4
	end

	return table.concat(out)
end

return {encode = StdEncode, decode = FastDecode}