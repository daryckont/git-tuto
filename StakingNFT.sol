// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


/*
    Staker contract for FUSYONA
    ===================================
    Based on Sushiswap MasterChef https://github.com/sushiswap/sushiswap/blob/archieve/canary/contracts/MasterChefV2.sol.
    The basic idea is to keep an accumulating pool "share balance" (accRewardPerShare):
    Every unit of this balance represents the proportionate reward of a single wei which is staked in the contract.
    This balance is updated in updateRewards() modifer (which is called in each stake/withdraw/harvest)
        according to the time passed from the last update and in proportion to the total tokens staked in the pool.
        Basically: accRewardPerShare = accRewardPerShare + (seconds passed from last update) * (rewards per second) / (total tokens staked)
    We also save for each user (investor) an accumulation of how much he has already harvested so far.
    And so to calculate a investor's rewards, we basically just need to calculate:
    investorRewards = accRewardPerShare * (user's currently staked tokens) - (user's rewards already claimed) 
    And updated the investor's rewards already harvested accordingly.
*/

//import "@openzeppelin/contracts/access/Ownable.sol";stakingToken
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./ABDKMath64x64.sol";

contract StakingNFT {
    using SafeMath for uint256;
    using ABDKMath64x64 for *;
    int128 public fee;

    address immutable fusyona;
    address immutable factory;

     /// @notice Info of each user.
    /// `investedTokens` Staking token amount the user has provided.
    /// `rewardDebt` The amount of reward entitled to the user.
    
    struct InvestorInfo {
        uint256 investedTokens;
        uint256 rewardDebt;
    }

    mapping (address => InvestorInfo) investors;

    IERC1155 public stakingToken;
    IERC20 public rewardToken;

    //state variables
    address public owner;    
    //the total value staked by each investment from investors.
    uint256 public totalStaked;

    //the amount to share among investors by each wei staked.
    uint256 public accRewardPerShare;

    //timestamp to mark the end of the reward period.
    uint256 public rewardPeriodEndTimestamp;
    
    //rate of reward per second.
    uint256 public rewardPerSecond; // multiplied by 1e7, to make up for division by 24*60*60

    //the last timestamp that was rewarded.
    uint256 public lastRewardTimestamp;


    //EVENTS 
    event ChargeRewards(uint256 amount, uint256 lengthInDays);
    event Stake(address indexed user, uint256 amount, uint256 rewardEntitled);
    event Harvest(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event NewOwner(address indexed newOwner, address indexed oldOwner);
    event Skim(uint256 amount);

    //this modifier will be applied each time that once of these events happen: deposit, withdraw, harvest

    modifier onlyOwner() {
        require(msg.sender == owner, "You are not the owner");
        _;
    }

     modifier onlyFactory {
        require(msg.sender == factory, "Your are not a verified operator.");
        _;
    }

    function setFee(int128 _fee) public onlyFactory {
        fee = _fee;
    }

    function _fusyonaFee(uint256 amountToken) public view returns(uint256) {
        return fee.mulu(amountToken);
    }


    //CONSTRUCTOR
    constructor (address _stakingToken, address _rewardToken, address _owner, address _fusyona, address _factory, int128 _fee) {
        stakingToken = IERC1155(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        owner = _owner;
        fusyona = _fusyona;
        factory = _factory;
        fee = _fee;
    }

    //FUNCTIONS

        function updateRewards() public { 
    // If no staking period active, or already updated rewards after staking ended, or nobody staked anything - nothing to do
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        if ((totalStaked == 0) || lastRewardTimestamp > rewardPeriodEndTimestamp) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        
        // If staking period ended, calculate time delta based on the time the staking ended (and not after)
        uint256 endingTime;
        if (block.timestamp > rewardPeriodEndTimestamp) {
            endingTime = rewardPeriodEndTimestamp;
        } else {
            endingTime = block.timestamp;
        }
        uint256 secondsSinceLastRewardUpdate = endingTime.sub(lastRewardTimestamp);
        uint256 totalNewReward = secondsSinceLastRewardUpdate.mul(rewardPerSecond); // For everybody in the pool
        // The next line will calculate the reward for each staked token in the pool.
        //  So when a specific user will claim his rewards,
        //  we will basically multiply this var by the amount the user staked.
        accRewardPerShare = accRewardPerShare.add(totalNewReward.mul(1e12).div(totalStaked));
        lastRewardTimestamp = block.timestamp;
        if (block.timestamp > rewardPeriodEndTimestamp) {
            rewardPerSecond = 0;
        }
    }    


    //the owner should to approve this contract before this function will trigered. 
    function chargeRewards(uint256 _rewardsAmount, uint256 _lengthInDays) external onlyOwner {
        require(block.timestamp > rewardPeriodEndTimestamp, "Staker: can't add rewards before period finished");
        updateRewards();
        rewardPeriodEndTimestamp = block.timestamp.add(_lengthInDays.mul(24*60*60));
        rewardPerSecond = _rewardsAmount.mul(1e7).div(_lengthInDays.mul(24*60*60));
        uint256 profitFusyona = _fusyonaFee(_rewardsAmount);
        require(rewardToken.transferFrom(msg.sender, fusyona, profitFusyona), "Staker: Fail to transfer FUSYONA's profit.");
        require(rewardToken.transferFrom(msg.sender, address(this), _rewardsAmount - profitFusyona), "Staker: transfer failed");
        emit ChargeRewards(_rewardsAmount, _lengthInDays);
    }

    function stake(uint256 tokenId, uint256 amount, bytes calldata data) external {
        InvestorInfo storage investor = investors[msg.sender];
        updateRewards();
        // Send reward for previous deposits
        if (investor.investedTokens > 0) {
            uint256 pending = investor.investedTokens.mul(accRewardPerShare).div(1e12).div(1e7).sub(investor.rewardDebt);
            require(rewardToken.transfer(msg.sender, pending), "Staker: transfer failed");
            emit Harvest(msg.sender, pending);
        }
        investor.investedTokens = investor.investedTokens.add(amount);
        totalStaked = totalStaked.add(amount);
        investor.rewardDebt = investor.investedTokens.mul(accRewardPerShare).div(1e12).div(1e7);
        stakingToken.safeTransferFrom(msg.sender, address(this), tokenId, amount, data);      
        emit Stake(msg.sender, amount, investor.rewardDebt); 
    }

    function withdraw(uint256 tokenId, uint256 amount, bytes calldata data) external {
        InvestorInfo storage investor = investors[msg.sender];
        require(amount <= investor.investedTokens, "Staker: balance not enough.");
        // Send reward for previous deposits
        updateRewards();
        uint256 pending = investor.investedTokens.mul(accRewardPerShare).div(1e12).div(1e7).sub(investor.rewardDebt);
        require(rewardToken.transfer(tx.origin, pending), "Staker: transfer failed");
        emit Harvest(msg.sender, pending);
        investor.investedTokens = investor.investedTokens.sub(amount);
        totalStaked = totalStaked.sub(amount);
        investor.rewardDebt = investor.investedTokens.mul(accRewardPerShare).div(1e12).div(1e7);
        stakingToken.safeTransferFrom(address(this), msg.sender, tokenId, amount, data);
        emit Withdraw(msg.sender, amount);
     }

    function harvest() external {
        InvestorInfo storage investor = investors[msg.sender];
        if (investor.investedTokens == 0) {
            return;
        }
        updateRewards();
        uint256 pending = investor.investedTokens.mul(accRewardPerShare).div(1e12).div(1e7).sub(investor.rewardDebt);
        require(rewardToken.transfer(tx.origin, pending), "Staker: transfer failed");
        emit Harvest(msg.sender, pending);
        investor.rewardDebt = investor.investedTokens.mul(accRewardPerShare).div(1e12).div(1e7);
    } 

    function transferOwnership(address newOwner) public onlyOwner {
        address oldOwner = owner;
        owner = newOwner;
        emit NewOwner(owner, oldOwner);
    }

    function skim(uint256 tokenId, bytes calldata data) external onlyOwner {
        uint256 actuallyPoolBalance = stakingToken.balanceOf(address(this), tokenId);
        require(actuallyPoolBalance > totalStaked, "Staker: Nothing to skim");
        stakingToken.safeTransferFrom(address(this), owner, tokenId, actuallyPoolBalance.sub(totalStaked), data);
        emit Skim(actuallyPoolBalance.sub(totalStaked));
    }

      function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }  
    

    /* 
        ####################################################
        ################## View functions ##################
        ####################################################
    */

    function pendingRewardsToHarvesting(address _investor) public view returns (uint256 pending) {
        InvestorInfo storage investor = investors[_investor];
        uint256 accumulated = accRewardPerShare;
        if (block.timestamp > lastRewardTimestamp && lastRewardTimestamp <= rewardPeriodEndTimestamp && totalStaked != 0) {
            uint256 endingTime;
            if (block.timestamp > rewardPeriodEndTimestamp) {
                endingTime = rewardPeriodEndTimestamp;
            } else {
                endingTime = block.timestamp;
            }
            uint256 secondsSinceLastRewardUpdate = endingTime.sub(lastRewardTimestamp);
            uint256 totalNewReward = secondsSinceLastRewardUpdate.mul(rewardPerSecond);
            accumulated = accumulated.add(totalNewReward.mul(1e12).div(totalStaked));
        }

        pending = investor.investedTokens.mul(accumulated).div(1e12).div(1e7).sub(investor.rewardDebt);
        
    }

    // Returns misc details for the front end.
    function getFrontendView() 
    external view returns (uint256 _rewardPerSecond, uint256 _secondsLeft, uint256 _investedTokens, uint256 _rewardDebt, uint256 _pending) {
        if (block.timestamp <= rewardPeriodEndTimestamp) {
            _secondsLeft = rewardPeriodEndTimestamp.sub(block.timestamp); 
            _rewardPerSecond = rewardPerSecond.div(1e7);
        } // else, anyway these values will default to 0
        _investedTokens = investors[msg.sender].investedTokens;
        _pending = pendingRewardsToHarvesting(msg.sender);
        _rewardDebt = investors[msg.sender].rewardDebt;
    }

}