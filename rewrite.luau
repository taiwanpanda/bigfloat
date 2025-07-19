--!optimize 2
--!native








--===========================[[ VARIABLES ]]===========================--



local bigfloat = {}

local _mt = {}
_mt.__index = _mt

local exponentialFactor = math.log(2, 10)

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
		OEIS_A222044(n + 3) or
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
			return idx - 4, buffer.readu32(b, idx - 4), buffer.writeu32, 4
		elseif remainingBytes >= 2 then
			idx += 2
			return idx - 2, buffer.readu16(b, idx - 2), buffer.writeu16, 2
		elseif remainingBytes == 1 then
			idx += 1
			return idx - 1, buffer.readu8(b, idx - 1), buffer.writeu8, 1
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
			return idx - 4, tonumber(string.sub(s, 8 * idx - 31, 8 * idx + 1), 2), buffer.writeu32, 4
		elseif remainingBytes >= 2 then
			idx += 2
			return idx - 2, tonumber(string.sub(s, 8 * idx - 15, 8 * idx + 1), 2), buffer.writeu16, 2
		elseif remainingBytes == 1 then
			idx += 1
			return idx - 1, tonumber(string.sub(s, 8 * idx - 7, 8 * idx + 1), 2), buffer.writeu8, 1
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
	
	quotient = string.match(quotient, "^0*(%d+)")
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
	
	while str ~= "0" do
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
	
	sign = sign == "-" and
		1 or
		0
	
	local floatString = sign .. exponent .. binary
	
	for i, chunk, write, length in binaryStringQuads(floatString) do
		write(float[1], i, chunk)
	end
end








--===========================[[ AUXILARY: NUMBER TO FLOAT ]]===========================--



function _decimalToBits(decimal: number, mantissaLength: number): number
	local bisemal = 0
	
	for i = 1, mantissaLength do
		local placeValue = 2 ^ -i
		
		if placeValue <= decimal then
			decimal -= placeValue
			bisemal += 2 ^ (mantissaLength - i)
			
			if decimal == 0 then
				break
			end
		end
	end
	
	return bisemal
end

function _binarySub(number, bitLength, i, j)
	return number % 2 ^ (bitLength - i + 1) // 2 ^ (bitLength - j)
end

function _writeNumberToFloat(number: number, float: bigfloat) --// type number is a double (float64)
	if float[2] <= 52 then --// the precision when calculating the biasedExponent will no longer be integer precision if the # of exponent bits exceeds 52
		local floatLength = buffer.len(float[1])

		local sign = 0 ^ math.max(math.sign(number), 0)
		local absnumber = math.abs(number)

		local exponent = math.floor(math.log(absnumber, 2))
		local biasedExponent = 2 ^ (float[2] - 1) - 1 + exponent

		local mantissa = _decimalToBits(absnumber / 2 ^ exponent % 1, math.min(float[3], 52)) --// number is always a double; only has 52 mantissa bits.

		local transitionByte = math.floor((float[2] + 1) / 8)
		local exponentIndex = 0
		local mantissaIndex = 0

		for i, _, write, length in compositeQuads(float[1]) do
			local signBits = i == 0 and --// Byte composition, # of sign bits, # of exponent bits, # of mantissa bits
				1 or
				0

			local exponentBits = math.max(
				(
					i + length < transitionByte and --// Check if these calculations are correct. (I think they are now)
					math.min(float[2], 8 * length) or
					8 * (transitionByte - i) + (float[3] % 8 > 0 and 8 - float[3] % 8 or 0)
				) - signBits,
				0
			)
	
			local mantissaBits = 8 * length - exponentBits - signBits

			local binaryChunk = 
				signBits * sign * 2 ^ (8 * length - 1) + --// You were accidentally applying the sign to each chunk by forgetting to multiply by signBits
				_binarySub(biasedExponent, float[2], exponentIndex, exponentIndex + exponentBits) * 2 ^ (8 * length - exponentBits - signBits) +
				_binarySub(mantissa, float[3], mantissaIndex, mantissaIndex + mantissaBits)

			exponentIndex += exponentBits
			mantissaIndex += mantissaBits

			write(float[1], floatLength - i - length, binaryChunk)
		end
	else
		_writeStringToFloat(tostring(number), float) --// Replace this with use of bigfloats when possible
	end
end








--===========================[[ AUXILARY: MISC ]]===========================--



function _getFloatComposition(bytes: number): (number, number)
	local exponentLength = GetExponentLength(bytes)
	local mantissaLength = 8 * bytes - exponentLength - 1
	
	return exponentLength, mantissaLength
end

function bigfloat._getRangeUsingExponentLength(exponentLength: number): (string, string)
	local bias = 2 ^ (exponentLength - 1)
	local bias_10 = bias * exponentialFactor
	
	local minimum = bias_10 - exponentialFactor < 7
		and `±{2 ^ (bias - 1)}` or
		`±{10 ^ ((bias_10 - exponentialFactor) % 1)}e-{math.floor(bias_10 - exponentialFactor)}`

	local maximum = bias_10 < 21
		and `±{2 ^ bias}` or
		`±{10 ^ (bias_10 % 1)}e+{math.floor(bias_10)}`
	
	return minimum, maximum
end








--===========================[[ FUNCTIONS ]]===========================--



function bigfloat.WriteValue(Value: number | string, float: bigfloat)
	if typeof(Value) == "number" then
		_writeNumberToFloat(Value, float)
	elseif typeof(Value) == "string" then
		_writeStringToFloat(Value, float)
	end
	
	return float --// Convenience
end

function bigfloat.new(bytes: number, Value: number | string | nil) --// Creates a new bigfloat with the value if specified
	local exponentLength, mantissaLength = _getFloatComposition(bytes)
	
	local float = setmetatable({buffer.create(bytes), exponentLength, mantissaLength}, _mt)
	
	if Value then
		bigfloat.WriteValue(Value, float)
	end
	
	return float
end

function bigfloat.GetRange(float: bigfloat)
	return bigfloat._getRangeUsingExponentLength(float[2])
end








--===========================[[ METAMETHODS ]]===========================--



return bigfloat
