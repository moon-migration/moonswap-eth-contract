pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./MoonToken.sol";


interface IMigratorStar {
    // Perform LP token migration from legacy UniswapV2 to MoonSwap.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    // Move Asset to conflux chain mint cToken
    function migrate(IERC20 token) external returns (IERC20);
}

// MasterStar is the master of Moon. He can make Moon and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Moon is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterStar is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Moons
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accMoonPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accMoonPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. Moons to distribute per block.
        uint256 lastRewardBlock;  // Last block number that Moons distribution occurs.
        uint256 accTokenPerShare; // Accumulated Moons per share, times 1e12. See below.
        uint256 tokenPerBlock; //  Flag halve block amount
        bool finishMigrate; // migrate crosschain finish pause
        uint256 lockCrosschainAmount; // flag crosschain amount
    }

    // The Moon TOKEN!
    MoonToken public token;
    // Dev address.
    address public devaddr;
    // Early bird plan Lp address.
    address public earlybirdLpAddr;
    // Block number when genesis bonus Moon period ends.
    uint256 public genesisEndBlock;
    // Moon tokens created per block. the
    uint256 public firstTokenPerBlock;
    // Moon tokens created per block. the current halve logic
    uint256 public currentTokenPerBlock;
    // Bonus muliplier for early Token makers.
    uint256 public constant BONUS_MULTIPLIER = 10;
    // Total Miner Token
    uint256 public constant MAX_TOKEN_MINER = 1e18 * 1e8; // 100 million
    // Early bird plan Lp Mint Moon Token
    uint256 public constant BIRD_LP_MINT_TOKEN_NUM = 1250000 * 1e18;
    // Total Miner Token
    uint256 public totalMinerToken;
    // Genesis Miner BlockNum
    uint256 public genesisMinerBlockNum = 50000;
    // halve blocknum
    uint256 public halveBlockNum = 5000000;
    // Total mint block num
    uint256 public totalMinerBlockNum = genesisMinerBlockNum + halveBlockNum * 4; // About four years
    // Flag Start Miner block
    uint256 public firstMinerBlock;
    // max miner block, it is end miner
    uint256 public maxMinerBlock;
    // lastHalveBlock
    uint256 public lastHalveBlock;
    // migrate moon crosschain pool manager
    mapping(uint256 => address) public migratePoolAddrs;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorStar public migrator;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when Token mining starts.
    uint256 public startBlock;
    mapping(address => uint256) internal poolIndexs;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event TokenConvert(address indexed user, uint256 indexed pid, address to, uint256 amount);
    event MigrateWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        MoonToken _moon,
        address _devaddr,
        uint256 _tokenPerBlock,
        uint256 _startBlock
    ) public {
        token = _moon;
        devaddr = _devaddr;
        firstTokenPerBlock = _tokenPerBlock; // 100000000000000000000  1e18
        currentTokenPerBlock = firstTokenPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // admin mint early bird Lp token only once
    function mintEarlybirdToken(address to) public onlyOwner {
      require(earlybirdLpAddr == address(0) && to != address(0), "mint early bird token once");
      earlybirdLpAddr = to;
      totalMinerToken = totalMinerToken.add(BIRD_LP_MINT_TOKEN_NUM);
      token.mint(earlybirdLpAddr, BIRD_LP_MINT_TOKEN_NUM);
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        require(poolIndexs[address(_lpToken)] < 1, "LpToken exists");
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            tokenPerBlock: currentTokenPerBlock,
            accTokenPerShare: 0,
            finishMigrate: false,
            lockCrosschainAmount:0
        }));

        poolIndexs[address(_lpToken)] = poolInfo.length;
    }

    // Update the given pool's Token allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorStar _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        require(migratePoolAddrs[_pid] != address(0), "migrate: no cmoon address");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
        pool.finishMigrate = true;
    }

    // when migrate must set pool cross chain
    function setCrosschain(uint256 _pid, address cmoonAddr) public onlyOwner {
        //PoolInfo storage pool = poolInfo[_pid];
        require(cmoonAddr != address(0), "address invalid");
        migratePoolAddrs[_pid] = cmoonAddr;
    }

    // View function to see pending Token on frontend.
    function pendingToken(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        //uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 lpSupply = pool.lockCrosschainAmount.add(pool.lpToken.balanceOf(address(this)));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            (uint256 genesisPoolReward, uint256 productionPoolReward) = _getPoolReward(pool, pool.tokenPerBlock, pool.tokenPerBlock.div(2));
            (, uint256 lpStakeTokenNum) =
              _assignPoolReward(genesisPoolReward, productionPoolReward);
            accTokenPerShare = accTokenPerShare.add(lpStakeTokenNum.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lockCrosschainAmount.add(pool.lpToken.balanceOf(address(this)));
        //uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        (uint256 genesisPoolReward, uint256 productionPoolReward) =
            _getPoolReward(pool, pool.tokenPerBlock, pool.tokenPerBlock.div(2));
        totalMinerToken = totalMinerToken.add(genesisPoolReward).add(productionPoolReward);

        (uint256 devTokenNum, uint256 lpStakeTokenNum) =
          _assignPoolReward(genesisPoolReward, productionPoolReward);


        if(devTokenNum > 0){
          token.mint(devaddr, devTokenNum);
        }

        if(lpStakeTokenNum > 0){
          token.mint(address(this), lpStakeTokenNum);
        }

        pool.accTokenPerShare = pool.accTokenPerShare.add(lpStakeTokenNum.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number > maxMinerBlock ? maxMinerBlock : block.number;

        // when migrate, and user cross
        if(lpStakeTokenNum > 0 && pool.finishMigrate){
            _transferMigratePoolAddr(_pid, pool.accTokenPerShare);
        }

        if(block.number <= maxMinerBlock && (
          (lastHalveBlock > 0 && block.number > lastHalveBlock &&  block.number.sub(lastHalveBlock) >= halveBlockNum) ||
          (lastHalveBlock == 0 && block.number > genesisEndBlock && block.number.sub(genesisEndBlock) >= halveBlockNum)
        )){
            lastHalveBlock = lastHalveBlock == 0 ?
                genesisEndBlock.add(halveBlockNum) : lastHalveBlock.add(halveBlockNum);
            currentTokenPerBlock = currentTokenPerBlock.div(2);
            pool.tokenPerBlock = currentTokenPerBlock;
        }
    }

    // Deposit LP tokens to MasterStar for Token allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        require(!pool.finishMigrate, "migrate not deposit");
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
            safeTokenTransfer(msg.sender, pending);
        }
        if(firstMinerBlock == 0 && _amount > 0){ // first deposit
           firstMinerBlock = block.number > startBlock ? block.number : startBlock;
           genesisEndBlock = firstMinerBlock.add(genesisMinerBlockNum);
           maxMinerBlock = firstMinerBlock.add(totalMinerBlockNum);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterStar.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(_amount > 0, "user amount is zero");
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
        safeTokenTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
        if(pool.finishMigrate) { // finish migrate record user withdraw lpToken
            pool.lockCrosschainAmount = pool.lockCrosschainAmount.add(_amount);
            _depositMigratePoolAddr(_pid, pool.accTokenPerShare, _amount);

            emit MigrateWithdraw(msg.sender, _pid, _amount);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        require(_amount > 0, "user amount is zero");
        user.amount = 0;
        user.rewardDebt = 0;

        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
        if(pool.finishMigrate){ //finish migrate record user withdraw lpToken
            pool.lockCrosschainAmount = pool.lockCrosschainAmount.add(_amount);
            _depositMigratePoolAddr(_pid, pool.accTokenPerShare, _amount);

            emit MigrateWithdraw(msg.sender, _pid, _amount);
        }
    }

    // Safe Token transfer function, just in case if rounding error causes pool to not have enough Tokens.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        if (_amount > tokenBal) {
            token.transfer(_to, tokenBal);
        } else {
            token.transfer(_to, _amount);
        }
    }

    //  users convert LpToken crosschain conflux
    function tokenConvert(uint256 _pid, address _to) public {
      PoolInfo storage pool = poolInfo[_pid];
      require(pool.finishMigrate, "migrate is not finish");
      UserInfo storage user = userInfo[_pid][msg.sender];
      uint256 _amount = user.amount;
      require(_amount > 0, "user amount is zero");
      updatePool(_pid);
      uint256 pending = _amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
      safeTokenTransfer(msg.sender, pending);
      user.amount = 0;
      user.rewardDebt = 0;
      pool.lpToken.safeTransfer(_to, _amount);

      pool.lockCrosschainAmount = pool.lockCrosschainAmount.add(_amount);
      _depositMigratePoolAddr(_pid, pool.accTokenPerShare, _amount);
      emit TokenConvert(msg.sender, _pid, _to, _amount);

    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    // after migrate, deposit LpToken same amount
    function _depositMigratePoolAddr(uint256 _pid, uint256 _poolAccTokenPerShare, uint256 _amount) internal
    {
      address migratePoolAddr = migratePoolAddrs[_pid];
      require(migratePoolAddr != address(0), "address invaid");

      UserInfo storage user = userInfo[_pid][migratePoolAddr];
      user.amount = user.amount.add(_amount);
      user.rewardDebt = user.amount.mul(_poolAccTokenPerShare).div(1e12);
    }

    // after migrate, mint LpToken's moon to address
    function _transferMigratePoolAddr(uint256 _pid, uint256 _poolAccTokenPerShare) internal
    {
        address migratePoolAddr = migratePoolAddrs[_pid];
        require(migratePoolAddr != address(0), "address invaid");

        UserInfo storage user = userInfo[_pid][migratePoolAddr];
        if(user.amount > 0){
          uint256 pending = user.amount.mul(_poolAccTokenPerShare).div(1e12).sub(user.rewardDebt);
          safeTokenTransfer(migratePoolAddr, pending);

          user.rewardDebt = user.amount.mul(_poolAccTokenPerShare).div(1e12);
        }
    }

    function _getPoolReward(PoolInfo memory pool,
      uint256 beforeTokenPerBlock,
      uint256 afterTokenPerBlock) internal view returns(uint256, uint256){
      (uint256 genesisBlocknum, uint256 beforeBlocknum, uint256 afterBlocknum)
          = _getPhaseBlocknum(pool);
      uint256 _genesisPoolReward = genesisBlocknum.mul(BONUS_MULTIPLIER).mul(firstTokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
      uint256 _beforePoolReward = beforeBlocknum.mul(beforeTokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
      uint256 _afterPoolReward = afterBlocknum.mul(afterTokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
      uint256 _productionPoolReward = _beforePoolReward.add(_afterPoolReward);
      // ignore genesis poolReward
      if(totalMinerToken.add(_productionPoolReward) > MAX_TOKEN_MINER){
        _productionPoolReward = totalMinerToken > MAX_TOKEN_MINER ? 0 : MAX_TOKEN_MINER.sub(totalMinerToken);
      }

      return (_genesisPoolReward, _productionPoolReward);
    }

    function _getPhaseBlocknum(PoolInfo memory pool) internal view returns(
      uint256 genesisBlocknum,
      uint256 beforeBlocknum,
      uint256 afterBlocknum
    ){
      genesisBlocknum = 0;
      beforeBlocknum = 0;
      afterBlocknum = 0;

      uint256 minCurrentBlock = maxMinerBlock > block.number ? block.number : maxMinerBlock;

      if(minCurrentBlock <= genesisEndBlock){
        genesisBlocknum = minCurrentBlock.sub(pool.lastRewardBlock);
      }else if(pool.lastRewardBlock >= genesisEndBlock){
        // when genesisEndBlock end, start halve logic
        uint256 expectHalveBlock = lastHalveBlock.add(halveBlockNum);
        if(minCurrentBlock <= expectHalveBlock){
          beforeBlocknum = minCurrentBlock.sub(pool.lastRewardBlock);
        }else if(pool.lastRewardBlock >= expectHalveBlock){
          //distance next halve
          beforeBlocknum = minCurrentBlock.sub(pool.lastRewardBlock);
        }else{
          beforeBlocknum = expectHalveBlock.sub(pool.lastRewardBlock);
          afterBlocknum = minCurrentBlock.sub(expectHalveBlock);
        }
      }else{
          genesisBlocknum = genesisEndBlock.sub(pool.lastRewardBlock);
          beforeBlocknum = minCurrentBlock.sub(genesisEndBlock);
      }
   }

   function _assignPoolReward(uint256 genesisPoolReward, uint256 productionPoolReward) internal view returns(
    uint256 devTokenNum,
    uint256 lpStakeTokenNum
   ) {
     if(genesisPoolReward > 0){
       // genesis period ratio 10 90 update
       devTokenNum = devTokenNum.add(genesisPoolReward.mul(10).div(100));
       lpStakeTokenNum = lpStakeTokenNum.add(genesisPoolReward.sub(devTokenNum));
     }

     if(productionPoolReward > 0){
       // Production period ratio 10 90
       devTokenNum = devTokenNum.add(productionPoolReward.mul(10).div(100));
       lpStakeTokenNum = lpStakeTokenNum.add(productionPoolReward.sub(devTokenNum));
     }
   }
}
