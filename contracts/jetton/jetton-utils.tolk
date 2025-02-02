import "workchain.tolk"
import "op-codes.tolk"

const STATUS_SIZE = 4;

@inline
fun packJettonWalletDataBuilder(status: int, balance: int, ownerAddress: slice, jettonMasterAddress: slice): builder {
    return beginCell()
        .storeUint(status, STATUS_SIZE)
        .storeCoins(balance)
        .storeSlice(ownerAddress)
        .storeSlice(jettonMasterAddress);
}

@inline
fun packJettonWalletData(status: int, balance: int, ownerAddress: slice, jettonMasterAddress: slice): cell {
    return packJettonWalletDataBuilder(status, balance, ownerAddress, jettonMasterAddress)
           .endCell();
}

@inline
fun calculateJettonWalletStateInit(ownerAddress: slice, jettonMasterAddress: slice, jettonWalletCode: cell): cell {
    /*
    https://github.com/ton-blockchain/ton/blob/8a9ff339927b22b72819c5125428b70c406da631/crypto/block/block.tlb#L144
    _ split_depth:(Maybe (## 5)) special:(Maybe TickTock)
    code:(Maybe ^Cell) data:(Maybe ^Cell)
    library:(Maybe ^Cell) = StateInit;
  */
    return beginCell()
    .storeUint(0, 2) // 0b00 - No split_depth; No special
    .storeMaybeRef(jettonWalletCode)
    .storeMaybeRef(
        packJettonWalletData(
            0, // status
            0, // balance
            ownerAddress,
            jettonMasterAddress)
    )
    .storeUint(0, 1) // Empty libraries
    .endCell();
}

@inline
fun calculateJettonWalletAddress(stateInit: cell): slice {
    /*
    https://github.com/ton-blockchain/ton/blob/8a9ff339927b22b72819c5125428b70c406da631/crypto/block/block.tlb#L105
    addr_std$10 anycast:(Maybe Anycast) workchain_id:int8 address:bits256  = MsgAddressInt;
    */
    return beginCell()
    .storeUint(4, 3) // 0b100 = addr_std$10 tag; No anycast
    .storeInt(MY_WORKCHAIN, 8)
    .storeUint(cellHash(stateInit), 256)
    .endCell()
    .beginParse();
}

@inline
fun calculateUserJettonWalletAddress(ownerAddress: slice, jettonMasterAddress: slice, jettonWalletCode: cell): slice {
    return calculateJettonWalletAddress(calculateJettonWalletStateInit(ownerAddress, jettonMasterAddress, jettonWalletCode));
}

@inline
fun checkEitherForwardPayload(s: slice) {
    if (s.preloadUint(1)) {
        // forward_payload in ref
        var (remainBits: int, remainRefs: int) = getRemainingBitsAndRefsCount(s);
        assert((remainRefs == 1) & (remainBits == 1)) throw `error::invalid_message`; // we check that there is no excess in the slice
    }
    // else forward_payload in slice - arbitrary bits and refs
}
