@inline_ref
fun sendEmptyMessage(amount: int, to: slice, mode: int) {
    var msg: cell = beginCell()
            .storeUint(0x18, 6)
            .storeSlice(to)
            .storeCoins(amount)
            .storeUint(0, 107)
            .endCell();
    sendMessage(msg, mode);
}

@inline_ref
fun sendSimpleMessage(amount: int, to: slice, body: cell, mode: int) {
    var msg: cell = beginCell()
            .storeUint(0x18, 6)
            .storeSlice(to)
            .storeCoins(amount)
            .storeUint(1, 107)
            .storeRef(body)
            .endCell();
    sendMessage(msg, mode);
}

@inline_ref
fun sendMessageWithStateinit(amount: int, to: slice, stateInit: cell, body: cell, mode: int) {
    var msg: cell = beginCell()
            .storeUint(0x18, 6)
            .storeSlice(to)
            .storeCoins(amount)
            .storeUint(7, 108)
            .storeRef(stateInit)
            .storeRef(body)
            .endCell();
    sendMessage(msg, mode);
}

fun sendTextMsg(toAddr: slice, value: int, mode: int, content: builder) {
    var body = beginCell()
            .storeUint(0, 32)
            .storeBuilder(content)
            .endCell();

    var msg = beginCell()
            .storeUint(0x10, 6)
            .storeSlice(toAddr)
            .storeCoins(value)
            .storeUint(1, 1 + 4 + 4 + 64 + 32 + 1 + 1)
            .storeRef(body)
            .endCell();

    sendMessage(msg, mode);
}

@inline
fun createSimpleJettonTransferBody(queryId: int, fwdAmount: int, jettonAmount: int, to: slice): builder {
  return beginCell()
  .storeUint(0xf8a7ea5, 32)
  .storeUint(queryId, 64)
  .storeCoins(jettonAmount)
  .storeSlice(to) // to_owner_address
  .storeSlice(to) // return excess to
  .storeUint(0, 1)
  .storeCoins(fwdAmount) // forward_ton_amount
  .storeUint(0, 1);
}
