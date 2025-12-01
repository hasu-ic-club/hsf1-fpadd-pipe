import struct
from enum import Enum

class FloatingPointRoundingMode(Enum):
    NEAREST_EVEN = 0
    TOWARD_ZERO = 1
    TOWARD_POSITIVE = 2
    TOWARD_NEGATIVE = 3

class FloatingPointGRS:
    def __init__(self):
        self.guard = 0
        self.round = 0
        self.sticky = 0

    def getExtendMantissa(self, mantissa):
        mantissa = mantissa << 3
        extMantissa = mantissa | (self.guard << 2) | (self.round << 1) | self.sticky
        return extMantissa

    def setGRSFromExtendMantissa(self, extMantissa):
        self.guard = (extMantissa >> 2) & 0x1
        self.round = (extMantissa >> 1) & 0x1
        self.sticky = extMantissa & 0x1

        return extMantissa >> 3

    def getShiftableMantissa(self, mantissa):
        return self.getExtendMantissa(mantissa) >> 1

    def rightShiftWithGRS(self, mantissa, shift):
        extMantissa = self.getExtendMantissa(mantissa)
        sticky = 0
        lostBitsMask = (1 << shift) - 1
        lostBits = extMantissa & lostBitsMask

        sticky = 1 if lostBits != 0 else 0
        extMantissa >>= shift

        extMantissa |= sticky

        return self.setGRSFromExtendMantissa(extMantissa)

    def leftShiftWithGRS(self, mantissa, shift):
        extMantissa = self.getExtendMantissa(mantissa)
        extMantissa <<= shift
        return self.setGRSFromExtendMantissa(extMantissa)

    def subtractWithGRS(self, substracted, mantissa):
        extSub = substracted << 3
        extMantissa = self.getExtendMantissa(mantissa)
        result = extSub - extMantissa

        return self.setGRSFromExtendMantissa(result)

    def clearGRS(self):
        self.guard = 0
        self.round = 0
        self.sticky = 0

    def applyGRSRounding(self, mantissa, sign, roundingMode: FloatingPointRoundingMode):
        if roundingMode == FloatingPointRoundingMode.NEAREST_EVEN:
            if self.guard == 1:
                if self.round == 1 or self.sticky == 1 or (mantissa & 0x1) == 1:
                    mantissa += 1
        elif roundingMode == FloatingPointRoundingMode.TOWARD_ZERO:
            pass
        elif roundingMode == FloatingPointRoundingMode.TOWARD_POSITIVE:
            if sign == 0 and (self.guard == 1 or self.round == 1 or self.sticky == 1):
                mantissa += 1
        elif roundingMode == FloatingPointRoundingMode.TOWARD_NEGATIVE:
            if sign == 1 and (self.guard == 1 or self.round == 1 or self.sticky == 1):
                mantissa += 1
        return mantissa

