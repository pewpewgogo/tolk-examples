import "@stdlib/tvm-dicts.tolk"

// after `grams:Grams` we have (1 + 4 + 4 + 64 + 32) zeroes - zeroed extracurrency, ihr_fee, fwd_fee, created_lt and created_at
const MSG_INFO_REST_BITS = 1 + 4 + 4 + 64 + 32;

// MSG

// https://github.com/ton-blockchain/ton/blob/8a9ff339927b22b72819c5125428b70c406da631/crypto/block/block.tlb#L155
// message$_ {X:Type} info:CommonMsgInfo
//  init:Maybe (Either StateInit ^StateInit)
//  body:(Either X ^X) = Message X;
//
//message$_ {X:Type} info:CommonMsgInfoRelaxed
//  init:(Maybe (Either StateInit ^StateInit))
//  body:(Either X ^X) = MessageRelaxed X;
//
//_ (Message Any) = MessageAny;

// if have StateInit (always place StateInit in ref):
// 0b11 for `Maybe (Either StateInit ^StateInit)` and 0b1 or 0b0 for `body:(Either X ^X)`

const MSG_WITH_STATE_INIT_AND_BODY_SIZE = MSG_INFO_REST_BITS + 1 + 1 + 1;
const MSG_HAVE_STATE_INIT = 4;
const MSG_STATE_INIT_IN_REF = 2;
const MSG_BODY_IN_REF = 1;

// if no StateInit:
// 0b0 for `Maybe (Either StateInit ^StateInit)` and 0b1 or 0b0 for `body:(Either X ^X)`

const MSG_ONLY_BODY_SIZE = MSG_INFO_REST_BITS + 1 + 1;

const TRUE = -1;
const FALSE = 0;

@inline
fun storeStatinitRefAndBodyRef(b: builder, stateInit: cell, body: cell): builder {
    return b
    .storeUint(MSG_HAVE_STATE_INIT + MSG_STATE_INIT_IN_REF + MSG_BODY_IN_REF, MSG_WITH_STATE_INIT_AND_BODY_SIZE)
    .storeRef(stateInit)
    .storeRef(body);
}

@inline
fun storeOnlyBodyRef(b: builder, body: cell): builder {
    return b
    .storeUint(MSG_BODY_IN_REF, MSG_ONLY_BODY_SIZE)
    .storeRef(body);
}

@inline
fun retrieveFwdFee(mutate self: slice): int {
    self.loadAddress(); // skip dst
    self.loadCoins(); // skip value
    self.skipDict(); // skip extracurrency collection
    self.loadCoins(); // skip ihr_fee
    var fwdFee: int = self.loadCoins();
    return fwdFee;
}

@inline
fun storePrefixOnlyBody(b: builder): builder {
    return b
    .storeUint(0, MSG_ONLY_BODY_SIZE);
}

@pure
fun getPrecompiledGasConsumption(): int
    asm "GETPRECOMPILEDGAS";

// TOKEN METADATA
// https://github.com/ton-blockchain/TEPs/blob/master/text/0064-token-data-standard.md

// Key is sha256 hash of string. Value is data encoded as described in "Data serialization" paragraph.
// Snake format - must be prefixed with 0x00 byte
fun setTokenSnakeMetadataEntry(mutate self: cell, key: int, value: slice): void {
    self.uDictSetRef(256, key, beginCell().storeUint(0, 8).storeSlice(value).endCell());
    return;
}

// On-chain content layout The first byte is 0x00 and the rest is key/value dictionary.
@inline
fun createTokenOnchainMetadata(contentDict: cell): cell {
    return beginCell().storeUint(0, 8).storeDict(contentDict).endCell();
}