// Jetton Wallet Smart Contract

tolk 0.6

import "@stdlib/common.tolk"
import "@stdlib/gas-payments.tolk"

import "func-stdlib.tolk"
import "op-codes.tolk"
import "workchain.tolk"
import "jetton-utils.tolk"
import "gas.tolk"

/*
  Storage

  storage#_ status:uint4
            balance:Coins owner_address:MsgAddressInt
            jetton_master_address:MsgAddressInt = Storage;
*/

@inline
fun loadData(): (int, int, slice, slice) {
    var ds: slice = getContractData().beginParse();
    var data = (
        ds.loadUint(STATUS_SIZE), // status
        ds.loadCoins(), // balance
        ds.loadAddress(), // owner_address
        ds.loadAddress() // jetton_master_address
    );
    ds.assertEndOfSlice();
    return data;
}

@inline
fun saveData(status: int, balance: int, ownerAddress: slice, jettonMasterAddress: slice) {
    var dataBuilder: builder = packJettonWalletDataBuilder(status, balance, ownerAddress, jettonMasterAddress);
    setContractData(dataBuilder.endCell());
}


@inline_ref
fun sendJettons(inMsgBody: slice, senderAddress: slice, msgValue: int, fwdFee: int) {
    // see transfer TL-B layout in jetton.tlb
    var queryId: int = inMsgBody.loadMessageQueryId();
    var jettonAmount: int = inMsgBody.loadCoins();
    var toOwnerAddress: slice = inMsgBody.loadAddress();
    checkSameWorkchain(toOwnerAddress);
    var (status: int, balance: int, ownerAddress: slice, jettonMasterAddress: slice) = loadData();
    // int outgoing_transfers_unlocked = ((status & 1) == 0);
    //throw_unless(error::contract_locked, outgoing_transfers_unlocked);
    assert(isSliceBitsEqual(ownerAddress, senderAddress)) throw `error::not_owner`;

    balance -= jettonAmount;
    assert(balance >= 0) throw `error::balance_error`;

    var stateInit: cell = calculateJettonWalletStateInit(toOwnerAddress, jettonMasterAddress, getContractCode());
    var toWalletAddress: slice = calculateJettonWalletAddress(stateInit);
    var responseAddress: slice = inMsgBody.loadAddress();
    inMsgBody.skipMaybeRef(); // custom_payload
    var forwardTonAmount: int = inMsgBody.loadCoins();
    checkEitherForwardPayload(inMsgBody);
    var eitherForwardPayload: slice = inMsgBody;

    // see internal TL-B layout in jetton.tlb
    var msgBody: cell = beginCell()
    .storeMessageOp(`op::internal_transfer`)
    .storeMessageQueryId(queryId)
    .storeCoins(jettonAmount)
    .storeSlice(ownerAddress)
    .storeSlice(responseAddress)
    .storeCoins(forwardTonAmount)
    .storeSlice(eitherForwardPayload)
    .endCell();

    // build MessageRelaxed, see TL-B layout in stdlib.fc#L733
    var msg: cell = beginCell()
    .storeUint(BOUNCEABLE, 6)
    .storeSlice(toWalletAddress)
    .storeCoins(0)
    .storeStatinitRefAndBodyRef(stateInit, msgBody)
    .endCell();

    checkAmountIsEnoughToTransfer(msgValue, forwardTonAmount, fwdFee);

    sendMessage(msg, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);

    saveData(status, balance, ownerAddress, jettonMasterAddress);
}

