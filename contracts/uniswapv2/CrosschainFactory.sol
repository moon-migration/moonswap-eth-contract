pragma solidity =0.6.12;

import './interfaces/ICrosschainFactory.sol';
import './interfaces/ICrosschainPair.sol';
import './CrosschainPair.sol';

contract CrosschainFactory is ICrosschainFactory {
    address public override migrator;
    address public override feeToSetter;
    address public override WETH;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;
    mapping(address => address) public override getCfxReceiveAddr;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor() public {
        feeToSetter = msg.sender;

        uint chainId;
        assembly {
            chainId := chainid()
        }

        WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        if( chainId == 4 ){ // rinkeby
           WETH = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
        }
    }

    function allPairsLength() external override view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, 'MoonSwap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'MoonSwap: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'MoonSwap: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(CrosschainPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        ICrosschainPair(pair).initialize(token0, token1);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setMigrator(address _migrator) external override {
        require(msg.sender == feeToSetter, 'MoonSwap: FORBIDDEN');
        migrator = _migrator;
    }

    // add safe conflux fund contract associated address
    function addCfxReceiveAddr(address token0, address token1, address _receiveAddr) external {
        require(msg.sender == feeToSetter, 'Moonswap: FORBIDDEN');
        require(_receiveAddr != address(0), "MoonSwap: Receive Address is zero");
        address pair = getPair[token0][token1];
        require(pair != address(0), "MoonSwap: Pair no exists");

        getCfxReceiveAddr[pair] = _receiveAddr;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'MoonSwap: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }

    function setWETH(address _weth) external {
        require(msg.sender == feeToSetter, 'MoonSwap: FORBIDDEN');

        require(_weth != address(0), "MoonSwap: weth is zero");

        WETH = _weth;
    }

}
