import "@stdlib/common.tolk"

import "constants.tolk"

global st_owner_address: slice;

@inline
fun loadData() {
    var cs = getContractData().beginParse();
    st_owner_address = cs.loadAddress();
}

@inline
fun storeData() {
    setContractData(
        beginCell()
        .storeSlice(st_owner_address)
        .endCell()
    );
}

fun onInternalMessage(msgValue: int, inMsgFull: cell, inMsgBody: slice) {
    loadData();
    var cs = inMsgFull.beginParse();

    val flags = cs.loadMessageFlags();
    if (isMessageBounced(flags)) {
        return;
    }

    val from = cs.loadAddress();
    if (isSliceBitsEqual(from, st_owner_address)) {
        val op = inMsgBody.loadMessageOp();
        val queryId = inMsgBody.loadMessageQueryId();
        onOwnerMessage(op, inMsgBody);
    } else {
        forwardToOwner(inMsgBody);
    }

    return;
}

@inline
fun onOwnerMessage(op: int, msgBody: slice) {
    if (op == op_owner_transfer) {
        val to = msgBody.loadAddress();
        val amount = msgBody.loadCoins();
        sendMessage(beginCell()
            .storeUint(BOUNCEABLE, 6)
            .storeSlice(st_owner_address)
            .storeCoins(amount)
            .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1) // todo: replace with something normal
            .endCell(),
            SEND_MODE_IGNORE_ERRORS | SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE
        );
        return;
    }

    if (op == op_owner_change) {
        val newOwner = msgBody.loadAddress();
        st_owner_address = newOwner;
        storeData();
    }
}

@inline
fun forwardToOwner(inMsgBody: slice) {
    var outMsgBody: builder = beginCell()
        .storeUint(BOUNCEABLE, 6)
        .storeSlice(st_owner_address)
        .storeCoins(0)
        .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1); // todo: replace with someting normal

    if (!isEndOfSlice(inMsgBody)) {
        outMsgBody.storeBool(-1);
        outMsgBody.storeRef(beginCell().storeSlice(inMsgBody).endCell());
    } else {
        outMsgBody.storeBool(0);
    }

    sendMessage(outMsgBody.endCell(),
        SEND_MODE_IGNORE_ERRORS | SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE
    );
}