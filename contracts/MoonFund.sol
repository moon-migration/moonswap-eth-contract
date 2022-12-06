pragma solidity 0.6.12;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IMasterStar {

  function deposit(uint256 _pid, uint256 _amount) external;
}

interface IMoonFansToken {
   function mint(address _to, uint256 _amount) external;
}

/**
 * Moon transfer conflux blockchain by MoonFund
 * Moon => cMoon process
 */

contract MoonFund is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // receive user deposit Moon
    mapping(address => uint256) public reserves;

    address public fansToken;
    address public masterStar;
    address public moonToken;
    address public confluxStarAddr; // Conflux star Address associated etherum address
    uint256 public endAirdropTime; // it`s conflux farm start mint time (migrate Lp, first etherum stop mint Moon, then Conflux deployed Farm)
    address public confluxAirdropAddr; // crosschain custidian mapping airdrop receive address

    uint256 stakePid; //

    event StakeEvent(address indexed user, uint256 indexed pid, uint256 amount);
    event MintcTokenEvent(address indexed user, uint256 indexed pid, address _to, uint256 amount);
    event SaveEvent(address indexed user, address _to, uint256 amount);
    event RetrieveEvent(address indexed user, uint256 amount);

    constructor(
      address _fansToken,
      address _mastarStar,
      address _moonToken)
      public
    {
       fansToken = _fansToken;
       masterStar = _mastarStar;
       moonToken = _moonToken;
    }

    // before stake, create pool at MasterStar
    // when stake, this contract get FansToken mint operator
    function stake(uint256 _pid, uint256 _amount) external onlyOwner {
      IMoonFansToken(fansToken).mint(address(this), _amount);
      IERC20(fansToken).safeApprove(masterStar, _amount);
      IMasterStar(masterStar).deposit(_pid, _amount);
      stakePid = _pid;
      emit StakeEvent(msg.sender, _pid, _amount);
    }

    function setConfluxStarAddr(address _addr) external onlyOwner {
      require(_addr != address(0), "MoonFund: addr is zero address");
      confluxStarAddr = _addr;
    }

    function setConfluxAirdropAddr(address _addr) external onlyOwner {
      require(_addr != address(0), "MoonFund: addr is zero address");
      confluxAirdropAddr = _addr;
    }

    // the step deposit 0 masterStar,
    function mintcToken() external {
        uint256 _pid = stakePid;
        address _to;
        // before aidrop endtime  transfer moon to airdrop contract
        if(confluxAirdropAddr != address(0) && block.timestamp <= endAirdropTime){
          _to = confluxAirdropAddr;
        } else {
          _to = confluxStarAddr;
        }

        require(_to != address(0), "MoonFund: addr is zero address");
        uint256 beforeBalance = IERC20(moonToken).balanceOf(address(this));
        IMasterStar(masterStar).deposit(_pid, 0);
        uint256 _diffAmount = IERC20(moonToken).balanceOf(address(this)).sub(beforeBalance);
        IERC20(moonToken).safeTransfer(address(_to), _diffAmount);

        emit MintcTokenEvent(msg.sender, _pid, _to, _diffAmount);
    }

    function onlyHarvest() external onlyOwner {
        uint256 _pid = stakePid;
        IMasterStar(masterStar).deposit(_pid, 0);
    }

    function onlyCrossChain(uint256 _amount) external onlyOwner {
        require(_amount > 0, "MoonFund: amount is zero");
        address _to = confluxStarAddr;
        require(_to != address(0), "MoonFund: addr is zero address");
        IERC20(moonToken).safeTransfer(address(_to), _amount);
    }

    function save(uint256 _amount) external {
       address _to = confluxStarAddr;
       require(_amount > 0, "MoonFund: amount is zero");
       require(_to != address(0), "MoonFund: addr is zero address");
       IERC20(moonToken).safeTransferFrom(address(msg.sender), address(this), _amount);
       IERC20(moonToken).safeTransfer(address(_to), _amount);

       reserves[msg.sender] = reserves[msg.sender].add(_amount);
       emit SaveEvent(msg.sender, _to, _amount);
    }

    function retrieve(uint256 _amount) external {
        require(_amount > 0, "MoonFund: amount is zero");
        uint256 balance = IERC20(moonToken).balanceOf(address(this));
        require(_amount < balance, "MoonFund: Balance insufficient");
        uint256 _userAmount = reserves[msg.sender];
        require(_amount <= _userAmount, "MoonFund: retrieve amount overflow");
        reserves[msg.sender] = reserves[msg.sender].sub(_amount);

        IERC20(moonToken).safeTransfer(address(msg.sender), _amount);

        emit RetrieveEvent(msg.sender, _amount);
    }

    function balanceOf() external view returns(uint256){
      return IERC20(moonToken).balanceOf(address(this));
    }

    function setEndAirdropTime(uint256 _time) external onlyOwner {
      endAirdropTime = _time;
    }
}
