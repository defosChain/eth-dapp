// SPDX-License-Identifier: DeFOS

pragma solidity ^0.6.0;

// Import OpenZeppelin Contracts library
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// import "github.com/OpenZeppelin/zeppelin-solidity/contracts/access/Ownable.sol";
// import "github.com/OpenZeppelin/zeppelin-solidity/contracts/math/SafeMath.sol";
// import "github.com/OpenZeppelin/zeppelin-solidity/contracts/utils/Address.sol";
// import "github.com/OpenZeppelin/zeppelin-solidity/contracts/utils/Pausable.sol";
// import "github.com/OpenZeppelin/zeppelin-solidity/contracts/token/ERC20/ERC20.sol";


/**
 * @title   EIP20NonStandardInterface
 * @dev     Version of ERC20 with no return values for `transfer` and `transferFrom`
 *          See https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
 *
 * @notice  Use this interface to compatible with Non-Standard ERC20 Token such as USDT etc...
 */
interface EIP20NonStandardInterface {
    /**
     * @notice Get the total number of tokens in circulation
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Gets the balance of the specified address
     * @param owner The address from which the balance will be retrieved
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    ///
    /// !!!!!!!!!!!!!!
    /// !!! NOTICE !!! `transfer` does not return a value, in violation of the ERC-20 specification
    /// !!!!!!!!!!!!!!
    ///

    /**
      * @notice Transfer `amount` tokens from `msg.sender` to `dst`
      * @param dst The address of the destination account
      * @param amount The number of tokens to transfer
      */
    function transfer(address dst, uint256 amount) external;

    ///
    /// !!!!!!!!!!!!!!
    /// !!! NOTICE !!! `transferFrom` does not return a value, in violation of the ERC-20 specification
    /// !!!!!!!!!!!!!!
    ///

    /**
      * @notice Transfer `amount` tokens from `src` to `dst`
      * @param src The address of the source account
      * @param dst The address of the destination account
      * @param amount The number of tokens to transfer
      */
    function transferFrom(address src, address dst, uint256 amount) external;

    /**
      * @notice Approve `spender` to transfer up to `amount` from `src`
      * @dev This will overwrite the approval amount for `spender`
      *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
      * @param spender The address of the account which may transfer tokens
      * @param amount The number of tokens that are approved
      */
    function approve(address spender, uint256 amount) external returns (bool success);

    /**
      * @notice Get the current allowance from `owner` for `spender`
      * @param owner The address of the account which owns the tokens to be spent
      * @param spender The address of the account which may transfer tokens
      */
    function allowance(address owner, address spender) external view returns (uint256 remaining);

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
}


/**
 * @author  Defos.Team
 *
 * @dev     Contract for multi-level fund investment with 80% insurance
 *
 * @notice  Use it for your own risk
 */

