pragma solidity 0.8.10;

import "@omni/contracts/src/pkg/XApp.sol";
import "@omni/contracts/src/libraries/ConfLevel.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PeripheralDepositContract is XApp, Ownable {
    // immutables
    address public immutable depositManager; // address of the central DepositManager contract
    uint64 public immutable managerChainId; // chain id of the central DepositManager contract
    mapping(address => bool) public supportedTokens; // supported tokens
    uint256 public constant DEST_TX_GAS_LIMIT = 200_000; // gas limit for xchain call at destination

    // events
    event DepositInitiated(
        address indexed owner,
        uint256 amount,
        address tokenAddress
    );

    constructor(address _portal, address _depositManager, uint64 _managerChainId) 
        XApp(_portal, ConfLevel.Finalized) 
    {
        depositManager = _depositManager;
        managerChainId = _managerChainId;
    }

    /// @dev initiates a deposit to the central DepositManager contract
    /// @param amount The amount to be deposited
    /// @param tokenAddress The address of the token being deposited
    function deposit(uint256 amount, address tokenAddress) external payable {
        require(isXCall(), "OVV1:!xcall");
        require(supportedTokens[tokenAddress], "OVV1:!token");

        // Transfer tokens to DepositManager
        require(
            IERC20(tokenAddress).transferFrom(msg.sender, depositManager, amount),
            "OVV1:transfer failed"
        );

        // Get token name
        string memory tokenSymbol = IERC20(tokenAddress).symbol();

        // send an xcall to the DepositManager
        uint256 fee = omni.xcall(
            managerChainId,
            depositManager,
            abi.encodeWithSignature(
                "tokenCrossSwapDeposit(address,uint256,address,string)",
                msg.sender,
                amount,
                tokenAddress,
                tokenSymbol
            ),
            DEST_TX_GAS_LIMIT
        );

        require(msg.value >= fee, "OVV1:xcall fee");

        emit DepositInitiated(msg.sender, amount, tokenAddress);
    }

    /// @dev sets a supported token
    /// @param tokenAddress The address of the token to be supported
    function setSupportedToken(address tokenAddress) external onlyOwner {
        supportedTokens[tokenAddress] = true;
    } 
}
