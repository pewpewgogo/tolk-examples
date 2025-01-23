import "@stdlib/common.tolk"
import "imports/constants.tolk"

global st_owner_address: slice;

fun loadData() {
    var cs = getContractData().beginParse();
    st_owner_address = cs.loadAddress();
}

fun storeData() {
    setContractData(
        beginCell()
        .storeSlice(st_owner_address)
        .endCell()
    );
}

fun onOwnerMessage(op: int, msgBody: slice) {
    if (op == op_owner_transfer) {
        var to = msgBody.loadAddress();
        var amount = msgBody.loadCoins();
        sendMessage(beginCell()
            .storeUint(BOUNCEABLE, 6)
            .storeSlice(st_owner_address)
            .storeCoins(amount)
            .endCell(),
            SEND_MODE_PAY_FEES_SEPARATELY + SEND_MODE_IGNORE_ERRORS
        );
        return;
    }

    if (op == op_owner_change) {
        var newOwner = msgBody.loadAddress();
        st_owner_address = newOwner;
        storeData();
        return;
    }
}

fun forwardToOwner() {
    sendMessage(beginCell()
        .storeUint(BOUNCEABLE, 6)
        .storeSlice(st_owner_address)
        .storeCoins(0)
        .endCell(),
        SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE + SEND_MODE_IGNORE_ERRORS
    );
}

fun onInternalMessage(myBalance: int, msgValue: int, msgFull: cell, msgBody: slice) {
    loadData();
    var cs = msgFull.beginParse();

    var flags = cs.loadMessageFlags();
    if (isMessageBounced(flags)) {
        return;
    }

    var from = cs.loadAddress();
    if (isSliceBitsEqual(from, st_owner_address)) {
        var op = msgBody.loadMessageOp();
        onOwnerMessage(op, msgBody);
    } else {
        forwardToOwner();
    }
}
