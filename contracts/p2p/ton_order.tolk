import "@stdlib/common.tolk"
import "imports/op.tolk"
import "imports/messages.tolk"
import "imports/utils.tolk"

global ctxAdmin: slice;
global ctxTokenA: cell;
global ctxTokenB: cell;

@inline
fun loadData() {
  var ds: slice = getContractData().beginParse();
  ctxAdmin = ds.loadAddress();
  ctxTokenA = ds.loadRef();
  ctxTokenB = ds.loadRef();
  ds.assertEndOfSlice();
}

@inline
fun saveData() {
  setContractData(
    beginCell()
      .storeSlice(ctxAdmin)
      .storeRef(ctxTokenA)
      .storeRef(ctxTokenB)
    .endCell()
  );
}

@inline
fun upackTokenData(data: cell) {
  var ds = data.beginParse();

  return (ds.loadAddress(), ds.loadUint(4), ds.loadRef());
}

@inline
fun sendTokens(to: slice, minter: slice, jettonAmount: int, code: cell) {
  var body: builder = createSimpleJettonTransferBody(0, 0, jettonAmount, to);
  var toJettonAddress: slice = calculateUserJettonWalletAddress(getMyAddress(), minter, code);
  sendSimpleMessage(
    42000000, // fix commision
    toJettonAddress,
    body.endCell(),
    SEND_MODE_IGNORE_ERRORS | SEND_MODE_PAY_FEES_SEPARATELY
  );
}

@inline
fun sendConfirmation() {
  sendTextMsg(
    ctxOrderOwner,
    1,
    SEND_MODE_IGNORE_ERRORS | SEND_MODE_PAY_FEES_SEPARATELY,
    beginCell().storeUint()
  );
}

fun onInternalMessage(msgValue: int, inMsgFull: cell, inMsgBody: slice) {
    if (inMsgBody.isEndOfSlice()) { // ignore empty messages
      return;
    }

    var cs: slice = inMsgFull.beginParse();
    val flags: int = cs.loadMessageFlags();
    if (isMessageBounced(flags)) {
      return;
    }

    val fromAddress: slice = cs.loadAddress();
    var op: int = inMsgBody.loadMessageOp();

    if (op == opTransferNotification) {
      assert(msgValue >= 100000000) throw errorNotEnoughTon; // 0.1 TON todo: Add a proper gas count
      var (queryId: int, jettonAmount: int, fromUser: slice) = (inMsgBody.loadMessageQueryId(), inMsgBody.loadCoins(), inMsgBody.loadAddress());
      loadData();
      val (minterAddressA, _, jettonCodeA) = upackTokenData(ctxTokenA);
      val (minterAddressB, _, jettonCodeB) = upackTokenData(ctxTokenB);
      val jettonWalletAddressA: slice = calculateUserJettonWalletAddress(getMyAddress(), minterAddressA, jettonCodeA);
      val jettonWalletAddressB: slice = calculateUserJettonWalletAddress(getMyAddress(), minterAddressB, jettonCodeB);
      if (isSliceBitsEqual(fromAddress, jettonWalletAddressA)) {
        // deploy order?
      }
      val isB: int = isSliceBitsEqual(fromAddress, jettonWalletAddressB);
      assert(isB) throw errorWrongToken; // we accept JettonB only
      assert(ctxAmountTokenB == jettonAmount) throw errorWrongTokenAmount; // check amount equal excepted amount

      sendTokens(fromUser, minterAddressA, ctxAmountTokenA, jettonCodeA); // send token A to fromUser
      sendTokens(ctxOrderOwner, minterAddressB, jettonAmount, jettonCodeB); // send token B to owner
      ctxCompleteStatus = -1; // complete order
      saveData();
      return;
    }

  throw 999;
}

get state(): (int, int, int) {
  loadData();
  return (ctxCompleteStatus, ctxAmountTokenA, ctxAmountTokenB);
}