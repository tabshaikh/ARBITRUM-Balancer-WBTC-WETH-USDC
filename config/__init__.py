## Ideally, they have one file with the settings for the strat and deployment
## This file would allow them to configure so they can test, deploy and interact with the strategy

BADGER_DEV_MULTISIG = "0xb65cef03b9b89f99517643226d76e286ee999e77"

WANT = "0x2f2a2543b76a4166549f7aab2e75bef0aefc5b0f"  ## WBTC on Arbitrum
LP_COMPONENT = "0x64541216bafffeec8ea535bb71fbc927831d0595"  ## lp-token that balancer gives https://arbiscan.io/address/0x64541216bafffeec8ea535bb71fbc927831d0595
REWARD_TOKEN = "0x040d1edc9569d4bab2d15287dc5a4f10f56a56b8"  ## BAL Token on Arbitrum

PROTECTED_TOKENS = [WANT, LP_COMPONENT, REWARD_TOKEN]
## Fees in Basis Points
DEFAULT_GOV_PERFORMANCE_FEE = 1000
DEFAULT_PERFORMANCE_FEE = 1000
DEFAULT_WITHDRAWAL_FEE = 50

FEES = [DEFAULT_GOV_PERFORMANCE_FEE, DEFAULT_PERFORMANCE_FEE, DEFAULT_WITHDRAWAL_FEE]

REGISTRY = "0xFda7eB6f8b7a9e9fCFd348042ae675d1d652454f"  # Multichain BadgerRegistry