class FloatingPoint:
    def __init__(self, M: int = 23, E: int = 8, data = 0):
        assert E > 0 and M > 0 and (E + M + 1) <= 64, "Invalid floating point format specification."

        self.M = M  # Number of mantissa bits
        self.E = E  # Number of exponent bits

        # Constant masks and values
        self.EXPONENT_ALL_ONES_MASK = (1 << E) - 1
        self.MANTISSA_HIDDEN_BIT_MASK = (1 << M)
        self.MANTISSA_ALL_ONES_MASK = (1 << M) - 1
        self.EXPONENT_BIAS = (1 << (E - 1)) - 1
        self.SIGN_BIT_MASK = (1 << (E + M))
        self.MAXIMUM_EXP = (1 << E) - 2 - self.EXPONENT_BIAS
        self.MINIMUM_EXP = 1 - self.EXPONENT_BIAS
        self.MINIMUM_SUBNORMALIZED_EXP = self.MINIMUM_EXP - M + 1

        self.data = data

    def setValue(self, sign = 0, exponent = 0, mantissa = 0):
        self.data = ((sign & 0x1) << (self.E + self.M)) | ((exponent & self.EXPONENT_ALL_ONES_MASK) << self.M) | (mantissa & self.MANTISSA_ALL_ONES_MASK)

    def setBinary(self, binary):
        self.data = binary

    def getBinary(self):
        return self.data

    def getSign(self):
        return (self.data >> (self.E + self.M)) & 0x1

    def getExponent(self):
        return (self.data >> self.M) & self.EXPONENT_ALL_ONES_MASK

    def getMantissa(self):
        return self.data & self.MANTISSA_ALL_ONES_MASK

    def isZero(self):
        return self.getExponent() == 0 and self.getMantissa() == 0

    def isSubNormalized(self):
        return self.getExponent() == 0 and self.getMantissa() != 0

    def isNormalized(self):
        exp = self.getExponent()
        return exp != 0 and exp != self.EXPONENT_ALL_ONES_MASK

    def isInfinity(self):
        return self.getExponent() == self.EXPONENT_ALL_ONES_MASK and self.getMantissa() == 0

    def isNaN(self):
        return self.getExponent() == self.EXPONENT_ALL_ONES_MASK and self.getMantissa() != 0

    def MAX_NORMALIZED_VALUE(self):
        return (2.0 - pow(2, self.M)) * pow(2, self.MAXIMUM_EXP)

    def MIN_NORMALIZED_VALUE(self):
        return pow(2, self.MINIMUM_EXP)

    def MIN_SUBNORMALIZED_VALUE(self):
        return pow(2, self.MINIMUM_SUBNORMALIZED_EXP)

    @staticmethod
    def ZERO(M, E):
        return FloatingPoint(M, E, 0)

    @staticmethod
    def NaN(M, E):
        fp = FloatingPoint(M, E)
        fp.setValue(0, fp.EXPONENT_ALL_ONES_MASK, 1)
        return fp

    def toFloat(self):
        if self.isNaN():
            return float('nan')
        if self.isInfinity():
            return float('-inf') if self.getSign() == 1 else float('inf')
        if self.isZero():
            return -0.0 if self.getSign() == 1 else 0.0

        sign = -1.0 if self.getSign() == 1 else 1.0
        exponent = self.getExponent()
        mantissa = self.getMantissa()

        if self.isSubNormalized():
            expValue = 1 - self.EXPONENT_BIAS
            mantissaValue = mantissa / (1 << self.M)
        else:
            expValue = exponent - self.EXPONENT_BIAS
            mantissaValue = 1.0 + (mantissa / (1 << self.M))

        return sign * mantissaValue * (2 ** expValue)

    def toFloatString(self):
        return f"{self.toFloat()}({self.getBinary():08X})"

    @staticmethod
    def fromFloat32(value: float):
        b = struct.pack("!f", value)
        fp = FloatingPoint(23, 8)
        fp.setBinary(struct.unpack('!I', b)[0])
        return fp

    def __neg__(self):
        fp = FloatingPoint(self.M, self.E, self.data)
        fp.setValue(1 - self.getSign(), self.getExponent(), self.getMantissa())
        return fp

    def __add__(self, other):
        return FloatingPoint.add(self, other, FloatingPointRoundingMode.NEAREST_EVEN)

    @staticmethod
    def add(a, b, roundingMode: FloatingPointRoundingMode = FloatingPointRoundingMode.NEAREST_EVEN):
        assert a.M == b.M and a.E == b.E, "Floating point formats must match for addition."
        M = a.M
        E = a.E

        # NaN, Infinity, Zero handling
        #  1. NaN + ANY = NaN
        if a.isNaN() or b.isNaN(): return FloatingPoint.NaN(M, E)

        #  2. 0 + ANY = ANY
        if a.isZero(): return b
        if b.isZero(): return a

        #  3. Infinity + ANY (not -Infinity) = Infinity
        #     Infinity + -Infinity = NaN
        if a.isInfinity() and b.isInfinity() and (a.getSign() != b.getSign()):
            return FloatingPoint.NaN(M, E)
        elif a.isInfinity():
            return a
        elif b.isInfinity():
            return b

        # Extract mantissas with hidden bits
        mantissaA = a.getMantissa() if a.isSubNormalized() else (a.MANTISSA_HIDDEN_BIT_MASK | a.getMantissa())
        mantissaB = b.getMantissa() if b.isSubNormalized() else (b.MANTISSA_HIDDEN_BIT_MASK | b.getMantissa())

        # Local variables for mantissa and exponent, sign
        # X is the larger one
        # Swap mantissas based on comparison
        if (a.getExponent() < b.getExponent()) or ((a.getExponent() == b.getExponent()) and (mantissaB > mantissaA)):
            # b has larger exponent, shift a's mantissa
            # map a to Y and b to X
            mantissaX = mantissaB
            mantissaY = mantissaA

            expX = b.getExponent()
            expY = a.getExponent()

            signX = b.getSign()
            signY = a.getSign()
        else:
            # a has larger exponent or same, shift b's mantissa
            # map b to Y and a to X
            mantissaX = mantissaA
            mantissaY = mantissaB

            expX = a.getExponent()
            expY = b.getExponent()

            signX = a.getSign()
            signY = b.getSign()

        # Align mantissas
        expX = 1 if expX == 0 else expX
        expY = 1 if expY == 0 else expY
        expDiff = (expX - expY)  # If sub-normalized, treat exponent as 1 for alignment
        grs = FloatingPointGRS()
        mantissaY = grs.rightShiftWithGRS(mantissaY, expDiff)

        # Add / subtract mantissas
        sumValue = mantissaX + mantissaY if signX == signY else grs.subtractWithGRS(mantissaX, mantissaY)
        resultExponent = expX
        resultSign = signX


        sumHidden = sumValue >> M

        if sumHidden & 0b10:
            # Overflow, need to right shift and increment exponent
            if resultExponent == a.EXPONENT_ALL_ONES_MASK - 1:
                # Overflow to infinity
                resultExponent = a.EXPONENT_ALL_ONES_MASK
                sumValue = 0
                grs.clearGRS()
            else:
                sumValue = grs.rightShiftWithGRS(sumValue, 1)
                resultExponent += 1
        elif (sumHidden == 0x00) and (grs.getShiftableMantissa(sumValue) != 0):
            # Underflow, need to left shift and decrement exponent
            # Get leading zeros (total bits is M + 2 + 1)
            shiftable = grs.getShiftableMantissa(sumValue)
            totalBits = M + 2 + 1
            leadingZeros = totalBits if shiftable == 0 else totalBits - shiftable.bit_length()

            if (resultExponent == 0) or (resultExponent == 1):
                # Result will be sub-normalized
                resultExponent = 0
            elif leadingZeros < resultExponent:
                sumValue = grs.leftShiftWithGRS(sumValue, leadingZeros)
                resultExponent -= leadingZeros
            else:
                # Sub-normalized result
                sumValue = grs.leftShiftWithGRS(sumValue, resultExponent - 1)
                resultExponent = 0
        elif (sumHidden == 0) and (sumValue == 0):
            # Result is zero
            return FloatingPoint.ZERO(M, E)

        sumValue = grs.applyGRSRounding(sumValue, resultSign, roundingMode)

        # Realign after rounding
        sumHidden = sumValue >> M
        if sumHidden & 0b10:
            sumValue = grs.rightShiftWithGRS(sumValue, 1)
            resultExponent += 1
        elif (resultExponent == 0) and (sumHidden & 0b1):
            # Denormalized mantissa overflowed to normalized
            resultExponent = 1

        # Remove hidden bit
        resultMantissa = sumValue & a.MANTISSA_ALL_ONES_MASK

        # Result construction
        fpResult = FloatingPoint(M, E)
        fpResult.setValue(resultSign, resultExponent, resultMantissa)
        return fpResult

if __name__ == '__main__':
    # Simple test
    fA = 1.0
    fB = -1.5
    fC = fA + fB

    bA = struct.pack("!f", fA)
    bB = struct.pack("!f", fB)
    bC = struct.pack("!f", fC)

    fpA = FloatingPoint(23, 8)
    fpB = FloatingPoint(23, 8)

    fpA.setBinary(struct.unpack('!I', bA)[0])
    fpB.setBinary(struct.unpack('!I', bB)[0])

    fpC = FloatingPoint.add(fpA, fpB, FloatingPointRoundingMode.NEAREST_EVEN)

    bFpC = struct.pack('!I', fpC.getBinary())
    fFpC = struct.unpack('!f', bFpC)[0]

    print(f"{fA} + {fB}")
    print(f"Expected {struct.unpack('!f', bC)[0]} ({struct.unpack('!I', bC)[0]:08X})")
    print(f"Actual   {fFpC} ({fpC.getBinary():08X})")
