// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts@v4.9.3/token/ERC20/IERC20.sol";

import "../interfaces/IYearnBoostedStaker.sol";
import "../interfaces/IRewardsDistributor.sol";

contract YBSUtilities {

    uint constant PRECISION = 1e18;
    uint constant WEEKS_PER_YEAR = 52;
    uint public immutable MAX_STAKE_GROWTH_WEEKS;
    IERC20 public immutable TOKEN;
    IYearnBoostedStaker public immutable YBS;
    IRewardsDistributor public immutable REWARDS_DISTRIBUTOR;

    constructor(
        IYearnBoostedStaker _ybs,
        IRewardsDistributor _rewardsDistributor
    ) {
        YBS = _ybs;
        REWARDS_DISTRIBUTOR = _rewardsDistributor;
        TOKEN = YBS.stakeToken();
        MAX_STAKE_GROWTH_WEEKS = YBS.MAX_STAKE_GROWTH_WEEKS();
    }

    // Boost multiplier based on last week's finalization
    function getUserActiveBoostMultiplier(address _user) external view returns (uint) {
        uint currentWeek = getWeek();
        // Ignore current week stake
        uint balance = YBS.balanceOf(_user) - getAccountStakeAmountAt(_user, currentWeek);
        if (balance == 0) return 0;
        // Ignore last week weight ()
        uint weight = adjustedAccountWeightAt(_user, currentWeek - 1);
        if (weight == 0) return 0;
        return weight * PRECISION / balance;
    }

    // Boost multiplier if week were to end today
    function getUserProjectedBoostMultiplier(address _user) external view returns (uint) {
        uint currentWeek = getWeek();
        uint balance = YBS.balanceOf(_user);
        if (balance == 0) return 0;
        uint weight = adjustedAccountWeightAt(_user, currentWeek);
        if (weight == 0) return 0;
        return weight * PRECISION / balance;
    }

    function getUserActiveApr(address _account, uint _stakeTokenPrice, uint _rewardTokenPrice) external view returns (uint) {
        if (_stakeTokenPrice == 0 || _rewardTokenPrice == 0) return 0;
        uint currentWeek = getWeek();
        if(currentWeek == 0) return 0;
        uint rewardsAmount = activeRewardAmount();
        if (rewardsAmount == 0) return 0;
        uint userShare = REWARDS_DISTRIBUTOR.computeSharesAt(_account, currentWeek - 1);
        if (userShare == 0) return 0;
        uint userRewards = userShare * rewardsAmount;
        if (userRewards == 0) return 0;
        uint userStakedBalance = YBS.balanceOf(_account) - getAccountStakeAmountAt(_account, currentWeek);
        if (userStakedBalance == 0) return 0;
        return (_rewardTokenPrice * userRewards) * WEEKS_PER_YEAR / (userStakedBalance * _stakeTokenPrice);
    }

    function getUserProjectedApr(address _account, uint _stakeTokenPrice, uint _rewardTokenPrice) public view returns (uint) {
        if (_stakeTokenPrice == 0 || _rewardTokenPrice == 0) return 0;
        uint currentWeek = getWeek();
        if(currentWeek == 0) return 0;
        uint rewardsAmount = projectedRewardAmount();
        if (rewardsAmount == 0) return 0;
        uint userShare = REWARDS_DISTRIBUTOR.computeSharesAt(_account, currentWeek);
        if (userShare == 0) return 0;
        uint userRewards = userShare * rewardsAmount;
        if (userRewards == 0) return 0;
        uint userStakedBalance = YBS.balanceOf(_account);
        if (userStakedBalance == 0) return 0;
        return (_rewardTokenPrice * userRewards) * WEEKS_PER_YEAR / (userStakedBalance * _stakeTokenPrice);
    }

    function getGlobalActiveBoostMultiplier() public view returns (uint) {
        uint currentWeek = getWeek();
        uint supply = YBS.totalSupply() - getGlobalStakeAmountAt(currentWeek);
        if (supply == 0) return 0;
        uint weight = adjustedGlobalWeightAt(currentWeek - 1);
        if (weight == 0) return 0;
        return weight * PRECISION / supply;
    }

    function getGlobalProjectedBoostMultiplier() public view returns (uint) {
        uint currentWeek = getWeek();
        uint supply = YBS.totalSupply();
        if (supply == 0) return 0;
        uint weight = adjustedGlobalWeightAt(currentWeek);
        if (weight == 0) return 0;
        return weight * PRECISION / supply;
    }
    

    function getGlobalActiveApr(uint _stakeTokenPrice, uint _rewardTokenPrice) public view returns (uint) {
        if (getGlobalActiveBoostMultiplier() == 0) return 0;
        if (_stakeTokenPrice == 0 || _rewardTokenPrice == 0) return 0;
        uint currentWeek = getWeek();
        if(currentWeek == 0) return 0;
        uint rewardsAmount = activeRewardAmount();
        if (rewardsAmount == 0) return 0;
        // Get total supply, but reduce by amount that has been staked in current week
        uint supply = YBS.totalSupply() - getGlobalStakeAmountAt(currentWeek);
        if (supply == 0) return 0;
        return (
            rewardsAmount * 
            _rewardTokenPrice *
            PRECISION /
            (supply * _stakeTokenPrice)
            * WEEKS_PER_YEAR
        );
    }

    function getGlobalProjectedApr(uint _stakeTokenPrice, uint _rewardTokenPrice) public view returns (uint) {
        if (_stakeTokenPrice == 0 || _rewardTokenPrice == 0) return 0;
        uint currentWeek = getWeek();
        uint rewardsAmount = projectedRewardAmount();
        if (rewardsAmount == 0) return 0;
        uint supply = YBS.totalSupply();
        if (supply == 0) return 0;
        return (
            rewardsAmount * 
            _rewardTokenPrice * 
            PRECISION /
            (supply * _stakeTokenPrice)
            * WEEKS_PER_YEAR
        );
    }

    function getGlobalMinMaxActiveApr(uint _stakeTokenPrice, uint _rewardTokenPrice) external view returns (uint min, uint max) {
        return getGlobalMinMaxApr(true, _stakeTokenPrice, _rewardTokenPrice);
    }
    function getGlobalMinMaxProjectedApr(uint _stakeTokenPrice, uint _rewardTokenPrice) external view returns (uint min, uint max) {
        return getGlobalMinMaxApr(false, _stakeTokenPrice, _rewardTokenPrice);
    }

    function getGlobalMinMaxApr(bool _active, uint _stakeTokenPrice, uint _rewardTokenPrice) internal view returns (uint min, uint max) {
        uint avgApr = _active ? 
            getGlobalActiveApr(_stakeTokenPrice, _rewardTokenPrice) :
            getGlobalProjectedApr(_stakeTokenPrice, _rewardTokenPrice);

        if(avgApr == 0) return (0, 0);

        uint avgBoost = _active ?
            getGlobalActiveBoostMultiplier() :
            getGlobalProjectedBoostMultiplier();

        if(avgBoost == 0) return (0, 0);
        uint minApr = avgApr * _minBoost() / avgBoost;
        uint maxApr = avgApr * _maxBoost() / avgBoost;
        return (minApr, maxApr);
    }

    function getAccountStakeAmountAt(address _account, uint _week) public view returns (uint) {
        uint regularStake = 2 * YBS.accountWeeklyToRealize(_account, _week + MAX_STAKE_GROWTH_WEEKS).weightPersistent;
        return regularStake + YBS.accountWeeklyMaxStake(_account, _week);
    }

    function getGlobalStakeAmountAt(uint _week) public view returns (uint) {
        uint regularStake = 2 *  YBS.globalWeeklyToRealize(_week + MAX_STAKE_GROWTH_WEEKS).weightPersistent;
        return regularStake + YBS.globalWeeklyMaxStake(_week);
    }

    function _minBoost() internal pure returns (uint) {
        return PRECISION; // 1x is the min
    }

    function _maxBoost() internal view returns (uint) {
        return _minBoost() * (MAX_STAKE_GROWTH_WEEKS + 1);
    }

    function adjustedAccountWeightAt(address _account, uint _week) public view returns (uint) {
        uint acctWeight = YBS.getAccountWeightAt(_account, _week);
        if (acctWeight == 0) return 0;
        return acctWeight - YBS.accountWeeklyToRealize(_account, _week + MAX_STAKE_GROWTH_WEEKS).weightPersistent;
    }

    function adjustedGlobalWeightAt(uint _week) public view returns (uint) {
        uint globalWeight = YBS.getGlobalWeightAt(_week);
        if (globalWeight == 0) return 0;
        return globalWeight - YBS.globalWeeklyToRealize(_week + MAX_STAKE_GROWTH_WEEKS).weightPersistent;
    }
    
    function activeRewardAmount() public view returns (uint) {
        uint week = getWeek();
        if(week == 0) return 0;
        return weeklyRewardAmountAt(week - 1);
    }

    function projectedRewardAmount() public view returns (uint) {
        uint week = getWeek();
        return weeklyRewardAmountAt(week);
    }

    function weeklyRewardAmountAt(uint _week) public view returns (uint) {
        return REWARDS_DISTRIBUTOR.weeklyRewardAmount(_week);
    }

    function getWeek() public view returns (uint) {
        return YBS.getWeek();
    }
}