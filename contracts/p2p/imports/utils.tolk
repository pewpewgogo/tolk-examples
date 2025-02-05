// Jetton utils
@inline
fun packJettonWalletData(balance: int, ownerAddress: slice, jettonMasterAddress: slice, jettonWalletCode: cell): cell {
  return  beginCell()
  .storeCoins(balance)
  .storeSlice(ownerAddress)
  .storeSlice(jettonMasterAddress)
  .storeRef(jettonWalletCode)
  .endCell();
}

@inline
fun calculateJettonWalletStateInit(ownerAddress: slice, jettonMasterAddress: slice, jettonWalletCode: cell): cell {
  return beginCell()
  .storeUint(0, 2)
  .storeDict(jettonWalletCode)
  .storeDict(packJettonWalletData(0, ownerAddress, jettonMasterAddress, jettonWalletCode))
  .storeUint(0, 1)
  .endCell();
}

@inline
fun calculateAddress(stateInit: cell): slice {
  return beginCell().storeUint(4, 3)
  .storeInt(0, 8)
  .storeUint(cellHash(stateInit), 256)
  .endCell()
  .beginParse();
}

@inline
fun calculateUserJettonWalletAddress(ownerAddress: slice, jettonMasterAddress: slice, jettonWalletCode: cell): slice {
  return calculateAddress(calculateJettonWalletStateInit(ownerAddress, jettonMasterAddress, jettonWalletCode));
}