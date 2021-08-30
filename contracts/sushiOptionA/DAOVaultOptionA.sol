//SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../../interfaces/IUniswapV2Router02.sol";
import "../../interfaces/IUniswapV2Pair.sol";
import "../../interfaces/IMasterChef.sol";

interface IChainlink {
    function latestAnswer() external view returns (int256);
}

interface Factory {
    function owner() external view returns (address);
}


contract DAOVaultOptionA is Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IUniswapV2Router02 public constant SushiRouter = IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);    
    IMasterChef public MasterChef;

    IERC20Upgradeable public lpToken; 
    IERC20Upgradeable public constant WETH = IERC20Upgradeable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); 
    IERC20Upgradeable public constant SUSHI = IERC20Upgradeable(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2); 
    IERC20Upgradeable public constant WBTC = IERC20Upgradeable(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20Upgradeable public constant ibBTC = IERC20Upgradeable(0xc4E15973E6fF2A35cC804c2CF9D2a1b817a8b40F);
    IERC20Upgradeable public token0;
    IERC20Upgradeable public token1;
    IUniswapV2Pair public lpPair;
    Factory public factory;

    address public admin; 
    address public treasuryWallet;
    address public communityWallet;
    address public strategist;

    uint public poolId;
    uint private _fees; // 18 decimals
    uint private masterChefVersion;
    uint public yieldFee;
    uint public depositFee;

    uint private token0Decimal;
    uint private token1Decimal;

    bool isEmergency;

    mapping(address => bool) public isWhitelisted;

    event Yield(uint _yieldAmount);
    event SetNetworkFeeTier2(uint256[] oldNetworkFeeTier2, uint256[] newNetworkFeeTier2);
    event SetNetworkFeePerc(uint256[] oldNetworkFeePerc, uint256[] newNetworkFeePerc);
    event SetCustomNetworkFeeTier(uint256 indexed oldCustomNetworkFeeTier, uint256 indexed newCustomNetworkFeeTier);
    event SetCustomNetworkFeePerc(uint256 oldCustomNetworkFeePerc, uint256 newCustomNetworkFeePerc);
    event SetTreasuryWallet(address indexed _treasuryWallet);
    event SetCommunityWallet(address indexed _communityWallet);
    event SetAdminWallet(address indexed _admin);
    event SetStrategistWallet(address indexed _strategistWallet);
    event Deposit(address indexed _token, address _from, uint _amount, uint _sharesMinted);
    event Withdraw(address indexed _token, address _from, uint _amount, uint _sharesBurned);

    uint256[49] private __gap;
    modifier onlyAdmin {
        require(msg.sender == admin, "Only Admin");
        _;
    }

    modifier onlyOwner {
        require(msg.sender == factory.owner(), "only Owner");
        _;
    }

    ///@dev For ETH-token pairs, _token0 should be ETH 
    function initialize(string memory _name, string memory _symbol, uint _poolId, 
      IERC20Upgradeable _token0, IERC20Upgradeable _token1, IERC20Upgradeable _lpToken,
      address _communityWallet, address _treasuryWallet, address _strategist, address _admin,
      address _masterchef, uint _masterChefVersion) external initializer {
        
        __ERC20_init(_name, _symbol);
        
        poolId = _poolId;
        yieldFee = 2000; //20%
        depositFee = 1000; //20%

        MasterChef  = IMasterChef(_masterchef); 
        masterChefVersion = _masterChefVersion;

        token0 = _token0;
        token1 = _token1;
        lpToken = _lpToken;
        lpPair = IUniswapV2Pair(address(_lpToken));
        communityWallet = _communityWallet;
        treasuryWallet = _treasuryWallet;
        strategist = _strategist;
        admin = _admin;

        token0Decimal = ERC20Upgradeable(address(_token0)).decimals();//18;
        token1Decimal =  ERC20Upgradeable(address(_token1)).decimals();//6;

        factory = Factory(msg.sender);

        token0.safeApprove(address(SushiRouter), type(uint).max);
        token1.safeApprove(address(SushiRouter), type(uint).max);
        lpToken.safeApprove(address(SushiRouter), type(uint).max);
        lpToken.safeApprove(address(MasterChef), type(uint).max);
        SUSHI.safeApprove(address(SushiRouter), type(uint).max);

    }
        
    /**
        @param _amount amount of token to deposit.
        @dev For ETH send, msg.value is used instead of _amount
     */
    function deposit(uint _amount) external nonReentrant {
        require(isEmergency == false ,"Deposit paused");
        require(_amount > 0, "Invalid amount");

        _deposit(_amount);
    }

    /** 
        @param _shares shares to withdraw.
     */
    function withdraw(uint _shares) external nonReentrant returns (uint amountToWithdraw){
        require(_shares > 0, "Invalid amount");
        
        amountToWithdraw = _withdraw(_shares);
    }

    function _withdraw(uint _shares) internal returns (uint amountToWithdraw){
        amountToWithdraw = balance().mul(_shares).div(totalSupply()); 

        uint lpInVault = available();
        
        if(amountToWithdraw > lpInVault) {
            _withdrawFromPool(amountToWithdraw.sub(lpInVault));
        }

        _burn(msg.sender, _shares);

        lpToken.safeTransfer(msg.sender, amountToWithdraw);

        emit Withdraw(address(lpToken), msg.sender, amountToWithdraw, _shares);//NEW_CHANGE //remove lptoken from event

    }

    function yield() external onlyAdmin{
        require(isEmergency == false ,"yield paused");
        _yield();

    }

    ///@dev Moves lpTokens from this contract to Masterchef
    function invest() external onlyAdmin {
        require(isEmergency == false ,"Invest paused");

        _transferFee();

        uint balanceInVault = available();
        if(balanceInVault > 0) {
            _stakeToPool(balanceInVault);
        }
    }

    function whitelistContract(address _addr, bool _status) external onlyOwner {
        isWhitelisted[_addr] = _status;
    }

    /**
     *@param _yieldFee yieldFee percentange. 2000 for 20%
     *@param _depositFee deposit fee percentange. 1000 for 10%
     */
    function setFee(uint _yieldFee, uint _depositFee) external onlyOwner {
        yieldFee = _yieldFee;
        depositFee = _depositFee;
    }
    

    ///@dev Withdraws lpTokens from masterChef. Yield, invest functions will be paused
    function emergencyWithdraw() external onlyAdmin {    
        isEmergency = true;
        // _yield();

        (uint lpTokenBalance, ) = MasterChef.userInfo(poolId, address(this));
        _withdrawFromPool(lpTokenBalance);
    }

    ///@dev Moves funds in this contract to masterChef. ReEnables deposit, yield, invest.
    function reInvest() external onlyOwner {        

        _stakeToPool(available());

        isEmergency = false;
    }

    function setTreasuryWallet(address _treasuryWallet) external onlyAdmin {
        treasuryWallet = _treasuryWallet;
        emit SetTreasuryWallet(_treasuryWallet);
    }

    function setCommunityWallet(address _communityWallet) external onlyAdmin {
        communityWallet = _communityWallet;
        emit SetCommunityWallet(_communityWallet);
    }

    function setStrategistWallet(address _strategistWallet) external onlyAdmin {
        strategist = _strategistWallet;
        emit SetStrategistWallet(_strategistWallet);
    }

    ///@dev To move lpTokens from masterChef to this contract.
    function withdrawToVault(uint _amount) external onlyAdmin {
        _withdrawFromPool(_amount);
    }

    ///@dev swap to required lpToken. Deposit to masterChef in invest()
    function _deposit(uint _amount) internal returns(uint _lpTokens){

        uint lpTokenPool = balance();

        if(isWhitelisted[msg.sender]) {
            _lpTokens = _amount;
        } else {
            uint256 _fee = _amount.mul(depositFee).div(10000); //10%
            _fees = _fees.add(_fee);
            _lpTokens = _amount.sub(_fee);
        }

        uint shares;
        

        if(totalSupply() == 0) {
            shares = _lpTokens;
        } else {
            shares = _lpTokens.mul(totalSupply()).div(lpTokenPool);
        }

        lpToken.transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, shares);

        emit Deposit(address(lpToken), msg.sender, _amount, shares);

    }

    function _withdrawFromPool(uint _amount) internal {
        if(masterChefVersion == 1 ) {
            MasterChef.withdraw(poolId, _amount);
        } else {
            MasterChef.withdraw(poolId, _amount, address(this));
        }
    }

    receive() external payable {
    }


    function _yield() internal {
        uint lpTokens;
        uint token1Reward;
        uint rewardInETH;
        address[] memory path = new address[](2);

        if(masterChefVersion == 1) {
            MasterChef.deposit(poolId, 0); // To collect SUSHI
        } else {
            MasterChef.harvest(poolId, address(this)); //claim sushi rewards
            token1Reward = token1.balanceOf(address(this));
            uint[] memory _tokensAmount = _swapTokenToPairs(address(token1),token1Reward);

            path[0] = address(token1);
            path[1] = address(WETH);
            
            rewardInETH = SushiRouter.getAmountsOut(token1Reward, path)[1];
            lpTokens = _addLiquidity(_tokensAmount[1], _tokensAmount[0]);
        }

        uint sushiBalance = SUSHI.balanceOf(address(this));
        
        if(sushiBalance > 0) {
            lpTokens = lpTokens.add(_swapSushi(sushiBalance.div(2)));
        }

        uint lpTokenBalance = available();
        if(lpTokens > 0) {
             uint fee = lpTokens.mul(yieldFee).div(10000);  //20%
            _fees = _fees.add(fee);
            _stakeToPool(lpTokenBalance.sub(fee));

            path[0] = address(SUSHI);
            path[1] = address(WETH);

            rewardInETH = rewardInETH.add(SushiRouter.getAmountsOut(sushiBalance, path)[1]);
        }

        emit Yield(rewardInETH);

    }

    function _swapSushi(uint _amount) internal returns (uint _lptokens){
        address[] memory path = getPathSushi(address(token0));

            _swapExactTokens(_amount, 0, path);

            path = getPathSushi(address(token1));

            _swapExactTokens(_amount, 0, path);   
            _lptokens = _addLiquidity (token0.balanceOf(address(this)), token1.balanceOf(address(this)));     
    }

    function getPathSushi(address _targetToken) internal view returns (address[] memory path) {
        if(token0 == WBTC) {
            if(address(token0) == _targetToken) {
                path = new address[](3);
                path[0] = address(SUSHI);
                path[1] = address(WETH);
                path[2] = _targetToken;
            } else {
                path = new address[](4);
                path[0] = address(SUSHI);
                path[1] = address(WETH);
                path[2] = address(WBTC);
                path[3] = _targetToken;
            }
        } else {

            if(_targetToken != address(WETH)) {
                path = new address[](3);
                path[0] = address(SUSHI);
                path[1] = address(WETH);
                path[2] = _targetToken;
            } else {
                path = new address[](2);
                path[0] = address(SUSHI);
                path[1] = _targetToken;
            }

        }

    }

    function getPathToETH(address _source) internal view returns (address[] memory path) {
        if(token0 == WETH) { //WETH pairs
            path = new address[](2);
            path[0] = _source;
            path[1] = address(WETH);

            return path;
        }

        if(token0 == WBTC) { 
            if(_source == address(WBTC))  { //for WBTC-token pair
                path = new address[](2);
                path[0] = _source;
                path[1] = address(WETH);

                return path;
            }

            if(_source != address(WBTC))  { //for WBTC-token pair, when token-ETH path doesn't exist
                path = new address[](3);
                path[0] = _source;
                path[1] = address(WBTC);
                path[2] = address(WETH);
                return path;
            }

        }

    }

    ///@dev Converts ETH to WETH and swaps to required pair token
    function _swapETHToPairs() internal returns (uint[] memory _tokensAmount){
        
        (bool _status,) = payable(address(WETH)).call{value: msg.value}(""); //wrap ETH to WETH
        require(_status, 'ETH-WETH failed');
        
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(token1);
        
        
        _tokensAmount = _swapExactTokens(msg.value.div(2), 0, path);

    }

    ///@dev swap to required pair tokens
    function _swapTokenToPairs(address _token, uint _amount) internal returns (uint[] memory _tokensAmount) {
        
        address[] memory path = new address[](2);
        path[0] = _token;
        path[1] = _token == address(token0) ? address(token1) : address(token0);
        
        uint[] memory _tokensAmountTemp = _swapExactTokens(_amount.div(2), 0, path);

        if(_token == address(token0)){
            _tokensAmount = _tokensAmountTemp;
        } else {
            _tokensAmount = new uint[](2);
            _tokensAmount[0] = _tokensAmountTemp[1];
            _tokensAmount[1] = _tokensAmountTemp[0];
        }

    }

    function _addLiquidity(uint _amount0, uint _amount1) internal returns (uint lpTokens) {
        (,,lpTokens) = SushiRouter.addLiquidity(address(token0), address(token1), _amount0, _amount1, 0, 0, address(this), block.timestamp);
    }

    function _stakeToPool(uint _amount) internal {
        if(masterChefVersion == 1) {
            MasterChef.deposit(poolId, _amount);
        } else {
            MasterChef.deposit(poolId, _amount, address(this));
        }
    }

    ///@dev Transfer fee from vault
    function _transferFee() internal {
        uint feeSplit = _fees.mul(2).div(5);

        lpToken.safeTransfer(treasuryWallet, feeSplit); //40%
        lpToken.safeTransfer(communityWallet, feeSplit); //40
        lpToken.safeTransfer(strategist, _fees.sub(feeSplit).sub(feeSplit)); //20%

        _fees = 0;
    }

    function _swapExactTokens(uint _inAmount, uint _outAmount, address[] memory _path) internal returns (uint[] memory _tokens) {
        _tokens = SushiRouter.swapExactTokensForTokens(_inAmount, _outAmount, _path, address(this), block.timestamp);
    }

    ///@dev calculates the assets that will be removed for the give lpTokenAmount
    function getRemovedAmount(uint _inputAmount) internal view returns (uint _amount0, uint _amount1){
        uint totalSupply = lpPair.totalSupply();
        uint balance0 = token0.balanceOf(address(lpPair));
        uint balance1 = token1.balanceOf(address(lpPair));

        _amount0 = _inputAmount.mul(balance0) / totalSupply; //not using div() as per univ2
        _amount1 = _inputAmount.mul(balance1) / totalSupply; //not using div() as per univ2
    }
    ///@dev balance of LPTokens in vault + masterCHef
    function balance() public view returns (uint _balance){
        (uint balanceInMasterChef, ) = MasterChef.userInfo(poolId,address(this));
        _balance = available().add(balanceInMasterChef);
    }

    function available() public view returns (uint _available) {
        _available = lpToken.balanceOf(address(this)).sub(_fees);
    }

    function getAllPool() public view returns (uint) {
        (uint balanceInMasterChef, ) = MasterChef.userInfo(poolId,address(this));
        return lpToken.balanceOf(address(this)).add(balanceInMasterChef);
    }

    ///@dev returns reserve values in 18 decimals. _reserve0 will always be token0 of this contract
    function _getReserves() internal view returns(uint _reserve0, uint _reserve1){ 
        (_reserve0, _reserve1, ) = lpPair.getReserves();

        if(address(token0) != lpPair.token0()) {
            (_reserve0, _reserve1) = (_reserve1, _reserve0);
        }

        _reserve0 = _adjustDecimals(_reserve0, token0Decimal);
        _reserve1 = _adjustDecimals(_reserve1, token1Decimal);
    }

    function _adjustDecimals(uint _amount, uint _sourceDecimals) internal pure returns(uint) { 
         uint _newDecimal = 18 - _sourceDecimals;
         return _amount * 10 ** _newDecimal;
     }

    //returns price of lpToken in terms of ETH (18 decimals)
    function getlpTokenPriceInETH() internal view returns (uint) {
        uint token1PriceInETH = (SushiRouter.getAmountsOut(10**(token1Decimal), getPathToETH(address(token1))))[1];
        (uint reserve0, uint reserve1) = _getReserves();
        uint token0PriceInETH;

        if(token0 != WETH) {
            token0PriceInETH = (SushiRouter.getAmountsOut(10**(token0Decimal), getPathToETH(address(token0))))[1];
        }

        //reserve1 + reserve0
        uint reserveInETH = token0 == WETH ? (reserve1.mul(token1PriceInETH)).add(reserve0.mul(1e18)) :

            (reserve1.mul(token1PriceInETH)).add((reserve0.mul(token0PriceInETH))) ; // for BTC-token pairs

        return reserveInETH.div(lpPair.totalSupply());
    }

    function getLpTokenPriceInUSD() internal view returns (uint) {
        uint ETHPriceInUSD = uint(IChainlink(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419).latestAnswer()).mul(1e10); // 8 decimals
        return getlpTokenPriceInETH() * ETHPriceInUSD / 1e18;
    }

    function getAllPoolInETH() public view returns (uint) {
        return getAllPool().mul(getlpTokenPriceInETH()).div(1e18);
    }
    ///@notice returns value in pool in USD (18 decimals)
    function getAllPoolInUSD() public view returns (uint) {
        return getAllPool().mul(getLpTokenPriceInUSD()).div(1e18);
    }

    function getPricePerFullShare(bool inUSD) external view returns (uint) {
        uint _totalSupply = totalSupply();
        if (_totalSupply == 0) return 0;
        return inUSD == true ?
            getAllPoolInUSD() * 1e18 / _totalSupply :
            getAllPool() * 1e18 / _totalSupply;
    }
}



