const op_reset_counter = "OpResetCounter"c; // 0x3dc2af2d

// global variables context (also you can declare global variables in separate file like storage.tolk and import it)
global ctxOwnerAddress: slice;
global ctxCounter: int;

@inline
fun loadCtx() { // method for loading data from storage
    var cs = getContractData().beginParse(); // getContractData is a standard function for loading data from storage
    ctxOwnerAddress = cs.loadAddress();
    ctxCounter = cs.loadUint(32);
}

@inline
fun storeCtx() { // method for storing data to storage
    setContractData( // setContractData is a standard function for storing data to storage
        beginCell()
        .storeSlice(ctxOwnerAddress)
        .storeUint(ctxCounter, 32)
        .endCell()
    );
}

fun onInternalMessage(msgFull: cell, msgBody: slice) { // Entrypoint for all internal messages (from other contracts)
    loadCtx(); // load data from storage and fill ctx variables
    var cs = msgFull.beginParse(); // start parse income message
    cs.loadMessageFlags(); // load message flags
    var sender = cs.loadAddress(); // read sender address from msg

    if (isSliceBitsEqual(sender, ctxOwnerAddress) & !isEndOfSlice(msgBody)) { // // isSliceBitsEqual - standart function for comparing slices. isEndOfSlice - standart function for checking empty or end of slice
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