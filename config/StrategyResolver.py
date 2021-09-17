from helpers.StrategyCoreResolver import StrategyCoreResolver
from rich.console import Console

console = Console()


class StrategyResolver(StrategyCoreResolver):
    def get_strategy_destinations(self):
        """
        Track balances for all strategy implementations
        (Strategy Must Implement)
        """
        # E.G
        strategy = self.manager.strategy
        return {
            "vault": strategy.VAULT(),
            "pool": strategy.want(),
            "lpcomponent": strategy.lpComponent(),
        }

    def hook_after_confirm_withdraw(self, before, after, params):
        """
        Specifies extra check for ordinary operation on withdrawal
        Use this to verify that balances in the get_strategy_destinations are properly set
        """
        # After withdraw from strategy the lpcomponent should decrease as it will be burned ...
        assert after.balances("want", "lpcomponent") <= before.balances(
            "want", "lpcomponent"
        )

        # After withdraw from strategy vault balance should decrease ...
        assert after.balances("want", "vault") < before.balances("want", "vault")

    def hook_after_confirm_deposit(self, before, after, params):
        """
        Specifies extra check for ordinary operation on deposit
        Use this to verify that balances in the get_strategy_destinations are properly set
        """
        # Deposit from deployer to sett therefore this check is not needed
        assert True

    def hook_after_earn(self, before, after, params):
        """
        Specifies extra check for ordinary operation on earn
        Use this to verify that balances in the get_strategy_destinations are properly set
        """
        # Earn deposits the amount from sett to Strategy therefore check if we have got lpcomponent after depositing in the pool
        assert after.balances("want", "lpcomponent") > before.balances(
            "want", "lpcomponent"
        )
        # the balance of vault should increase after deposit
        assert after.balances("want", "vault") > before.balances("want", "vault")

    def confirm_harvest(self, before, after, tx):
        """
        Verfies that the Harvest produced yield and fees
        """
        console.print("=== Compare Harvest ===")
        self.manager.printCompare(before, after)
        self.confirm_harvest_state(before, after, tx)

        valueGained = after.get("sett.pricePerFullShare") > before.get(
            "sett.pricePerFullShare"
        )

        # # Strategist should earn if fee is enabled and value was generated
        # if before.get("strategy.performanceFeeStrategist") > 0 and valueGained:
        #     assert after.balances("want", "strategist") > before.balances(
        #         "want", "strategist"
        #     )

        # # Strategist should earn if fee is enabled and value was generated
        # if before.get("strategy.performanceFeeGovernance") > 0 and valueGained:
        #     assert after.balances("want", "governanceRewards") > before.balances(
        #         "want", "governanceRewards"
        #     )

    def confirm_tend(self, before, after, tx):
        """
        Tend Should;
        - Increase the number of staked tended tokens in the strategy-specific mechanism
        - Reduce the number of tended tokens in the Strategy to zero

        (Strategy Must Implement)
        """
        assert True
