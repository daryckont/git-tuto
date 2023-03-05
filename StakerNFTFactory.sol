// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./StakingNFT.sol";

contract StakerNFTFactory is Ownable {
  using Counters for Counters.Counter;
  Counters.Counter private pids;

  int128 constant public DEFAULT_FEE = (int128(5) * int128(2**64))/ int128(100); //5%
  IERC20 erc20;

  struct Pool {
    uint256 pid;
    address owner;
    address spa;
    address stakingToken;
    address rewardToken;
  }
  
  //this array contain all pools that have been listed
  uint256[] listed;

  //Pool's info through owner and pid <owner, pid, Pool Objet>
  mapping (uint256 => Pool) private _dataPools;

  //Total Sp owned by an user <address owner, quantity of pools >
  mapping (address => uint256) private _quantity;
  
  //owner of Sp <pid, address owner>
  mapping (uint256 => address) private _owners;
  
  //Pid's index in listed array <pid, indexInListedArray>
  mapping (uint256 => uint256) private _indexByPid;
  
  // All pids owned by an user <address user,  index of pid in _quantity map, pid>
  mapping (address => mapping (uint256 => uint256)) private _ownedPid;  


  event NewPoolListed(uint256 indexed _pid, address indexed _owner);
  event PoolUnlisted(uint256 indexed _pid, address indexed _owner);

  function list(address stakingAddress, address rewardAddress) external {
    //require(rewardAddress != stakingAddress, "Same addresses");
    require(rewardAddress != address(0) && stakingAddress != address(0));
    StakingNFT newSpool = new StakingNFT(stakingAddress, rewardAddress, msg.sender, address(this), address(this), DEFAULT_FEE);
    
    pids.increment();
    uint256 _pid = pids.current();

    Pool memory sPool = Pool({
      pid: _pid,
      owner: msg.sender,
      spa: address(newSpool),
      stakingToken: stakingAddress,
      rewardToken: rewardAddress
    });

    _mintTo(msg.sender, _pid, sPool);

    uint256 indexMap = _quantity[msg.sender];
    _ownedPid[msg.sender][indexMap] = _pid;
    listed.push(_pid);
    _indexByPid[_pid] = listed.length;
  
    emit NewPoolListed(_pid, msg.sender);
  
  }

  function unlist(uint256 pid) external onlyOwner {
    require(poolExist(pid), "Factory: Pool not found.");
    address _owner = _owners[pid];
    uint256 index = _indexByPid[pid];
    uint256 indexMap = _quantity[msg.sender];
    delete _ownedPid[_owner][indexMap];
    _burnTo(_owner, pid);
    _popIndexTarget(index, listed);
    emit PoolUnlisted(pid, _owner);
  }

  function setFeeTo(uint256 pid, int128 fee) external onlyOwner {
    require(poolExist(pid), "Factory: Pool not found.");
    address spa = _dataPools[pid].spa;
    StakingNFT staker = StakingNFT(spa);
    staker.setFee(fee);
  }

  function withdrawFusyona(address _erc20, address vault) public onlyOwner returns(bool) {
    erc20 = IERC20(_erc20);
    return erc20.transfer(vault, erc20.balanceOf(address(this)));
  }

  function plotQtyPoolsListed () external view returns (uint256) {
    return listed.length;
  }

  function plotAllPid () external view returns (uint256[] memory) {
    return listed;
  }

   function getPoolInfo(uint256 pid) external view returns(Pool memory) {
    return _dataPools[pid];
  }

  function getPidByIndex(uint256 index) external view returns(uint256) {
    return listed[index];
  }
  
  function getTotalSpByUser(address user) external view returns (uint256) {
    return _quantity[user];
  }

  function getPidByUserIndexMap(address user, uint256 index) external view returns (uint256) {
    return _ownedPid[user][index];
  }

  function poolExist(uint256 pid) public view returns (bool) {
    uint256 index = _indexByPid[pid];
    return index <= listed.length;    
  }
  
  function _mintTo(address recipient, uint256 pid, Pool memory newSp) internal {
    _dataPools[pid] = newSp;
    _owners[pid] = recipient;
    _quantity[recipient] +=1;
  }

  function _burnTo(address user, uint256 pid) internal {
    delete _dataPools[pid];
    delete _owners[pid];
    _quantity[user] -=1;
  }

  function _popIndexTarget(uint256 indexTarget, uint256[] storage _list) internal {
     uint256 lastIndex = _list.length - 1;
     _list[indexTarget] = _list[lastIndex];
    _list.pop();
  }
}

