pragma solidity 0.6.12;

import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import "./uniswapv2/interfaces/IUniswapV2Factory.sol";
import "./uniswapv2/interfaces/ICrosschainPair.sol";
import "./uniswapv2/interfaces/ICrosschainFactory.sol";


contract Migrator {
    address public master;
    ICrosschainFactory public factory;
    uint256 public notBeforeBlock;
    uint256 public desiredLiquidity = uint256(-1);
    mapping(address => bool) public originalFactories;
    address public operatorAddr;

    constructor(
        address _master,
        address[] memory _oldFactories,
        ICrosschainFactory _factory,
        uint256 _notBeforeBlock
    ) public {
        master = _master;
        factory = _factory;
        notBeforeBlock = _notBeforeBlock;

        operatorAddr = msg.sender;
        uint range = _oldFactories.length;
        require(range > 0, "Migrate: oldFactory Empty");

        for (uint i = 0; i < range; i++) {
            originalFactories[_oldFactories[i]] = true;
        }
    }

    function migrate(IUniswapV2Pair orig) public returns (ICrosschainPair) {
        require(msg.sender == master, "not from master access");
        require(block.number >= notBeforeBlock, "too early to migrate");
        require(originalFactories[orig.factory()], "not from old factory");
        address token0 = orig.token0();
        address token1 = orig.token1();
        ICrosschainPair pair = ICrosschainPair(factory.getPair(token0, token1));
        if (pair == ICrosschainPair(address(0))) {
            pair = ICrosschainPair(factory.createPair(token0, token1));
        }

        uint256 lp = orig.balanceOf(msg.sender);
        if (lp == 0) return pair;
        desiredLiquidity = lp;
        orig.transferFrom(msg.sender, address(orig), lp);
        orig.burn(address(pair));
        pair.mint(msg.sender);
        desiredLiquidity = uint256(-1);

        return pair;
    }

    function setOperatorAddr(address _operatorAddr) external {
        require(msg.sender == operatorAddr, 'MoonSwap: FORBIDDEN');
        operatorAddr = _operatorAddr;
    }

    // when config update, operator immediately change Factory
    function setOriginalFactory(address _factory, bool _status) external {
        require(msg.sender == operatorAddr, 'MoonSwap: FORBIDDEN');
        originalFactories[_factory] = _status;
    }
}
