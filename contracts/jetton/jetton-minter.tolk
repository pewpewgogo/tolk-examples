tolk 0.6

import "@stdlib/common.tolk"
import "@stdlib/gas-payments.tolk"
import "@stdlib/tvm-dicts.tolk"

import "func-stdlib.tolk"
import "op-codes.tolk"
import "workchain.tolk"
import "jetton-utils.tolk"
import "gas.tolk"

// storage#_ total_supply:Coins admin_address:MsgAddress next_admin_address:MsgAddress jetton_wallet_code:^Cell metadata_uri:^Cell = Storage;
@inline
fun loadData(): (int, slice, slice, cell, cell) {
    var ds: slice = getContractData().beginParse();
    var data = (
        ds.loadCoins(), // total_supply
        ds.loadAddress(), // admin_address
        ds.loadAddress(), // next_admin_address
        ds.loadRef(),  // jetton_wallet_code
        ds.loadRef()  // metadata url (contains snake slice without 0x0 prefix)
    );
    ds.assertEndOfSlice();
    return data;
}

@inline
fun saveData(totalSupply: int, adminAddress: slice, nextAdminAddress: slice, jettonWalletCode: cell, metadataUri: cell) {
    setContractData(
        beginCell()
        .storeCoins(totalSupply)
        .storeSlice(adminAddress)
        .storeSlice(nextAdminAddress)
        .storeRef(jettonWalletCode)
        .storeRef(metadataUri)
        .endCell()
    );
}

