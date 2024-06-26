pragma solidity 0.8.10;

import "@omni/contracts/src/pkg/XApp.sol";
import "@omni/contracts/src/libraries/ConfLevel.sol";

import "@openzeppelin-contracts/contracts/access/Ownable.sol";

import "./interfaces/IOverlayV1Token.sol";

contract DepositManager is XApp, Ownable {    
    // constants
    uint256 public constant NATIVE_TOKEN_AMOUNT = 250_000 * 1e9; // 250K gwei, about 10 transactions at 250K gas each
    uint256 public constant FEE_PERCENTAGE = 1; // 1%

    // immutables
    IOverlayV1Token public immutable ov; // ov token
    address public immutable ratesRelayer; // pushes conversion rates to this contract

    // state variables
    mapping(string => uint256) public convertToOV; // Token symbol to OV token conversion rate
    mapping(string => uint256) public lastUpdatedTime; // Token symbol to last updated time
    mapping(uint64 => address) public depositContractOn; // returns deposit contract address for a chain id
    mapping(address => bool) public hasDeposit; // owner -> bool

    // events
    event DepositSwap(
        address indexed owner, 
        uint256 amount, 
        string tokenName, 
        uint256 ovAmount, 
        uint64 sourceChainId
    );

    constructor(address _portal, address _ovToken, address _omni, address _ratesRelayer) 
        XApp(_portal, ConfLevel.Finalized) 
    {
        ov = IOverlayV1Token(_ovToken);
        ratesRelayer = _ratesRelayer;
    }

    /// @dev records user deposit from a supported rollup chain sending OV tokens (and native for first time users)
    /// @param owner The address of the owner making the deposit
    /// @param amount The amount to be deposited
    /// @param tokenAddress The address of the token being deposited at source chain
    /// @param tokenSymbol The symbol of the token being deposited at source chain
    function tokenCrossSwapDeposit(address owner, uint256 amount, address tokenAddress, string calldata tokenSymbol) external xrecv {
        require(isXCall(), "OVV1:!xcall");
        require(msg.sender == address(omni.omniChainId()), "OVV1:!ov");
        require(isSupportedChain(xmsg.sourceChainId), "OVV1:!chain");
        require(xmsg.sender == depositContractOn[xmsg.sourceChainId], "OVV1:!deposit");
        require(hasConversionRate(tokenSymbol), "OVV1:!tokenrate");
        require(lastUpdatedTime[tokenSymbol] + 21600 < block.timestamp, "OVV1:!tokenratetime"); // 6 hours

        // Perform conversion to OV token amount from tokenName using mapping
        uint256 ovAmount = amount * convertToOV[tokenSymbol];
        require(ovAmount > 0, "OVV1:conversion rate");

        // Calculate fee
        ovAmount = ovAmount - (ovAmount * FEE_PERCENTAGE / 100);

        // Transfer native tokens to owner if not already done
        if (!hasDeposit[owner]) {
            // Reduce native token grant from ovAmount
            require(hasConversionRate("ETH"), "OVV1:!ETHrate");
            require(lastUpdatedTime["ETH"] + 21600 < block.timestamp, "OVV1:!ETHratetime"); // 6 hours
            ovAmount -= NATIVE_TOKEN_AMOUNT * convertToOV["ETH"] / 1e18;
            uint256 nativeTokenAmount = NATIVE_TOKEN_AMOUNT;
            payable(owner).transfer(nativeTokenAmount);
            hasDeposit[owner] = true;
        }

        // Transfer the OV tokens to user
        require(ov.transfer(owner, ovAmount), "OVV1:transfer failed");

        emit DepositSwap(owner, amount, tokenSymbol, ovAmount, xmsg.sourceChainId);
    }

    /// @dev Sets the conversion rate for a token
    /// @param tokenSymbol The symbol of the token
    /// @param rate The conversion rate to OV tokens
    function setConversionRate(string calldata tokenSymbol, uint256 rate) external {
        require(msg.sender == ratesRelayer, "OVV1:!relayer");
        convertToOV[tokenSymbol] = rate;
        lastUpdatedTime[tokenSymbol] = block.timestamp;
    }

    /// @dev Sets the deposit contract address for a chain
    /// @param chainId The chain id
    /// @param depositContract The address of the deposit contract
    function setDepositContract(uint64 chainId, address depositContract) external onlyOwner {
        depositContractOn[chainId] = depositContract;
    }

    /// @dev Checks if a token is supported
    /// @param tokenSymbol The name of the token
    /// @return True if the token is supported
    function hasConversionRate(string memory tokenSymbol) public view returns (bool) {
        return convertToOV[tokenSymbol] != 0;
    }

    /// @dev Checks if a chain is supported
    /// @param chainId The chain id
    /// @return True if the chain is supported
    function isSupportedChain(uint64 chainId) public view returns (bool) {
        return contractOn[chainId] != address(0);
    }

    // receive native tokens
    receive() external payable {}
}
