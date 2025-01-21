--!optimize 2
--!native








--===========================[[ VARIABLES ]]===========================--



local bigfloat = {}
bigfloat.__index = bigfloat

type bigfloat = {buffer | number} --// {[1]: binaryData, [2]: exponentBits, [3]: mantissaBits}









--===========================[[ AUXILARY: CALCULATING EXPONENT LENGTH ]]===========================--



local ExponentLengthCache = {
	[1 / 8] = 0,
	[1] = 4,
	[2] = 5,
	[4] = 8,
	[8] = 11,
	[16] = 15,
	[32] = 19,
}

local _niCache = {}

function _reverseTuple(tuple)
	return {tuple[2], tuple[1]}
end

function _computeB(n, i)
	if not (_niCache[n] and _niCache[n][i]) then
		if not _niCache[n] then
			_niCache[n] = {}
		end
		
		local result =
			n == i and 
			{n, 0} or
			{0, 0}
		
		if i >= 1 then
			local previous = _computeB(n, i - 1)
			local bShifted =
				n < i and
				{0, 0} or
				_reverseTuple(_computeB(n - i, i))
			
			result[1] += previous[1] + bShifted[1]
			result[2] += previous[2] + bShifted[2]
		end
		
		_niCache[n][i] = result
	end
	
	return _niCache[n][i]
end

function OEIS_A222044(n)
	return _computeB(n, n)[1]
end

function _calculateExponentLength(bytes: number)
	local n = math.log(bytes, 2)
	
	return n % 1 == 0 and
		OEIS_A222044(n) or
		math.ceil(math.exp(math.pi * math.sqrt(n * 2 / 3)) / (n * 2 * math.sqrt(3))) + 2
end

function GetExponentLength(bytes: number) --// Returns # of bits allocated to the float's exponent based on float length in bytes
	if not ExponentLengthCache[bytes] then
		ExponentLengthCache[bytes] = _calculateExponentLength(bytes)
	end
	
	return ExponentLengthCache[bytes]
end








--===========================[[ AUXILARY: ITERATOR FUNCTIONS ]]===========================--



function compositeQuads(b: buffer)
	local idx = 0
	
	local function iterator(): (number, number, (b: buffer, offset: number, value: number) -> (), number)
		local remainingBytes = buffer.len(b) - idx
		
		if remainingBytes >= 4 then
			idx += 4
			return idx - 4, buffer.readu32(b, idx - 4), buffer.readu32, 4
		elseif remainingBytes >= 2 then
			idx += 2
			return idx - 2, buffer.readu16(b, idx - 2), buffer.readu16, 2
		elseif remainingBytes == 1 then
			idx += 1
			return idx - 1, buffer.readu8(b, idx - 1), buffer.readu8, 1
		end
	end
	
	return iterator
end

function binaryStringQuads(s: string)
	if string.gmatch(s, "[^01]")() then
		error("String must be binary!")
	end
	
	if #s / 8 % 1 ~= 0 then
		error("String must comprise whole bytes.")
	end
	
	local idx = 0

	local function iterator(): (number, number, (b: buffer, offset: number, value: number) -> (), number)
		local remainingBytes = #s / 8 - idx

		if remainingBytes >= 4 then
			idx += 4
			return idx - 4, tonumber(string.sub(s, 8 * idx - 31, 8 * idx + 1), 2), buffer.readu32, 4
		elseif remainingBytes >= 2 then
			idx += 2
			return idx - 2, tonumber(string.sub(s, 8 * idx - 15, 8 * idx + 1), 2), buffer.readu16, 2
		elseif remainingBytes == 1 then
			idx += 1
			return idx - 1, tonumber(string.sub(s, 8 * idx - 7, 8 * idx + 1), 2), buffer.readu8, 1
		end
	end

	return iterator
end








--===========================[[ AUXILARY: STRINGS TO FLOAT ]]===========================--

--// Thank you to kexy123 for their post @ https://devforum.roblox.com/t/how-to-convert-strings-into-a-floating-point-number/3061055/7?u=au_tk

local _dividedBy2 = {
	["0"] = {0, 0},
	["1"] = {0, 5},
	["2"] = {1, 0},
	["3"] = {1, 5},
	["4"] = {2, 0},
	["5"] = {2, 5},
	["6"] = {3, 0},
	["7"] = {3, 5},
	["8"] = {4, 0},
	["9"] = {4, 5}
}

local _multipliedBy2 = {
	["0"] = {0, 0},
	["1"] = {2, 0},
	["2"] = {4, 0},
	["3"] = {6, 0},
	["4"] = {8, 0},
	["5"] = {0, 1},
	["6"] = {2, 1},
	["7"] = {4, 1},
	["8"] = {6, 1},
	["9"] = {8, 1}
}

function _floorDivide2(str: string): (string, number)
	local quotient, remainder = "", 0
	
	for i = 1, #str do
		local symbol = string.sub(str, i, i)
		local divideResult = _dividedBy2[symbol]
		
		quotient ..= divideResult[1] + remainder
		remainder = divideResult[2]
	end
	
	quotient = string.match(quotient, "^0+(%d+)")
	return quotient, remainder
end

function _multiplyBy2(str: string): string
	local product, carry = "", 0
	
	for i = #str, 1, -1 do
		local symbol = string.sub(str, i, i)
		local multiplyResult = _multipliedBy2[symbol]
		
		product = tostring(multiplyResult[1] + carry) .. product
		carry = multiplyResult[2]
	end
	
	if carry > 0 then
		product = tostring(carry) .. product
	end
	
	return product
end

function _wholeNumberToBinary(str: string): string
	local binary, remainder = "", 0
	
	while str ~= "" do
		str, remainder = _floorDivide2(str)
		binary = math.sign(remainder) .. binary
	end
	
	return binary
end

function _fractionToBinary(str: string, mantissaLength: number): string
	local bisemal = ""
	
	for _ = 1, mantissaLength do
		str = _multiplyBy2(str)
		
		bisemal ..= string.sub(str, 1, 1)
		str = `0{string.sub(str, 2)}`
	end
	
	return bisemal
end

function _writeStringToFloat(str: string, float: bigfloat)
	local sign, whole, fraction = string.match(string.gsub(str, "^(-?)(%.)", "%10%2"), "^(%--)(%d+)%.?(%d*)")
	local wholeBinary, fractionBinary = _wholeNumberToBinary(whole), _fractionToBinary(`0{fraction}`, float[3])
	local binary = wholeBinary .. fractionBinary
	local index = string.find(binary, "1")
	local exponent = #wholeBinary - index + 2 ^ (float[2] - 1) - 1
	exponent = _wholeNumberToBinary(tostring(exponent))
	exponent = string.rep("0", float[2] - #exponent) .. exponent
	binary = string.sub(binary, index + 1, index + float[3])
	sign = sign == "-" and 1 or 0
	
	local floatString = sign .. exponent .. binary
	
	for i, chunk, write, length in binaryStringQuads(floatString) do
		write(float[1], i, chunk)
	end
	
	return float
end








--===========================[[ FUNCTIONS ]]===========================--



function bigfloat.new(Value: number | string | nil) --// Creates a new bigfloat with the value if specified
	--// TODO: this
end








--===========================[[ METAMETHODS ]]===========================--



return bigfloat