@inline
fun sendToJettonWallet(toAddress: slice, jettonWalletCode: cell, tonAmount: int, masterMsg: cell, needStateInit: int) {
    reserveToncoinsOnBalance(ONE_TON / 100, RESERVE_MODE_EXACT_AMOUNT); // reserve for storage fees

    val stateInit: cell = calculateJettonWalletStateInit(toAddress, getMyAddress(), jettonWalletCode);
    val toWalletAddress: slice = calculateJettonWalletAddress(stateInit);

    // build MessageRelaxed, see TL-B layout in stdlib.fc#L733
    var msg = beginCell()
    .storeUint(BOUNCEABLE, 6) // add store_msg_flags_and_address_none or replace with similar // todo: Replace storeUint with named method
    .storeSlice(toWalletAddress) // dest
    .storeCoins(tonAmount);

    if (needStateInit) {
        msg = msg.storeStatinitRefAndBodyRef(stateInit, masterMsg);
    } else {
        msg = msg.storeOnlyBodyRef(masterMsg);
    }

    sendMessage(msg.endCell(), SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
}

fun onInternalMessage(msgValue: int, inMsgFull: cell, inMsgBody: slice) {
    var inMsgFullSlice: slice = inMsgFull.beginParse();
    val msgFlags: int = inMsgFullSlice.loadMessageFlags();

    if (isMessageBounced(msgFlags)) {
        inMsgBody.skipBouncedPrefix();
        // process only mint bounces
        if (!(inMsgBody.loadMessageOp() == `op::internal_transfer`)) {
            return;
        }
        inMsgBody.skipMessageQueryId();
        val jettonAmount: int = inMsgBody.loadCoins();
        val (totalSupply: int, adminAddress: slice, nextAdminAddress: slice, jettonWalletCode: cell, metadataUri: cell) = loadData();
        saveData(totalSupply - jettonAmount, adminAddress, nextAdminAddress, jettonWalletCode, metadataUri);
        return;
    }
    val senderAddress: slice = inMsgFullSlice.loadAddress();

    val fwdFeeFromInMsg: int = inMsgFullSlice.retrieveFwdFee();
    val fwdFee: int = calculateOriginalMessageFee(MY_WORKCHAIN, fwdFeeFromInMsg); // we use message fwd_fee for estimation of forward_payload costs

    val op: int = inMsgBody.loadMessageOp();
    val queryId: int = inMsgBody.loadMessageQueryId();

    var (totalSupply: int, adminAddress: slice, nextAdminAddress: slice, jettonWalletCode: cell, metadataUri: cell) = loadData();

    if (op == `op::mint`) {
        assert(isSliceBitsEqual(senderAddress, adminAddress)) throw `error::not_owner`;
        val toAddress: slice = inMsgBody.loadAddress();
        checkSameWorkchain(toAddress);
        val tonAmount: int = inMsgBody.loadCoins();
        val masterMsg: cell = inMsgBody.loadRef();
        inMsgBody.assertEndOfSlice();

        // see internal_transfer TL-B layout in jetton.tlb
        var masterMsgSlice: slice = masterMsg.beginParse();
        assert(masterMsgSlice.loadMessageOp() == `op::internal_transfer`) throw `error::invalid_op`;
        masterMsgSlice.skipMessageQueryId();
        val jettonAmount: int = masterMsgSlice.loadCoins();
        masterMsgSlice.loadAddress(); // from_address
        masterMsgSlice.loadAddress(); // response_address
        val forwardTonAmount: int = masterMsgSlice.loadCoins(); // forward_ton_amount
        checkEitherForwardPayload(masterMsgSlice); // either_forward_payload

        // a little more than needed, it’s ok since it’s sent by the admin and excesses will return back
        checkAmountIsEnoughToTransfer(tonAmount, forwardTonAmount, fwdFee);

        sendToJettonWallet(toAddress, jettonWalletCode, tonAmount, masterMsg, TRUE);
        saveData(totalSupply + jettonAmount, adminAddress, nextAdminAddress, jettonWalletCode, metadataUri);
        return;
    }

    if (op == `op::burn_notification`) {
        // see burn_notification TL-B layout in jetton.tlb
        val jettonAmount: int = inMsgBody.loadCoins();
        val fromAddress: slice = inMsgBody.loadAddress();
        assert(isSliceBitsEqual(calculateUserJettonWalletAddress(fromAddress, getMyAddress(), jettonWalletCode), senderAddress)) throw `error::not_valid_wallet`;
        saveData(totalSupply - jettonAmount, adminAddress, nextAdminAddress, jettonWalletCode, metadataUri);
        val responseAddress: slice = inMsgBody.loadAddress();
        inMsgBody.assertEndOfSlice();

        if (!addressIsNone(responseAddress)) {
            // build MessageRelaxed, see TL-B layout in stdlib.fc#L733
            var msg = beginCell()
            .storeUint(NON_BOUNCEABLE, 6) // todo: Replace storeUint with named method
            .storeSlice(responseAddress) // dest
            .storeCoins(0)
            .storePrefixOnlyBody()
            .storeMessageOp(`op::excesses`)
            .storeMessageQueryId(queryId);
            sendMessage(msg.endCell(), SEND_MODE_IGNORE_ERRORS | SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }
        return;
    }

    if (op == `op::provide_wallet_address`) {
        // see provide_wallet_address TL-B layout in jetton.tlb
        val ownerAddress: slice = inMsgBody.loadAddress();
        val isIncludeAddress: int = inMsgBody.loadBool();
        inMsgBody.assertEndOfSlice();

        val includedAddress: cell = isIncludeAddress
        ? beginCell().storeSlice(ownerAddress).endCell()
        : null;

        // build MessageRelaxed, see TL-B layout in stdlib.fc#L733
        var msg = beginCell()
        .storeUint(NON_BOUNCEABLE, 6) // todo: Replace storeUint with named method
        .storeSlice(senderAddress)
        .storeCoins(0)
        .storePrefixOnlyBody()
        .storeMessageOp(`op::take_wallet_address`)
        .storeMessageQueryId(queryId);

        if (isSameWorkchain(ownerAddress)) {
            msg = msg.storeSlice(calculateUserJettonWalletAddress(ownerAddress, getMyAddress(), jettonWalletCode));
        } else {
            msg = msg.storeAddressNone();
        }

        val msgCell: cell = msg.storeMaybeRef(includedAddress).endCell();

        sendMessage(msgCell, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        return;
    }

    if (op == `op::change_admin`) {
        assert(isSliceBitsEqual(senderAddress, adminAddress)) throw `error::not_owner`;
        nextAdminAddress = inMsgBody.loadAddress();
        inMsgBody.assertEndOfSlice();
        saveData(totalSupply, adminAddress, nextAdminAddress, jettonWalletCode, metadataUri);
        return;
    }

    if (op == `op::claim_admin`) {
        inMsgBody.assertEndOfSlice();
        assert(isSliceBitsEqual(senderAddress, nextAdminAddress)) throw `error::not_owner`;
        saveData(totalSupply, nextAdminAddress, createAddressNone(), jettonWalletCode, metadataUri);
        return;
    }

    if (op == `op::drop_admin`) {
        assert(isSliceBitsEqual(senderAddress, adminAddress)) throw `error::not_owner`;
        inMsgBody.assertEndOfSlice();
        saveData(totalSupply, createAddressNone(), createAddressNone(), jettonWalletCode, metadataUri);
        return;
    }

    if (op == `op::change_metadata_uri`) {
        assert(isSliceBitsEqual(senderAddress, adminAddress)) throw `error::not_owner`;
        saveData(totalSupply, adminAddress, nextAdminAddress, jettonWalletCode, beginCell().storeSlice(inMsgBody).endCell());
        return;
    }

    if (op == `op::upgrade`) {
        assert(isSliceBitsEqual(senderAddress, adminAddress)) throw `error::not_owner`;
        var (newData: cell, newCode: cell) = (inMsgBody.loadRef(), inMsgBody.loadRef());
        inMsgBody.assertEndOfSlice();
        setContractData(newData);
        setContractCodePostponed(newCode);
        return;
    }

    if (op == `op::top_up`) {
        return; // just accept tons
    }

    throw `error::wrong_op`;
}

@inline
fun buildContentCell(metadataUri: slice): cell {
    var contentDict: cell = createEmptyDict();
    contentDict.setTokenSnakeMetadataEntry("uri"H, metadataUri);
    contentDict.setTokenSnakeMetadataEntry("decimals"H, "9");
    return createTokenOnchainMetadata(contentDict);
}

get get_jetton_data(): (int, int, slice, cell, cell) {
    val (totalSupply: int, adminAddress: slice, nextAdminAddress: slice, jettonWalletCode: cell, metadataUri: cell) = loadData();
    return (totalSupply, TRUE, adminAddress, buildContentCell(metadataUri.beginParse()), jettonWalletCode);
}

get get_wallet_address(ownerAddress: slice): slice {
    val (totalSupply: int, adminAddress: slice, nextAdminAddress: slice, jettonWalletCode: cell, metadataUri: cell) = loadData();
    return calculateUserJettonWalletAddress(ownerAddress, getMyAddress(), jettonWalletCode);
}

get get_next_admin_address(): slice {
    val (totalSupply: int, adminAddress: slice, nextAdminAddress: slice, jettonWalletCode: cell, metadataUri: cell) = loadData();
    return nextAdminAddress;
}
