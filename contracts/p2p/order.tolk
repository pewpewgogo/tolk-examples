import "@stdlib/common.tolk"
import "imports/op.tolk"
import "imports/messages.tolk"
import "imports/utils.tolk"

global ctxCompleteState: int;
global ctxAmountTokenA: int;
global ctxAmountTokenB: int;
global ctxOrderOwner: slice;
global ctxTokenA: cell;
global ctxTokenB: cell;

@inline
fun loadData() {
  var ds: slice = getContractData().beginParse();
  ctxCompleteState = ds.loadBool();
  ctxAmountTokenA = ds.loadCoins();
  ctxAmountTokenB = ds.loadCoins();
  ctxOrderOwner = ds.loadAddress();
  ctxTokenA = ds.loadRef();
  ctxTokenB = ds.loadRef();
  ds.assertEndOfSlice();
}

@inline
fun saveData() {
  setContractData(
    beginCell()
    .storeBool(ctxCompleteState)
      .storeCoins(ctxAmountTokenA)
      .storeCoins(ctxAmountTokenB)
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
      assert(msgValue >= 100000000) throw errorNotEnoughTon; // 0.1 TON
      var (queryId: int, jettonAmount: int, fromUser: slice) = (inMsgBody.loadMessageQueryId(), inMsgBody.loadCoins(), inMsgBody.loadAddress());
      loadData();
      assert(ctxCompleteState == 0) throw errorOrderCompletedAlready;
      val (minterAddressA, decimalA, jettonCodeA) = upackTokenData(ctxTokenA);
      val (minterAddressB, decimalB, jettonCodeB) = upackTokenData(ctxTokenB);
      val jettonWalletAddressA: slice = calculateUserJettonWalletAddress(getMyAddress(), minterAddressA, jettonCodeA);
      val jettonWalletAddressB: slice = calculateUserJettonWalletAddress(getMyAddress(), minterAddressB, jettonCodeB);
      if (isSliceBitsEqual(fromAddress, jettonWalletAddressA)) {
        // accept order deploy and send confirmation to owner?
      }
      val isB: int = isSliceBitsEqual(fromAddress, jettonWalletAddressB);
      assert(isB) throw errorWrongToken; // we accept JettonB only
      assert(ctxAmountTokenB == jettonAmount) throw errorWrongTokenAmount; // check amount equal excepted amount

      sendTokens(fromUser, minterAddressA, ctxAmountTokenA, jettonCodeA); // send token A to fromUser
      sendTokens(ctxOrderOwner, minterAddressB, jettonAmount, jettonCodeB); // send token B to owner
      ctxCompleteState = -1; // complete order
      saveData();
      return;
    }

  throw 999;
}

get state(): (int, int, int) {
  loadData();
  return (ctxCompleteState, ctxAmountTokenA, ctxAmountTokenB);
}
