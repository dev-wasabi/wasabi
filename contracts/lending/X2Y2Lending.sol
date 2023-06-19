// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/INFTLending.sol";
import "./interfaces/x2y2/IXY3.sol";

/// @title X2Y2 Lending
/// @notice Manages creating and repaying a loan on X2Y2
contract X2Y2Lending is INFTLending {
    using SafeERC20 for IERC20;

    /// @notice XY3 Contract
    IXY3 public constant xy3 = IXY3(0xFa4D5258804D7723eb6A934c11b1bd423bC31623);

    /// @inheritdoc INFTLending
    function borrow(
        bytes calldata _inputData
    ) external returns (uint256) {
        // Decode `inputData` into Offer, Signature and BorrowerSettings
        (
            IXY3.Offer memory offer,
            uint256 nftId,
            bool isCollectionOffer,
            IXY3.Signature memory lenderSignature,
            IXY3.Signature memory brokerSignature,
            IXY3.CallData memory extraDeal
        ) = abi.decode(
                _inputData,
                (
                    IXY3.Offer,
                    uint256,
                    bool,
                    IXY3.Signature,
                    IXY3.Signature,
                    IXY3.CallData
                )
            );

        IERC721 nft = IERC721(offer.nftAsset);

        // Approve
        nft.setApprovalForAll(address(xy3), true);

        // Borrow on X2Y2
        uint32 loanId = xy3.borrow(
            offer,
            nftId,
            isCollectionOffer,
            lenderSignature,
            brokerSignature,
            extraDeal
        );

        // Return loan id
        return uint256(loanId);
    }

    /// @inheritdoc INFTLending
    function repay(uint256 _loanId, address _receiver) external {
        uint32 loanId = uint32(_loanId);

        // Get LoanDetail for loanId
        IXY3.LoanDetail memory loanDetail = xy3.loanDetails(loanId);

        // Approve token to `xy3`
        IERC20 token = IERC20(loanDetail.borrowAsset);
        token.safeApprove(address(xy3), 0);
        token.safeApprove(address(xy3), loanDetail.repayAmount);

        // Pay back loan
        xy3.repay(loanId);

        // Transfer collateral NFT to the user
        IERC721(loanDetail.nftAsset).safeTransferFrom(
            address(this),
            _receiver,
            loanDetail.nftTokenId
        );
    }
}
