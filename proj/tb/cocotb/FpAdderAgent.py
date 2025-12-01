import random
from random import randint

import cocotb
from cocotb.clock import Clock
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, ReadOnly

from FpAdderTransactions import FpAdderOperandInputTransaction, FpAdderResultOutputTransaction


class FpAdderOperandInputDriver:
    def __init__(self, duv):
        self.duv = duv

    async def sendOne(self, item : FpAdderOperandInputTransaction):
        self.duv.op_a_in.value = item.operandA
        self.duv.op_b_in.value = item.operandB
        self.duv.op_valid.value = 1

        while True:
            await RisingEdge(self.duv.clk)
            if self.duv.op_ready.value == 1:
                break

        self.duv.op_valid.value = 0

    async def sendStream(self, vecs: list[FpAdderOperandInputTransaction]):
        for item in vecs:
            self.duv.op_a_in.value = item.operandA
            self.duv.op_b_in.value = item.operandB
            self.duv.op_valid.value = 1

            while True:
                await RisingEdge(self.duv.clk)
                if self.duv.op_ready.value == 1:
                    break

        self.duv.op_valid.value = 0

class FpAdderResultOutputMonitor:
    def __init__(self, duv, enableBackpressure=True, backpressureRate=0.3):
        self.duv = duv

        self.enableBackpressure = enableBackpressure
        self.backpressureRate = backpressureRate

        self.collectedQueue = Queue()

    async def run(self):
        self.duv.result_ready.value = 1

        while True:
            await RisingEdge(self.duv.clk)

            if self.enableBackpressure:
                self.duv.result_ready.value = 1 if random.random() < self.backpressureRate else 0

            if self.duv.result_ready.value == 1 and self.duv.result_valid.value == 1:
                result = int(self.duv.result_out.value)
                exception = self.duv.exception_out.value
                isNaN = self.duv.nan_out.value
                isInf = self.duv.inf_out.value

                transaction = FpAdderResultOutputTransaction(result, exception, isNaN, isInf)
                await self.collectedQueue.put(transaction)


class FpAdderAgent:
    def __init__(self, duv, enableBackpressure=True, backpressureRate=0.3):
        self.duv = duv

        self.driver = FpAdderOperandInputDriver(duv)
        self.monitor = FpAdderResultOutputMonitor(duv, enableBackpressure, backpressureRate)

        cocotb.start_soon(self.monitor.run())