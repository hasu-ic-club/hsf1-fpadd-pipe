import logging

import cocotb
from cocotb.triggers import Timer, RisingEdge

from FpAdderAgent import FpAdderAgent
from FpAdderScoreboard import FpAdderScoreboard
from FpAdderTransactions import FpAdderOperandInputTransaction, FpAdderResultOutputTransaction


class FPAdderTestbench(object):
    def __init__(self, duv, enableBackpressure=True, backpressureRate=0.3):
        self.duv = duv

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.agent = FpAdderAgent(self.duv, enableBackpressure, backpressureRate)
        self.scoreboard = FpAdderScoreboard()

        # Start the scoreboard automatic checking process
        cocotb.start_soon(self.runScoreboard())

    async def reset(self):
        self.duv.aresetn.value = 0
        self.duv.op_valid.value = 0
        self.duv.result_ready.value = 0

        await Timer(15, 'ns')
        self.duv.aresetn.value = 1

        await RisingEdge(self.duv.clk)

    async def runScoreboard(self):
        while True:
            collected = await self.agent.monitor.collectedQueue.get()
            await self.scoreboard.checkOne(collected)

            await RisingEdge(self.duv.clk)

    async def sendVectors(self, opVecs: list[FpAdderOperandInputTransaction], resultVecs: list[FpAdderResultOutputTransaction]):
        self.log.info(f"Sending {len(opVecs)}/{len(resultVecs)} test vectors to the DUV")
        await self.scoreboard.pushExpectedVectors(resultVecs)
        await self.agent.driver.sendStream(opVecs)
