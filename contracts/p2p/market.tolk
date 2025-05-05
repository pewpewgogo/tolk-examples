import "@stdlib/common.tolk"
import "imports/op.tolk"
import "imports/messages.tolk"
import "imports/utils.tolk"

global ctxAdminAddress: slice;
global ctxFeeAddress: slice;
global ctxFreezeTime: int;

@inline
fun loadData() {
  var ds: slice = getContractData().beginParse();
  ctxAdminAddress = ds.loadAddress();
  ctxFeeAddress = ds.loadAddress();
  ctxFreezeTime = ds.loadUint(32);
  ds.assertEndOfSlice();
}

@inline
fun saveData() {
  setContractData(
    beginCell()
      .storeSlice(ctxAdminAddress)
      .storeSlice(ctxFeeAddress)
      .storeUint(ctxFreezeTime, 32)
    .endCell()
  );
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
    loadData();
    assert(isSliceBitsEqual(fromAddress, ctxAdminAddress)) throw errorNotAdmin;
    var op: int = inMsgBody.loadMessageOp();

    if (op == opClaimFee) {
      assert(msgValue >= 100000000) throw errorNotEnoughTon; // 0.1 TON
      var (_, isTon: int) = (inMsgBody.loadMessageQueryId(), inMsgBody.loadBool());
      if (isTon) {
        val amount = inMsgBody.loadCoins();
        sendEmptyMessage(amount, ctxFeeAddress, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        return ();
      } else {
        val (amount, minterAddress, jettonWalletCode) = (inMsgBody.loadCoins(), inMsgBody.loadAddress(), inMsgBody.loadRef());
        sendTokens(ctxFeeAddress, minterAddress, amount, jettonWalletCode);
        return ();
      }
    }

    if (op == opChangeFeeAddress) {
      if (ctxFreezeTime == 0) {
        ctxFreezeTime = now();
        saveData();
        return ();
      }

      assert(ctxFreezeTime + 60 * 60 * 24  >= now()) throw errorFreezeFeeAddressChange;
      ctxFeeAddress = inMsgBody.loadAddress();
      ctxFreezeTime = 0;
      saveData();
    }

  throw 999;
}

get admin(): (slice) {
  loadData();
  return (ctxAdminAddress);
}