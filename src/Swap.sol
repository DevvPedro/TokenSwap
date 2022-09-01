// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error Swap_SharesZero();
error Swap_PoolNotAvailable();
error Swap_TransferFailed();
error Swap_NonZero();

contract Swap{

    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

     /// EVENTS ///
    event Purchased (address indexed user, uint indexed amountIn, uint indexed amountOut);
    event AddLiquidity(address indexed user, uint indexed amountA, uint indexed amountB);
    event RemoveLiquidity(address indexed user, uint indexed amountA, uint indexed amountB);
    

    //The reserve balance of tokenA
    uint256 public reserveA;
    //The rserve balance of tokenB
    uint256 public reserveB;
    // Liquidity provider tokens
    uint256 public totalShares;

    mapping(address => uint) public balanceOf;

    constructor(IERC20 _addressA, IERC20 _addressB) {
        tokenA = _addressA;
        tokenB = _addressB;
    }


    /** The swap function is called by users who want to trade either of tokenA or tokenB
     * The amount to be returned in the swap is governed by this formula "reserveB * amountIn(A) /reserveA = reserveA * amountIn(B)/reserveB"
     * @param _tokenIn address: The address of the token to be swapped must be either tokenA or tokenB
     * @param _amountIn uint256: The amount the caller of the function wants to swap
     * @notice There will be fees , 0.3% of tme amount transferred in
     * @return _amountOut the number of tokens to be given out with respect to the formula
     */
    function swap(address _tokenIn,  uint _amountIn) external returns( uint256 _amountOut) {
        if (_amountIn == 0) {
            revert Swap_PoolNotAvailable();
        }
        //if tokenIn is neither of tokenA and tokenB this function will revert
        if(_tokenIn != address(tokenA) ||  _tokenIn != address(tokenB)) {
            revert Swap_PoolNotAvailable();
        }
          // _tokenA is assumed to be address(tokenA) if true tokenA will be transferred to the contract,
          //If false automatically _tokenIn becomes address(tokenB)
          // The same applies to reserveA and rserveB
            bool isTokenin = _tokenIn == address(tokenA);
            (IERC20 tokenIn, IERC20 tokenOut,
             uint reserveIn, uint reserveOut 
             ) = isTokenin
            ?(tokenA ,tokenB, reserveA, reserveB)
            :(tokenB, tokenA, reserveB, reserveA);
        
             
          bool success = tokenIn.transferFrom(msg.sender,address(this),_amountIn);
          if(!success) {
              revert Swap_TransferFailed();
          }

          //deduction of the 0.3% fee
          uint amountInWithFee = (_amountIn * 997) / 1000 ;
         // dy = (y * dx)/ x + dx
          _amountOut = (reserveIn * amountInWithFee) / (reserveOut + amountInWithFee);

          bool successful = tokenOut.transfer(msg.sender,_amountOut);
          if(!successful) {
              revert Swap_TransferFailed();
          }
         
          _trackReserve(
              tokenA.balanceOf(address(this)),
              tokenB.balanceOf(address(this))
          );

          emit Purchased(msg.sender,_amountIn,_amountOut);

    }

     /**
     * Called by liquidity providers. Must provide the same value of `amountA` as `amountB` in order to respect the current reserve ratio
     * reserve formula to respect: (_amountA/reserveA) * totalShares = (_amountB/reserveB) * totalShares
     * @param _amountA uint256: input amount of token that liquidity provider is depositing
     * @param _amountB uint256: input amount of token that liquidity provider is depositing
     * @return shares uint256: amount of shares to be rewarded to the liquidity provider
     * @notice it allow the 1st liquidity provider to decide on the initial reserve ratio
     * @notice if totalShares equals 0, the Liquidity providers share will be the product of the squareRoot of both amounts provided
     * @notice rewards liquidity provider with pool tokens called "Shares"
     * @notice Shares is proportional to the amount of both tokens provided comparatively to the total reserve of both tokens
     */

    function addLiquidity (uint256 _amountA, uint256 _amountB) external returns(uint shares) {
        if(_amountA == 0) {
            revert Swap_NonZero();
        }
        if (_amountB == 0) {
            revert Swap_NonZero();
        }
         tokenA.transferFrom(msg.sender,address(this),_amountA);
         tokenB.transferFrom(msg.sender,address(this), _amountB);

         //since dy = ydx/x
         if(reserveA > 0 || reserveB > 0) {
             require(reserveA * _amountB == reserveB * _amountA, "dy/dx != y/x");
         }
        
         if (totalShares == 0) {
             shares = _squareRoot(_amountA * _amountB);
         }

         else {
            //multiplication before division to avoid precision errors
            // _min determines the lowest because any of the equation can be used
             shares = _min((_amountA * totalShares ) / reserveA,
                          (_amountB  * totalShares) / reserveB);
         }
         if(shares < 0) {
            revert Swap_SharesZero();
         }
         // assigns shares to liquidity providers
         _mint(msg.sender,shares);
         emit AddLiquidity(msg.sender,_amountA,_amountB);
    }
   /**
     * Called by liquidity providers. Burn pool tokens in exchange of ETH & Tokens at current ratios.
     *
     * @param _shares uint256: Amount of shares to be burned
     * @return _amountA uint256: Amount of ETH withdrawn
     * @return _amountB uint256: Amount of Tokens withdrawn
     */ 
    
    function removeLiquidity(uint _shares) external returns (uint _amountA,uint _amountB) {
        if(_shares == 0) {
            revert Swap_NonZero();
        }

        uint balanceA = tokenA.balanceOf(address(this));
        uint balanceB = tokenB.balanceOf(address(this));

        //Formula that dictates the amount of shares to be burned of both tokenA and tokenB
        _amountA = (_shares * balanceA) / totalShares;
        _amountB = (_shares * balanceB) / totalShares;

        _burn(msg.sender, _shares);

       //update reserve of both tokens
        _trackReserve(
            balanceA - _amountA,
            balanceB - _amountB
        );

        bool success = tokenA.transfer(msg.sender, _amountA);
        if(!success) {
            revert Swap_TransferFailed();
        }

        bool successful = tokenB.transfer(msg.sender, _amountB);
        if(!successful) {
            revert Swap_TransferFailed();
        }
        
        emit RemoveLiquidity(msg.sender,_amountA,_amountB);
    }
    
    function _mint(address user, uint amount) private  {
        balanceOf[user] += amount;
        totalShares -= amount;
    }

    function _burn(address user,uint amount) private {
        balanceOf[user] -= amount;
        totalShares -=amount;
    }

    function _min(uint x, uint y) private pure returns(uint) {
        return x <= y ? x : y;
    }

   
    function _squareRoot(uint y) private pure returns (uint z) {
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
   
    function _trackReserve(uint _reserveA, uint _reserveB) private {
     reserveA = _reserveA;
     reserveB = _reserveB;
    } 
}