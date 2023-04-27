// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./WasabiOption.sol";
import "./IWasabiPool.sol";
import "./IWasabiErrors.sol";
import "./IReservoirV6_0_1.sol";
import "./lib/Signing.sol";
import { IPool } from "./aave/IPool.sol";
import { IWETH } from "./aave/IWETH.sol";
import { IPoolAddressesProvider } from "./aave/IPoolAddressesProvider.sol";
import { IFlashLoanSimpleReceiver } from "./aave/IFlashLoanSimpleReceiver.sol";

contract WasabiOptionArbitrage is IERC721Receiver, Ownable, ReentrancyGuard, IFlashLoanSimpleReceiver {
    address private option;
    address private addressProvider; //0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e // for Aave
    address wethAddress;

    error FailedToExecuteMarketOrder();

    struct FunctionCallData {
        address to;
        uint256 value;
        bytes data;
    }

    IPool private lendingPool;

    event Arbitrage(address account, uint256 optionId, uint256 payout);

    constructor(address _option, address _addressProvider, address _wethAddress) {
        option = _option;
        addressProvider = _addressProvider;
        wethAddress = _wethAddress;
        lendingPool = IPool(IPoolAddressesProvider(addressProvider).getPool());
    }

    function setOption(address _option) external {
        option = _option;
    }

    function arbitrage(
        uint256 _optionId,
        uint256 _value,
        address _poolAddress,
        uint256 _tokenId,
        FunctionCallData[] calldata _marketplaceCallData,
        bytes[] calldata _signatures
    ) external payable {

        validate(_marketplaceCallData, _signatures);
        // Transfer Option for Execute
        IERC721(option).safeTransferFrom(msg.sender, address(this), _optionId);

        address asset = IWasabiPool(_poolAddress).getLiquidityAddress();
        if (asset == address(0)) {
            asset = wethAddress;
        }

        uint16 referralCode = 0;
        bytes memory params = abi.encode(_optionId, _poolAddress, _tokenId, _marketplaceCallData);

        lendingPool.flashLoanSimple(address(this), asset, _value, params, referralCode);

        uint256 wBalance = IERC20(wethAddress).balanceOf(address(this));
        if (wBalance != 0) {
            IWETH(wethAddress).withdraw(wBalance);
        }
        
        uint256 balance = address(this).balance;
        if (balance != 0) {
            (bool sent, ) = payable(msg.sender).call{value: balance}("");
            require(sent, "Failed to send Ether");
        }
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns(bool) {
        ( uint256 _optionId, address _poolAddress, uint256 _tokenId, FunctionCallData[] memory _calldataList ) =
            abi.decode(params, (uint256, address, uint256, FunctionCallData[]));

        IWasabiPool pool = IWasabiPool(_poolAddress);
        address nft = IWasabiPool(_poolAddress).getNftAddress();

        // Validate Order
        IWETH(asset).withdraw(amount);
        uint256 totalDebt = amount + premium;

        if (pool.getOptionData(_optionId).optionType == WasabiStructs.OptionType.CALL) {
            // Execute Option
            IWasabiPool(_poolAddress).executeOption{value: amount}(_optionId);

            // Sell NFT
            bool marketSuccess = executeFunctions(_calldataList);
            if (!marketSuccess) {
                return false;
            }
        } else {
            // Purchase NFT
            bool marketSuccess = executeFunctions(_calldataList);
            if (!marketSuccess) {
                return false;
            }

            //Execute Option
            IERC721(nft).approve(_poolAddress, _tokenId);
            IWasabiPool(_poolAddress).executeOptionWithSell(_optionId, _tokenId);
            
            IWETH(wethAddress).deposit{value: totalDebt}();
        }
        
        IERC20(asset).approve(address(lendingPool), totalDebt);

        return true;
    }

    /**
     * @dev Executes a given list of functions
     */
    function executeFunctions(FunctionCallData[] memory _marketplaceCallData) internal returns (bool) {
        for (uint256 i = 0; i < _marketplaceCallData.length; i++) {
            FunctionCallData memory functionCallData = _marketplaceCallData[i];
            (bool success, ) = functionCallData.to.call{value: functionCallData.value}(functionCallData.data);
            if (success == false) {
                return false;
            }
        }
        return true;
    }

    function validate(FunctionCallData[] calldata _marketplaceCallData, bytes[] calldata _signatures) private view {
        require(_marketplaceCallData.length == _signatures.length, "Length is invalid");
        for (uint256 i = 0; i < _marketplaceCallData.length; i++) {
            bytes32 ethSignedMessageHash = Signing.getEthSignedMessageHash(getMessageHash(_marketplaceCallData[i]));
            require(Signing.recoverSigner(ethSignedMessageHash, _signatures[i]) == owner(), 'Owner is not signer');
        }
    }

    /**
     * @dev Returns the message hash for the given data
     */
    function getMessageHash(FunctionCallData calldata data) public pure returns (bytes32) {
        return keccak256(abi.encode(data));
    }
    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address /* operator */,
        address /* from */,
        uint256 /* tokenId */,
        bytes memory /* data */)
    public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
    
    // Payable function to receive ETH
    receive() external payable {
    }
}