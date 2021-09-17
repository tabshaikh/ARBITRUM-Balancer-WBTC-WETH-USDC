// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "../interfaces/erc20/IERC20.sol";

import "../interfaces/badger/IController.sol";
import {IVault} from "../interfaces/balancer/IVault.sol";
import {IBalancerPool} from "../interfaces/balancer/IBalancerPool.sol";
import "../interfaces/balancer/IAsset.sol";

import {BaseStrategy} from "../deps/BaseStrategy.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    address public lpComponent; // Token we provide liquidity with
    address public reward; // Token we farm and swap to want / lpComponent

    uint256 public totalDepositedinPool; // tracking total wbtc deposited in the pool

    address public constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8; // Balancer Vault address on Arbitrum
    address public constant HELPER = 0x77d46184d22CA6a3726a2F500c776767b6A3d6Ab; // Balancer Helper Contract Address on Arbitrum - https://github.com/balancer-labs/balancer-v2-monorepo/blob/18bd5fb5d87b451cc27fbd30b276d1fb2987b529/pkg/standalone-utils/contracts/BalancerHelpers.sol
    bytes32 public constant poolId =
        0x64541216bafffeec8ea535bb71fbc927831d0595000100000000000000000002; // Pool Id of WBTC/WETH/USDC Balancer Pool on Arbitrum

    // Found using:
    // >>> vault.getPool(0x64541216bafffeec8ea535bb71fbc927831d0595000100000000000000000002)
    // ("0x64541216bAFFFEec8ea535BB71Fbc927831d0595", 1)
    IBalancerPool public bpt =
        IBalancerPool(0x64541216bAFFFEec8ea535BB71Fbc927831d0595);

    // address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC on Arbitrum
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH on Arbitrum
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC on Arbitrum

    address public constant SUSHISWAP_ROUTER =
        0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506; // SushiSwap router on arbitrum

    uint256 public slippage;
    uint256 public constant MAX_BPS = 10000;

    // Used to signal to the Badger Tree that rewards where sent to it
    event TreeDistribution(
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    function initialize(
        address _governance,
        address _strategist,
        address _controller,
        address _keeper,
        address _guardian,
        address[3] memory _wantConfig,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(
            _governance,
            _strategist,
            _controller,
            _keeper,
            _guardian
        );

        /// @dev Add config here
        want = _wantConfig[0];
        lpComponent = _wantConfig[1];
        reward = _wantConfig[2];

        totalDepositedinPool = 0; // Setting total amount deposit in balancer vault as 0
        slippage = 100; // 1% slippage allowance

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        /// @dev do one off approvals here
        IERC20Upgradeable(want).safeApprove(VAULT, type(uint256).max);
        IERC20Upgradeable(reward).safeApprove(
            SUSHISWAP_ROUTER,
            type(uint256).max
        );
    }

    /// ===== View Functions =====

    // @dev Specify the name of the strategy
    function getName() external pure override returns (string memory) {
        return "Arbitrum-Balancer-WBTC-WETH-USDC-Strategy";
    }

    // @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.0";
    }

    /// @dev Creates the Swap Request Structure required by IBalancerPool.onSwap function
    function _getSwapRequest(
        IERC20 token,
        uint256 amount,
        uint256 lastChangeBlock
    ) public view returns (IBalancerPool.SwapRequest memory request) {
        return
            IBalancerPool.SwapRequest(
                IBalancerPool.SwapKind.GIVEN_IN,
                token,
                IERC20(want),
                amount,
                poolId,
                lastChangeBlock,
                address(this),
                address(this),
                abi.encode(0)
            );
    }

    /// @dev Balance of lpcomponent
    function balanceOfPool() public view override returns (uint256) {
        return IERC20Upgradeable(lpComponent).balanceOf(address(this));
    }

    /// @dev Balance of pool currently held in strategy positions in terms of want.
    function balanceOfPoolinWant() public returns (uint256) {
        uint256 totalWantPooled;
        (
            IERC20[] memory tokens,
            uint256[] memory totalBalances,
            uint256 lastChangeBlock
        ) = IVault(VAULT).getPoolTokens(poolId);
        for (uint8 i = 0; i < 3; i++) {
            uint256 tokenPooled =
                totalBalances[i].mul(balanceOfPool()).div(bpt.totalSupply());
            if (tokenPooled > 0) {
                IERC20 token = tokens[i];
                if (token != IERC20(want)) {
                    IBalancerPool.SwapRequest memory request =
                        _getSwapRequest(token, tokenPooled, lastChangeBlock);
                    // now denomated in want
                    // onSwap gives us the amount that would be returned if the token was to be swapped
                    tokenPooled = bpt.onSwap(request, totalBalances, i, 0); // 0 is tokenIndex of want(WBTC)
                }
                totalWantPooled += tokenPooled;
            }
        }
        return totalWantPooled;
    }

    /// @dev Returns true if this strategy requires tending
    function isTendable() public view override returns (bool) {
        // Checks balance of want token (WBTC) and returns true if balance of want > 0 as we have wbtc to deposit into the strat
        return balanceOfWant() > 0;
    }

    // @dev These are the tokens that cannot be moved except by the vault
    function getProtectedTokens()
        public
        view
        override
        returns (address[] memory)
    {
        address[] memory protectedTokens = new address[](3);
        protectedTokens[0] = want;
        protectedTokens[1] = lpComponent;
        protectedTokens[2] = reward;
        return protectedTokens;
    }

    /// @notice sets slippage tolerance for liquidity provision in terms of BPS ie.
    /// @notice minSlippage = 0
    /// @notice maxSlippage = 10_000
    function setSlippageTolerance(uint256 _s) external whenNotPaused {
        _onlyGovernanceOrStrategist();
        require(_s <= 10_000, "slippage out of bounds");
        slippage = _s;
    }

    /// ===== Internal Core Implementations =====

    /// @dev security check to avoid moving tokens that would cause a rugpull, edit based on strat
    function _onlyNotProtectedTokens(address _asset) internal override {
        address[] memory protectedTokens = getProtectedTokens();

        for (uint256 x = 0; x < protectedTokens.length; x++) {
            require(
                address(protectedTokens[x]) != _asset,
                "Asset is protected"
            );
        }
    }

    /// @dev invest the amount of want
    /// @notice When this function is called, the controller has already sent want to this
    /// @notice Just get the current balance and then invest accordingly
    function _deposit(uint256 _amount) internal override {
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(want);
        assets[1] = IAsset(WETH);
        assets[2] = IAsset(USDC);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _amount;
        amounts[1] = 0;
        amounts[2] = 0;

        bytes memory userData = abi.encode(uint256(1), amounts); // Here 1 is the id for "EXACT_TOKENS_IN_FOR_BPT_OUT"

        IVault.JoinPoolRequest memory request =
            IVault.JoinPoolRequest(assets, amounts, userData, false);

        IVault(VAULT).joinPool(poolId, address(this), address(this), request);

        totalDepositedinPool = totalDepositedinPool.add(_amount);
    }

    function _exitPosition(uint256 _wbtcAmountOut, uint256 _bptAmountIn)
        internal
    {
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(want);
        assets[1] = IAsset(WETH);
        assets[2] = IAsset(USDC);

        uint256[] memory minAmountsOut = new uint256[](3); // minAmountsOut for respective assets
        minAmountsOut[0] = _wbtcAmountOut.mul(slippage).div(MAX_BPS);

        uint256 exitTokenIndex = 0; // As wbtc is the token we want to exit with therefore exitTokenIndex = 0

        bytes memory userData =
            abi.encode(uint256(0), _bptAmountIn, exitTokenIndex); // Here 0: EXACT_BPT_IN_FOR_ONE_TOKEN_OUT

        IVault.ExitPoolRequest memory exit_request =
            IVault.ExitPoolRequest(assets, minAmountsOut, userData, false);

        IVault(VAULT).exitPool(
            poolId,
            address(this),
            payable(address(this)),
            exit_request
        );
    }

    /// @dev utility function to withdraw everything for migration
    function _withdrawAll() internal override {
        uint256 _bptAmountIn = balanceOfPool();
        uint256 _wbtcAmountOut = totalDepositedinPool;

        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(want);
        assets[1] = IAsset(WETH);
        assets[2] = IAsset(USDC);

        uint256[] memory minAmountsOut = new uint256[](3); // minAmountsOut for respective assets
        minAmountsOut[0] = _wbtcAmountOut.mul(slippage).div(MAX_BPS);

        uint256 exitTokenIndex = 0; // As wbtc is the token we want to exit with therefore exitTokenIndex = 0

        bytes memory userData =
            abi.encode(uint256(0), _bptAmountIn, exitTokenIndex); // Here 0: EXACT_BPT_IN_FOR_ONE_TOKEN_OUT

        IVault.ExitPoolRequest memory exit_request =
            IVault.ExitPoolRequest(assets, minAmountsOut, userData, false);

        IVault(VAULT).exitPool(
            poolId,
            address(this),
            payable(address(this)),
            exit_request
        );

        totalDepositedinPool = 0;
    }

    /// @dev withdraw the specified amount of want, liquidate from lpComponent to want, paying off any necessary debt for the conversion
    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        if (_amount > totalDepositedinPool) {
            _amount = totalDepositedinPool;
        }
        uint256 percentageOfWbtcWithdrawn =
            _amount.mul(100).div(totalDepositedinPool);
        _exitPosition(_amount, balanceOfPool() * percentageOfWbtcWithdrawn);
        totalDepositedinPool = totalDepositedinPool.sub(_amount);
    }

    /// @dev Swap Rewards to want token
    function _swapRewards() internal {
        uint256 balanceOfReward =
            IERC20Upgradeable(reward).balanceOf(address(this));
    }

    /// @dev Harvest from strategy mechanics, realizing increase in underlying position
    function harvest() external whenNotPaused returns (uint256 harvested) {
        _onlyAuthorizedActors();

        uint256 _before = IERC20Upgradeable(want).balanceOf(address(this));

        // Write your code here

        // harvest will get the rewards using merkle tree proof
        // BAL rewards will be swapped to wbtc

        uint256 earned =
            IERC20Upgradeable(want).balanceOf(address(this)).sub(_before);

        /// @notice Keep this in so you get paid!
        (uint256 governancePerformanceFee, uint256 strategistPerformanceFee) =
            _processPerformanceFees(earned);

        // TODO: If you are harvesting a reward token you're not compounding
        // You probably still want to capture fees for it
        // // Process Sushi rewards if existing
        // if (sushiAmount > 0) {
        //     // Process fees on Sushi Rewards
        //     // NOTE: Use this to receive fees on the reward token
        //     _processRewardsFees(sushiAmount, SUSHI_TOKEN);

        //     // Transfer balance of Sushi to the Badger Tree
        //     // NOTE: Send reward to badgerTree
        //     uint256 sushiBalance = IERC20Upgradeable(SUSHI_TOKEN).balanceOf(address(this));
        //     IERC20Upgradeable(SUSHI_TOKEN).safeTransfer(badgerTree, sushiBalance);
        //
        //     // NOTE: Signal the amount of reward sent to the badger tree
        //     emit TreeDistribution(SUSHI_TOKEN, sushiBalance, block.number, block.timestamp);
        // }

        /// @dev Harvest event that every strategy MUST have, see BaseStrategy
        emit Harvest(earned, block.number);

        /// @dev Harvest must return the amount of want increased
        return earned;
    }

    // Alternative Harvest with Price received from harvester, used to avoid exessive front-running
    function harvest(uint256 price)
        external
        whenNotPaused
        returns (uint256 harvested)
    {}

    /// @dev Rebalance, Compound or Pay off debt here
    function tend() external whenNotPaused {
        _onlyAuthorizedActors();
    }

    /// ===== Internal Helper Functions =====

    /// @dev used to manage the governance and strategist fee, make sure to use it to get paid!
    function _processPerformanceFees(uint256 _amount)
        internal
        returns (
            uint256 governancePerformanceFee,
            uint256 strategistPerformanceFee
        )
    {
        governancePerformanceFee = _processFee(
            want,
            _amount,
            performanceFeeGovernance,
            IController(controller).rewards()
        );

        strategistPerformanceFee = _processFee(
            want,
            _amount,
            performanceFeeStrategist,
            strategist
        );
    }

    /// @dev used to manage the governance and strategist fee on earned rewards, make sure to use it to get paid!
    function _processRewardsFees(uint256 _amount, address _token)
        internal
        returns (uint256 governanceRewardsFee, uint256 strategistRewardsFee)
    {
        governanceRewardsFee = _processFee(
            _token,
            _amount,
            performanceFeeGovernance,
            IController(controller).rewards()
        );

        strategistRewardsFee = _processFee(
            _token,
            _amount,
            performanceFeeStrategist,
            strategist
        );
    }
}
