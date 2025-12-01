import cocotb.result
from cocotb.queue import Queue

from FpAdderTransactions import FpAdderResultOutputTransaction
from FloatingPoint import FloatingPoint

class FpAdderScoreboard:
    def __init__(self):
        self.expectedQueue = Queue()

    async def pushExpected(self, item):
        await self.expectedQueue.put(item)

    async def pushExpectedVectors(self, items: list):
        for item in items:
            await self.expectedQueue.put(item)

    async def checkOne(self, actual : FpAdderResultOutputTransaction):
        if self.expectedQueue.empty():
            raise cocotb.result.TestFailure("Unexpected output received with empty expected queue")

        fpA : FloatingPoint
        fpB : FloatingPoint
        fpExpected : FloatingPoint
        fpA, fpB, fpExpected = await self.expectedQueue.get()
        expectedValue = fpExpected.getBinary()
        actualValue = actual.result

        actException = actual.exception.integer
        actIsNaN = actual.isNaN.integer
        actIsInf = actual.isInf.integer

        # Convert to float for better error message
        fpActual = FloatingPoint(fpExpected.M, fpExpected.E, actualValue)
        
        # Generate test string for error
        fomularStr = f"{fpA.toFloatString()} + {fpB.toFloatString()} "
        binaryStr = f"expected {fpExpected.toFloatString()}, actual {fpActual.toFloatString()}"

        # Check the result
        assert expectedValue == actualValue, fomularStr + binaryStr
        
        # Check the exception flags
        expectedNaN = 1 if fpExpected.isNaN() else 0
        expectedInf = 1 if fpExpected.isInfinity() else 0
        expectedException = 1 if expectedNaN or expectedInf else 0

        assert expectedNaN == actIsNaN, fomularStr + binaryStr + f" exp/act NaN = {expectedNaN}/{actIsNaN}"
        assert expectedInf == actIsInf, fomularStr + binaryStr + f" exp/act Inf = {expectedInf}/{actIsInf}"
        assert expectedException == actException
        


