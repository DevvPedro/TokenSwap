// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error Swap_SharesZero();
error Swap_PoolNotAvailable();
error Swap_TransferFailed();
error Swap_NonZero();

contract Swap{

    IERC20 public tokenA;
    IERC20 public tokenB;

    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public totalShares;

    mapping(address => uint) public balanceOf;

    constructor(IERC20 _addressA, IERC20 _addressB) {
        tokenA = _addressA;
        tokenB = _addressB;
    }

    function swap(address _tokenIn,  uint amountIn) external returns( uint256 amountOut) {
        if (amountIn == 0) {
            revert Swap_PoolNotAvailable();
        }
        if(_tokenIn != address(tokenA) ||  _tokenIn != address(tokenB)) {
            revert Swap_PoolNotAvailable();
        }

            bool isTokenin = _tokenIn == address(tokenA);
            (IERC20 tokenIn, IERC20 tokenOut,
             uint reserveIn, uint reserveOut 
             ) = isTokenin
            ?(tokenA ,tokenB, reserveA, reserveB)
            :(tokenB, tokenA, reserveB, reserveA);
        
             
          bool success = tokenIn.transferFrom(msg.sender,address(this),amountIn);
          if(!success) {
              revert Swap_TransferFailed();
          }
          uint amountInWithFee = (amountIn * 997) / 1000 ;
         // dy = (y * dx)/ x + dx
          amountOut = (reserveIn * amountInWithFee) / (reserveOut + amountInWithFee);

          bool successful = tokenOut.transfer(msg.sender,amountOut);
          if(!successful) {
              revert Swap_TransferFailed();
          }

          _trackReserve(
              tokenA.balanceOf(address(this)),
              tokenB.balanceOf(address(this))
          );

    }

    function _mint(address user, uint amount) private  {
        balanceOf[user] += amount;
        totalShares -= amount;
    }

    function _burn(address user,uint amount) private {
        balanceOf[user] -= amount;
        totalShares -=amount;
    }

    function _trackReserve(uint _reserveA, uint _reserveB) private {
     reserveA = _reserveA;
     reserveB = _reserveB;

    }

    function addLiquidity (uint256 _amountA, uint256 _amountB) external returns(uint shares) {
         tokenA.transferFrom(msg.sender,address(this),_amountA);
         tokenB.transferFrom(msg.sender,address(this), _amountB);

         //since dy = ydx/x
         if(reserveA > 0 || reserveB > 0) {
             require(reserveA * _amountB == reserveB * _amountA, "dy/dx != y/x");
         }

         if (totalShares == 0) {
             shares = squareRoot(_amountA * _amountB);
         }

         else {
             shares = _min((_amountA * totalShares ) / reserveA,
                          (_amountB  * totalShares) / reserveB);
         }
         if(shares < 0) {
            revert Swap_SharesZero();
         }
         _mint(msg.sender,shares);
    }

    function squareRoot(uint y) private pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;

            while (x > z) {
                z = x;
                x =( y / x + x ) / 2;
            }
            } else if (y != 0) {
                z = 1;
            }

        }

    function removeLiquidity(uint _shares) external returns (uint amount1,uint amount2) {
        uint balanceA = tokenA.balanceOf(address(this));
        uint balanceB = tokenB.balanceOf(address(this));

        amount1 = (_shares * balanceA) / totalShares;
        amount2 = (_shares * balanceB) / totalShares;

        _burn(msg.sender, _shares);

        _trackReserve(
            balanceA - amount1,
            balanceB - amount2
        );

        tokenA.transfer(msg.sender,amount1);
        tokenB.transfer(msg.sender,amount2);

    }

    function _min(uint x, uint y) private pure returns(uint) {
        return x <= y ? x : y;
    }


}