@inline_ref
fun receiveJettons(inMsgBody: slice, senderAddress: slice, myTonBalance: int, msgValue: int) {
    var (status: int, balance: int, ownerAddress: slice, jettonMasterAddress: slice) = loadData();
    // int incoming_transfers_locked = ((status & 2) == 2);
    // throw_if(error::contract_locked, incoming_transfers_locked);
    // see internal TL-B layout in jetton.tlb
    var queryId: int = inMsgBody.loadMessageQueryId();
    var jettonAmount: int = inMsgBody.loadCoins();
    var fromAddress: slice = inMsgBody.loadAddress();
    var responseAddress: slice = inMsgBody.loadAddress();
    assert(isSliceBitsEqual(jettonMasterAddress, senderAddress)
        |
        isSliceBitsEqual(calculateUserJettonWalletAddress(fromAddress, jettonMasterAddress, getContractCode()), senderAddress)) throw `error::not_valid_wallet`;
    balance += jettonAmount;

    var forwardTonAmount: int = inMsgBody.loadCoins();

    if (forwardTonAmount > 0) {
        var eitherForwardPayload: slice = inMsgBody;

        // see transfer_notification TL-B layout in jetton.tlb
        var msgBody: cell = beginCell()
        .storeMessageOp(`op::transfer_notification`)
        .storeMessageQueryId(queryId)
        .storeCoins(jettonAmount)
        .storeSlice(fromAddress)
        .storeSlice(eitherForwardPayload)
        .endCell();

        // build MessageRelaxed, see TL-B layout in stdlib.fc#L733
        var msg: cell = beginCell()
        .storeUint(NON_BOUNCEABLE, 6)
        .storeSlice(ownerAddress)
        .storeCoins(forwardTonAmount)
        .storeOnlyBodyRef(msgBody)
        .endCell();

        sendMessage(msg, SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
    }

    if (!addressIsNone(responseAddress)) {
        var toLeaveOnBalance: int = myTonBalance - msgValue + getMyStorageDuePayment();
        reserveToncoinsOnBalance(max(toLeaveOnBalance, calculateJettonWalletMinStorageFee()), RESERVE_MODE_AT_MOST);

        // build MessageRelaxed, see TL-B layout in stdlib.fc#L733
        var msg: cell = beginCell()
        .storeUint(NON_BOUNCEABLE, 6)
        .storeSlice(responseAddress)
        .storeCoins(0)
        .storePrefixOnlyBody()
        .storeMessageOp(`op::excesses`)
        .storeMessageQueryId(queryId)
        .endCell();
        sendMessage(msg, SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
    }

    saveData(status, balance, ownerAddress, jettonMasterAddress);
}

@inline_ref
fun burnJettons(inMsgBody: slice, senderAddress: slice, msgValue: int) {
    var (status: int, balance: int, ownerAddress: slice, jettonMasterAddress: slice) = loadData();
    val queryId: int = inMsgBody.loadMessageQueryId();
    val jettonAmount: int = inMsgBody.loadCoins();
    val responseAddress: slice = inMsgBody.loadAddress();
    inMsgBody.skipMaybeRef(); // custom_payload
    inMsgBody.assertEndOfSlice();

    balance -= jettonAmount;
    assert(isSliceBitsEqual(ownerAddress, senderAddress)) throw `error::not_owner`;
    assert(balance >= 0) throw `error::balance_error`;

    // see burn_notification TL-B layout in jetton.tlb
    var msgBody: cell = beginCell()
    .storeMessageOp(`op::burn_notification`)
    .storeMessageQueryId(queryId)
    .storeCoins(jettonAmount)
    .storeSlice(ownerAddress)
    .storeSlice(responseAddress)
    .endCell();

    // build MessageRelaxed, see TL-B layout in stdlib.fc#L733
    var msg: cell = beginCell()
    .storeUint(BOUNCEABLE, 6)
    .storeSlice(jettonMasterAddress)
    .storeCoins(0)
    .storeOnlyBodyRef(msgBody)
    .endCell();

    checkAmountIsEnoughToBurn(msgValue);

    sendMessage(msg, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);

    saveData(status, balance, ownerAddress, jettonMasterAddress);
}

@inline
fun onBounce(inMsgBody: slice) {
    inMsgBody.skipBouncedPrefix();
    var (status: int, balance: int, ownerAddress: slice, jettonMasterAddress: slice) = loadData();
    var op: int = inMsgBody.loadMessageOp();
    assert((op == `op::internal_transfer`) | (op == `op::burn_notification`)) throw `error::wrong_op`;
    inMsgBody.skipMessageQueryId();
    var jettonAmount: int = inMsgBody.loadCoins();
    saveData(status, balance + jettonAmount, ownerAddress, jettonMasterAddress);
}

fun onInternalMessage(myTonBalance: int, msgValue: int, inMsgFull: cell, inMsgBody: slice) {
    var inMsgFullSlice: slice = inMsgFull.beginParse();
    var msgFlags: int = inMsgFullSlice.loadMessageFlags();
    if (isMessageBounced(msgFlags)) {
        onBounce(inMsgBody);
        return;
    }
    var senderAddress: slice = inMsgFullSlice.loadAddress();
    var fwdFeeFromInMsg: int = inMsgFullSlice.retrieveFwdFee();
    var fwdFee: int = calculateOriginalMessageFee(MY_WORKCHAIN, fwdFeeFromInMsg); // we use message fwd_fee for estimation of forward_payload costs

    var op: int = inMsgBody.loadMessageOp();

    // outgoing transfer
    if (op == `op::transfer`) {
        sendJettons(inMsgBody, senderAddress, msgValue, fwdFee);
        return;
    }

    // incoming transfer
    if (op == `op::internal_transfer`) {
        receiveJettons(inMsgBody, senderAddress, myTonBalance, msgValue);
        return;
    }

    // burn
    if (op == `op::burn`) {
        burnJettons(inMsgBody, senderAddress, msgValue);
        return;
    }

    if (op == `op::top_up`) {
        return; // just accept tons
    }

    throw `error::wrong_op`;
}

get get_wallet_data(): (int, slice, slice, cell) {
    var (status: int, balance: int, ownerAddress: slice, jettonMasterAddress: slice) = loadData();
    return (balance, ownerAddress, jettonMasterAddress, getContractCode());
}

get get_status(): int {
    var (status: int, _, _, _) = loadData();
    return status;
}
