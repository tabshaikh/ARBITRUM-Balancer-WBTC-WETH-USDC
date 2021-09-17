import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days

"""
  TODO: Put your tests here to prove the strat is good!
  See test_harvest_flow, for the basic tests
  See test_strategy_permissions, for tests at the permissions level
"""


def test_custom_deposit(deployer, sett, strategy, want):
    # Setup
    startingBalance = want.balanceOf(deployer)

    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance >= 0
    # End Setup
    print("Setup Complete")

    # Deposit
    assert want.balanceOf(sett) == 0

    want.approve(sett, MaxUint256, {"from": deployer})
    sett.deposit(depositAmount, {"from": deployer})

    available = sett.available()
    assert available > 0
    print("Avaiable amount in sett: ", sett.available())

    sett.earn({"from": deployer})

    amountLPComponent = strategy.balanceOfPool()

    print("Amount of LPComponent(BAL-WBTC-WETH-USDC-Token):", amountLPComponent)

    assert amountLPComponent > 0

    # Will not work currently as the Pool Contract is not verified on arbitrum ... and brownie throws an error
    # ValueError: Failed to retrieve data from API: {'status': '0', 'message': 'NOTOK', 'result': 'Contract source code not verified'}
    # balanceOfPoolInWant = (
    #     strategy.balanceOfPoolinWant()
    # )  # Getting the balance of pool in terms of want

    # assert balanceOfPoolInWant > 0


def test_custom_withdraw_all(deployer, sett, strategy, want, controller):
    # Setup
    startingBalance = want.balanceOf(deployer)

    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance >= 0
    # End Setup
    print("Setup Complete")

    # Deposit
    assert want.balanceOf(sett) == 0

    want.approve(sett, MaxUint256, {"from": deployer})
    sett.deposit(depositAmount, {"from": deployer})

    available = sett.available()
    assert available > 0
    print("Avaiable amount in sett: ", sett.available())

    sett.earn({"from": deployer})

    amountLPComponent = strategy.balanceOfPool()

    print("Amount of LPComponent(BAL-WBTC-WETH-USDC-Token):", amountLPComponent)

    assert amountLPComponent > 0

    # Deposit complete

    # Withdraw
    controller.withdrawAll(strategy.want(), {"from": deployer})

    assert (
        strategy.balanceOfPool() == 0
    )  # After withdrawAll no LPComponent should be there

    assert (
        strategy.totalDepositedinPool() == 0
    )  # totalDepositedinPool balance should be zero
