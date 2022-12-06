pragma solidity =0.6.12;

import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/ICrosschainFactory.sol';
import './interfaces/IUniswapV2Callee.sol';
import './interfaces/IWETH.sol';

interface IMigrator {
    // Return the desired amount of liquidity token that the migrator wants.
    function desiredLiquidity() external view returns (uint256);
}

contract CrosschainPair is UniswapV2ERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    address public WETH;
    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves
    struct PairMigration {
      uint migrateLiquidity;     // migrator total liquidity
      uint amount0;
      uint amount1;
    }

    PairMigration public pairMigration;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Moonswap: TRANSFER_FAILED');
    }

    function _safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'Moonswap: ETH_TRANSFER_FAILED');
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);

    constructor() public {
        factory = msg.sender;

        WETH = ICrosschainFactory(factory).WETH();
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'Moonswap: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    //
    function mint(address to) external lock returns (uint liquidity) {
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0;
        uint amount1 = balance1;

        address migrator = ICrosschainFactory(factory).migrator();
        require(msg.sender == migrator, "Moonswap: FORBIDDEN");
        liquidity = IMigrator(migrator).desiredLiquidity();
        require(liquidity > 0, 'Moonswap: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        pairMigration.migrateLiquidity = pairMigration.migrateLiquidity.add(liquidity);
        pairMigration.amount0 = pairMigration.amount0.add(amount0);
        pairMigration.amount1 = pairMigration.amount1.add(amount1);

        // move asset for crosschain safe address audit the process
        address _receiveAddress = ICrosschainFactory(factory).getCfxReceiveAddr(address(this));
        require(_receiveAddress != address(0), 'Moonswap: receive is ZERO_ADDRESS');

        if(token0 == WETH){
            IWETH(WETH).withdraw(amount0);
            _safeTransferETH(_receiveAddress, amount0);
        }else{
            _safeTransfer(token0, _receiveAddress, amount0);
        }

        if(token1 == WETH){
            IWETH(WETH).withdraw(amount1);
            _safeTransferETH(_receiveAddress, amount1);
        }else{
            _safeTransfer(token1, _receiveAddress, amount1);
        }

        emit Mint(msg.sender, amount0, amount1);
    }
}
