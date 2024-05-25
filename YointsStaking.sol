// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract YointsStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Stake {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastStakedTime;
    }

    IERC20 public yointsToken;
    IERC20 public yapesToken;

    bool public rewardsActive = false;

    uint256 public totalStaked;
    uint256 public accYapesPerShare;
    uint256 public rewardRate;
    uint256 public lastRewardTime;
    uint256 public endRewardTime;
    uint256 public lockupDuration = 2 minutes;

    mapping(address => Stake) public stakes;

    // Events
    event StakeAdded(address indexed user, uint256 amount);
    event StakeRemoved(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardsStarted(uint256 startTime);
    event RewardsStopped(uint256 stopTime);

    constructor(IERC20 _yointsToken, IERC20 _yapesToken) Ownable(msg.sender) {
        yointsToken = _yointsToken;
        yapesToken = _yapesToken;
        uint256 annualRewards = 1000000 * 1e18; // Total rewards multiplied by decimals
        rewardRate = annualRewards / 31536000; // Divide first to prevent overflow
        lastRewardTime = block.timestamp;
    }

    function updatePool() internal {
        if (!rewardsActive || block.timestamp <= lastRewardTime) return;

        if (totalStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - lastRewardTime;
        uint256 yapesReward = (timeElapsed * rewardRate) / 1e18; // Apply reward rate
        accYapesPerShare += (yapesReward * 1e12) / totalStaked; // Convert yapesReward into per-share increment
        lastRewardTime = block.timestamp;
    }

    function depositRewards(uint256 amount) external onlyOwner {
        yapesToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Cannot stake 0 tokens");
        Stake storage userStake = stakes[msg.sender];
        updatePool();
        if (userStake.amount > 0) {
            uint256 pending = ((userStake.amount * accYapesPerShare) / 1e12) -
                userStake.rewardDebt;
            if (pending > 0) {
                yapesToken.safeTransfer(msg.sender, pending);
            }
        }
        yointsToken.safeTransferFrom(msg.sender, address(this), _amount);
        userStake.amount += _amount;
        userStake.rewardDebt = (userStake.amount * accYapesPerShare) / 1e12;
        userStake.lastStakedTime = block.timestamp;
        totalStaked += _amount;
        emit StakeAdded(msg.sender, _amount);
    }

    function unstake(uint256 _amount) external nonReentrant {
        Stake storage userStake = stakes[msg.sender];
        require(
            block.timestamp >= userStake.lastStakedTime + lockupDuration,
            "Tokens are locked"
        );
        require(userStake.amount >= _amount, "Not enough staked");
        updatePool();
        uint256 pending = ((userStake.amount * accYapesPerShare) / 1e12) -
            userStake.rewardDebt;
        if (pending > 0) {
            yapesToken.safeTransfer(msg.sender, pending);
        }
        yointsToken.safeTransfer(msg.sender, _amount);
        userStake.amount -= _amount;
        userStake.rewardDebt = (userStake.amount * accYapesPerShare) / 1e12;
        totalStaked -= _amount;
        emit StakeRemoved(msg.sender, _amount);
    }

    function claimReward() external nonReentrant {
        require(rewardsActive, "Rewards are not active.");
        Stake storage userStake = stakes[msg.sender];
        // require(
        //     block.timestamp >= userStake.lastStakedTime + lockupDuration,
        //     "Rewards are locked"
        // );
        updatePool();
        uint256 pending = ((userStake.amount * accYapesPerShare) / 1e12) -
            userStake.rewardDebt;
        uint256 contractBalance = yapesToken.balanceOf(address(this));
        require(
            pending <= contractBalance,
            "Insufficient balance in contract for rewards"
        );
        if (pending > 0) {
            yapesToken.safeTransfer(msg.sender, pending);
            userStake.rewardDebt = (userStake.amount * accYapesPerShare) / 1e12;
            emit RewardClaimed(msg.sender, pending);
        }
    }

    function getPendingRewards(address _user) external returns (uint256) {
        updatePool();
        Stake storage userStake = stakes[_user];
        return
            ((userStake.amount * accYapesPerShare) / 1e12) -
            userStake.rewardDebt;
    }

    function startRewards() external onlyOwner {
        require(!rewardsActive, "Rewards already started.");
        rewardsActive = true;
        lastRewardTime = block.timestamp; // Reset the last reward time to now
        emit RewardsStarted(block.timestamp);
    }

    function stopRewards() external onlyOwner {
        require(rewardsActive, "Rewards already stopped.");
        rewardsActive = false;
        updatePool(); // Final update before stopping
        emit RewardsStopped(block.timestamp);
    }

    // Method for snapshot
    function getTotalStaked(address _user) external view returns (uint256) {
        return stakes[_user].amount;
    }
}
