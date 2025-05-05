import { Address, beginCell, Cell, Contract, contractAddress, ContractProvider, Sender, SendMode } from '@ton/core';

export type MarketConfig = {
    ctxAdminAddress: Address;
    ctxFeeAddress: Address;
};

export function marketConfigToCell(config: MarketConfig): Cell {
    return beginCell()
        .storeAddress(config.ctxAdminAddress)
        .storeAddress(config.ctxFeeAddress)
    .endCell();
}

export class Market implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new Market(address);
    }

    static createFromConfig(config: MarketConfig, code: Cell, workchain = 0) {
        const data = marketConfigToCell(config);
        const init = { code, data };
        return new Market(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }
}
