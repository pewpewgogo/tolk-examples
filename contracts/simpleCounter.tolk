const op_reset_counter = "OpResetCounter"c; // 0x3dc2af2d

// global variables context
global ctxOwnerAddress: slice;
global ctxCounter: int;

fun loadCtx() { // method for loading data from storage
    var cs = getContractData().beginParse(); // getContractData is a standard function for loading data from storage
    ctxOwnerAddress = cs.loadAddress();
    ctxCounter = cs.loadUint(32);
}

fun storeCtx() { // method for storing data to storage
    setContractData( // setContractData is a standard function for storing data to storage
        beginCell()
        .storeSlice(ctxOwnerAddress)
        .storeUint(ctxCounter, 32)
        .endCell()
    );
}

fun onInternalMessage(msgValue: int, msgFull: cell, msgBody: slice) { // All internal messages (from other contracts) are processed in onInternalMessage method
    loadCtx(); // load data from storage and fill ctx variables
    var cs = msgFull.beginParse(); // start parse income message
    cs.loadMessageFlags(); // load message flags
    var sender = cs.loadAddress(); // read sender address from msg

    if (isSliceBitsEqual(sender, ctxOwnerAddress) & !isEndOfSlice(msgBody)) { // isSliceBitsEqual - standart function for comparing slices
        var op = msgBody.loadMessageOp(); // load operation from message body (32 uint)
        if (op == op_reset_counter) {
            ctxCounter = 0; // update counter value
            storeCtx(); // update ctx data in contract storage
            return;
        }
    }

    ctxCounter += 1;
    storeCtx();
}

get counter(): int { // get method for counter value
    loadCtx();
    return ctxCounter;
}

get owner(): slice { // get method for owner address
    loadCtx();
    return ctxOwnerAddress;
}