contract MLFund is Ownable, Pausable {
    using Address for address;
    using SafeMath for uint256;

    uint256 public constant etherUnit = 1e18;
    
    // note: usdt just has 6 decimals!
    uint256 public constant usdtUnit = 1e6;


    // commonly a pair should be base/quote
    // so defos is the base currency, usdt is the quote currency in our game.
    address public constant baseAddr    = 0x6Dc47E3cD4B459606025b0B2ED600E1173429FeC;   // defos token addr
    address public constant quoteAddr   = 0x78a20924e4B228B0B8D7F781B5016431eE07783C;   // usdt token addr

    // convert token address to contract object
    ERC20 public constant baseToken     = ERC20(baseAddr);

    // usdt is a non standard erc20 token
    EIP20NonStandardInterface public constant quoteToken = EIP20NonStandardInterface(quoteAddr);

    // the blocks delay to transfer insurance money, commonly be 180days
    // eth will produce a block about 15 seconds at the moment, but maybe change
    // so this is an appropriate delay(source: https://etherscan.io/chart/blocktime)
    uint256 public constant shouldDelayBlocks   = (4*60*24*180);

    // the block number when contract created.
    uint256 private _createdBlockNo;

    // the price of one unit, such as 1defos=0.01usdt
    uint256 private _unitPrice;

    // record the total base invest num, including the refunds
    uint256 private _totalBaseInvests   = 0;

    // record the total quote invest num, including the refunds
    uint256 private _totalQuoteInvests  = 0;

    // record the total refund invest num via base currency
    uint256 private _totalRefundsInBase = 0;

    // record the total refund invest num via quote currency, not including insurance
    uint256 private _totalRefundsInQuote= 0;


    // configure variables start

    // the minimum deposit value
    uint256 private _minimumMlfundNum   = 1*usdtUnit;

    // the dst address of 20% quote token
    address private _luckyPoolOwner;

    // insurance ratio, fix it to 80% at the moment
    uint256 private _insuranceRatio     = 80;

    // configure variables end

    // Main data struct
    // Tracks funds-related info for a specific investor(address)
    struct Investor
    {
        uint256 baseInvests;    // Total invest num of base currency at moment
        uint256 quoteInvests;   // Total invest num of quote currency at moment
        uint256 lastBlock;      // Last block height at which investments were made

        uint256 refundsInBase;  // Total refunds(record via base currency) for this investor, not including insurance
    }
    mapping (address => Investor) private _investors;

    /*************  public functions *************/

    // constructor
    constructor(uint256 initPrice) public {
        require(initPrice > 0, "error param, initPrice need be greater than 0!");

        _unitPrice      = initPrice;

        _luckyPoolOwner = _msgSender();
        _createdBlockNo = block.number;
    }

    // empty function and do not receive any eth funds.
    receive() external payable {
        require(msg.value == 0, "eth amount should be zero, and this function should not be called at any time!");

        // do nothing..
    }
    

    /**
     * @dev     main mlfund function, deposit quote token, and return base token
     *      
     * @notice  if someone returned x token, another one can mlfund(buy) it at this price
     */
    function mlfund(uint256 amount) public whenNotPaused 
        returns(bool)
    {
        require(amount >= _minimumMlfundNum, "mlfund amount should greater than _minimumMlfundNum!");
        require(baseToken.balanceOf(address(this)) > 0, "contract has no base token now, please retry.");

        return _mlfund(amount);
    }


    /**
     * @dev     main refund function, deposit base token, return quote token.
     *
     * @notice  investors could refund at any time, should not be paused at any time
     */
    function refund(uint256 amount) public returns(bool) {
        require(amount > 0, "refund amount should be greater than 0");
        require(_investors[_msgSender()].baseInvests >= amount, "invest balance is insufficient.");

        require(quoteToken.balanceOf(address(this)) > 0, "contract has no quote token now, please retry.");
        require(baseToken.balanceOf(_msgSender()) >= amount, "insufficient balance");

        return _refund(amount);
    }


    /**
     * @dev     get the investor info
     *
     * @return  return the investor struct info, please read Investor struct for details.
     */
    function getInvestorInfo(address addr) external view
        returns(uint256, uint256, uint256, uint256)
    {
        return (_investors[addr].baseInvests,
                _investors[addr].quoteInvests,
                _investors[addr].lastBlock,
                _investors[addr].refundsInBase
        );
    }

    /**
     * @dev     get contract variable info
     *
     * @return  _unitPrice:             unitPrice for pair: base/quote(defos/usdt)
     *          _totalBaseInvests:      total invests of base currency at moment
     *          _totalQuoteInvests:     total invests of quote currency at moment
     *          _totalRefundsInBase:    total refunds of base currency at moment
     *          _totalRefundsInQuote:   total refunds of quote currency at moment
     *          _createdBlockNo:        the block height of the creation time for this contract
     *          _baseTokenBalance:      contract's base token balance
     *          _quoteTokenBalance:     contract's quote token balance         
     */
    function getContractInfo() external view
        returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        uint256 _baseTokenBalance   = baseToken.balanceOf(address(this));
        uint256 _quoteTokenBalance  = quoteToken.balanceOf(address(this));

        return (_unitPrice,
                _totalBaseInvests,
                _totalQuoteInvests,
                _totalRefundsInBase,
                _totalRefundsInQuote,
                _createdBlockNo,
                _baseTokenBalance,
                _quoteTokenBalance
        );
    }

    /**
     * @dev     get admin configure info
     *
     * @return  _minimumMlfundNum:  minimum fund deposit num
     *          _luckyPoolOwner:    the owner of lucky pool with 20% invests
     */
    function getAdminConfigures() external view 
        returns(uint256, address)
    {
        return (_minimumMlfundNum,
                _luckyPoolOwner
        );
    }


    /*************  admin area *************/

    // modify _minimumMlfundNum
    function modifyMinimumMlfundNum(uint256 amount) public onlyOwner
        returns(bool success)
    {
        require(amount > 0, "modifyMinimumMlfundNum: deposit num shoule be greater than 0");

        _minimumMlfundNum = amount;
        return true;
    }

    // modify _luckyPoolOwner
    function modifyLuckyPoolOwner(address newAddr) public onlyOwner
        returns(bool success)
    {
        require(newAddr != address(0), "modifyLuckyPoolOwner: new owner is the zero address");

        _luckyPoolOwner = newAddr;
        return true;
    }

    /**
     * @dev after specified blocks later, admin can transfer the insurance quote token
     */
    function withdrawQuoteToken(uint256 amount) public onlyOwner {
        require(amount > 0, "withdrawQuoteToken: amount should be greater than 0");

        require(quoteToken.balanceOf(address(this)) >= amount, 
                "withdrawQuoteToken: contract has no enough quote balance");

        // check the conditions of after specified blocks delay
        require(block.number >= (shouldDelayBlocks + _createdBlockNo), 
                "withdrawQuoteToken: block.number is less than the demand delay blocks now.");

        _withdrawQuoteToken(_msgSender(), amount);
    }

    /**
     * @dev     admin can transfer the base token out, or adjust the total sale amount
     *
     * @notice  the purpose of this operation is to burn the tokens or other things
     *          surely the admin may also never call this function..
     */
    function withdrawBaseToken(uint256 amount) public onlyOwner {
        require(amount > 0, "withdrawBaseToken: amount should be greater than 0");

        require(baseToken.balanceOf(address(this)) >= amount, 
                "withdrawBaseToken: contract has no enough quote balance");

        _withdrawBaseToken(_msgSender(), amount);
    }

    /**
     * @dev pause mlfund function
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev unpause mlfund function
     */
    function unpause() public onlyOwner {
        _unpause();
    }


    /*************  private functions *************/

    /**
     * @dev the real mlfund function which does the logic, steps: 
     *      1. several checks 
     *      2. calculate the returned token num
     *      3. transfer 20% usdt to lucky addr and 80% to insurance pool
     *      4. do the asset relative things
     *      5. other things such as emiting event etc
     *
     * @return  bool
     */
    function _mlfund(uint256 amount) private returns(bool) {
        // 1. several checks
        // nothing to do here yet

        // 2. calculate the returned base token num
        uint256 retBaseToken = amount.mul(etherUnit).div(_unitPrice);

        require(retBaseToken > 0, "calculation of return token has errors, please retry");
        require(baseToken.balanceOf(address(this)) >= retBaseToken, "balance of matrix pool is insufficient");

        // 3. do 20% of quote token to luckyPool, 80% to contract
        uint256 insuranceAmount = amount.mul(_insuranceRatio).div(100);
        uint256 luckyPoolAmount = amount.sub(insuranceAmount);

        // return is always true, otherwise would throw an exception
        // do quote token transfer first
        quoteToken.transferFrom(_msgSender(), address(this), insuranceAmount);
        quoteToken.transferFrom(_msgSender(), _luckyPoolOwner, luckyPoolAmount);

        // then do base token transfer
        baseToken.transfer(_msgSender(), retBaseToken);

        // 4. do the asset update or relative things, will change the contract variables here.
        // update contract global info
        _totalBaseInvests   = _totalBaseInvests.add(retBaseToken);
        _totalQuoteInvests  = _totalQuoteInvests.add(amount);

        // update invest info
        _investors[_msgSender()].baseInvests  = _investors[_msgSender()].baseInvests.add(retBaseToken);
        _investors[_msgSender()].quoteInvests = _investors[_msgSender()].quoteInvests.add(amount);
        _updateBlockNo();

        // 5. other things such as emiting event etc
        emit eMLFund(_msgSender(), amount);

        return true;
    }

    /**
     * @dev the real refund function which does the logic, steps: 
     *      1. receive basic token and calcute refund quote token num
     *      2. do the return token logic
     *      3. event things etc
     */
    function _refund(uint256 amount) private returns (bool) {
        // 1. receive defos and calcute refund num
        // calculate the returned token, muliple an etherUnit to avoid float number
        uint256 retQuoteTokenNum    = _unitPrice.mul(amount).div(etherUnit);
        uint256 retInsuranceQuoteNum= retQuoteTokenNum.mul(_insuranceRatio).div(100);

        require(quoteToken.balanceOf(address(this)) >= retInsuranceQuoteNum, "contract has no enough quote token");

        // 2. do the return token logic
        baseToken.transferFrom(_msgSender(), address(this), amount);
        quoteToken.transfer(_msgSender(), retInsuranceQuoteNum);

        _totalRefundsInBase     = _totalRefundsInBase.add(amount);
        _totalRefundsInQuote    = _totalRefundsInQuote.add(retQuoteTokenNum);
        
        _investors[_msgSender()].refundsInBase = _investors[_msgSender()].refundsInBase.add(amount);

        // need decrease the invest amount of this investor
        // will not multiple insurance ratio, record the full refund amount
        _investors[_msgSender()].baseInvests  = _investors[_msgSender()].baseInvests.sub(amount);
        _investors[_msgSender()].quoteInvests = _investors[_msgSender()].quoteInvests.sub(retQuoteTokenNum);

        // 3. event things etc
        emit eReFund(_msgSender(), amount, retInsuranceQuoteNum);

        return true;
    }


    // update block when receive a new trasaction
    function _updateBlockNo() private
    {
        _investors[_msgSender()].lastBlock = block.number;
    }

    // transfer insurance money by admin
    function _withdrawQuoteToken(address to, uint256 amount) private
    {
        quoteToken.transfer(to, amount);

        // emit event if needed
    }

    // transfer base token money by admin
    function _withdrawBaseToken(address to, uint256 amount) private
    {
        baseToken.transfer(to, amount);

        // emit event if needed
    }


    /*************  event definition  *************/

    /**
     * @dev multi-level fund invest event.
     */
    event eMLFund(address indexed from, uint256 value);
    event eReFund(address indexed from, uint256 baseValue, uint256 quoteValue);
}