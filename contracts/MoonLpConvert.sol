pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./uniswapv2/interfaces/IUniswapV2ERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import "./uniswapv2/interfaces/IUniswapV2Factory.sol";
import './uniswapv2/interfaces/IWETH.sol';

contract MoonLpConvert {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Factory public factory;
    address public receiveAddr;
    address public weth;

    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    constructor(IUniswapV2Factory _factory, address _receiveAddr, address _weth) public {
        factory = _factory;
        receiveAddr = _receiveAddr;
        weth = _weth;
    }

    function convert(address token0, address token1) public {
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token0, token1));
        pair.transfer(address(pair), pair.balanceOf(address(this)));
        pair.burn(address(this));

        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));

        uint amount0 = balance0;
        uint amount1 = balance1;

        if(token0 == weth){
            IWETH(weth).withdraw(amount0);
            _safeTransferETH(receiveAddr, amount0);
            _safeTransfer(token1, receiveAddr, amount1);
        }else if(token1 == weth){
          IWETH(weth).withdraw(amount1);
          _safeTransferETH(receiveAddr, amount1);
          _safeTransfer(token0, receiveAddr, amount0);
        }else{
          _safeTransfer(token0, receiveAddr, amount0);
          _safeTransfer(token1, receiveAddr, amount1);
        }
    }

    function forceWithdraw(address token) external
    {
      uint _balance = IERC20(token).balanceOf(address(this));
      _safeTransfer(token, receiveAddr, _balance);
    }


    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'MoonMaker: TRANSFER_FAILED');
    }

    function _safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'MoonMaker: ETH_TRANSFER_FAILED');
    }
}
